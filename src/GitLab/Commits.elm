module GitLab.Commits exposing (Action, CommitError(..), CommitPayload, action, classifyError, createCommit)

import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Decode as Decode
import Json.Encode as Encode


{-| One file change in a commit.

`lastCommitId` is the version of the file the edit was based on, and sending it
is what turns a write from "overwrite whatever is there" into "overwrite this,
or tell me it moved". Without it two tabs, two people, or one edit made in
GitLab's own UI after the app loaded all silently clobber each other, and the
loser never finds out.

It is `Nothing` for a `create` — there is no previous version to be based on —
and for the rare read that came back without the header. Use `action` rather
than building this record by hand, so a new call site can't quietly omit it.

-}
type alias Action =
    { action : String -- "create", "delete", "move", "update", "chmod"
    , filePath : String
    , content : Maybe String
    , lastCommitId : Maybe String
    }


{-| The usual case: a create or an update of one file, at a known version.

GitLab rejects `last_commit_id` on a `create`, so this drops it there rather
than making every caller remember to.

-}
action : { action : String, filePath : String, content : Maybe String, lastCommitId : Maybe String } -> Action
action fields =
    { action = fields.action
    , filePath = fields.filePath
    , content = fields.content
    , lastCommitId =
        if fields.action == "create" then
            Nothing

        else
            fields.lastCommitId
    }


type alias CommitPayload =
    { branch : String
    , commitMessage : String
    , actions : List Action
    }


encodeAction : Action -> Encode.Value
encodeAction act =
    Encode.object
        (List.filterMap identity
            [ Just ( "action", Encode.string act.action )
            , Just ( "file_path", Encode.string act.filePath )
            , Maybe.map (\c -> ( "content", Encode.string c )) act.content
            , Maybe.map (\c -> ( "last_commit_id", Encode.string c )) act.lastCommitId
            ]
        )


encodeCommitPayload : CommitPayload -> Encode.Value
encodeCommitPayload payload =
    Encode.object
        [ ( "branch", Encode.string payload.branch )
        , ( "commit_message", Encode.string payload.commitMessage )
        , ( "actions", Encode.list encodeAction payload.actions )
        ]


{-| Why a commit didn't happen.

`Http.expectWhatever` used to discard the response body, which is exactly where
GitLab explains itself — so a protected branch, an expired token and a file
that changed underneath all arrived as the same `Err ()` and came out as
"Couldn't save to GitLab". Each of these has a different thing for the user to
do about it.

-}
type CommitError
    = StaleFile String
    | Unauthorized
    | Forbidden
    | OtherError String


{-| GitLab reports a stale write as a 400 whose message names the file. There is
no machine-readable code for it, so the text is what there is; the check is
deliberately loose, because a 400 from a commit that mentions a change conflict
is not something the app should treat as a generic failure just because the
wording moved.
-}
classifyError : Http.Error -> CommitError
classifyError error =
    case error of
        Http.BadStatus 401 ->
            Unauthorized

        Http.BadStatus 403 ->
            Forbidden

        Http.BadBody body ->
            classifyBody body

        _ ->
            OtherError "Couldn't save to GitLab."


classifyBody : String -> CommitError
classifyBody body =
    let
        message =
            Decode.decodeString (Decode.field "message" Decode.string) body
                |> Result.withDefault body

        lowered =
            String.toLower message
    in
    if String.contains "changed" lowered || String.contains "conflict" lowered then
        StaleFile message

    else if String.contains "protected" lowered then
        Forbidden

    else
        OtherError message


createCommit : String -> Int -> CommitPayload -> (Result Http.Error () -> msg) -> Request msg
createCommit token projectId payload toMsg =
    { method = "POST"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/commits"
    , headers = GitLab.Request.authorized token
    , body = JsonBody (encodeCommitPayload payload)
    , expect = expectCommit toMsg
    }


{-| Keeps a failing response's body, as `Http.BadBody`, so `classifyError` has
something to read. `Http.expectWhatever` maps every failure onto a status code
and throws the rest away.
-}
expectCommit : (Result Http.Error () -> msg) -> Http.Expect msg
expectCommit toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ metadata body ->
                    if metadata.statusCode == 400 then
                        Err (Http.BadBody body)

                    else
                        Err (Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ _ _ ->
                    Ok ()
