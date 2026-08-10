module GitLab.Commits exposing (Action, CommitPayload, createCommit)

import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Encode as Encode


type alias Action =
    { action : String -- "create", "delete", "move", "update", "chmod"
    , filePath : String
    , content : Maybe String
    }


type alias CommitPayload =
    { branch : String
    , commitMessage : String
    , actions : List Action
    }


encodeAction : Action -> Encode.Value
encodeAction action =
    let
        baseList =
            [ ( "action", Encode.string action.action )
            , ( "file_path", Encode.string action.filePath )
            ]

        withContent =
            case action.content of
                Just content ->
                    ( "content", Encode.string content ) :: baseList

                Nothing ->
                    baseList
    in
    Encode.object withContent


encodeCommitPayload : CommitPayload -> Encode.Value
encodeCommitPayload payload =
    Encode.object
        [ ( "branch", Encode.string payload.branch )
        , ( "commit_message", Encode.string payload.commitMessage )
        , ( "actions", Encode.list encodeAction payload.actions )
        ]


createCommit : String -> Int -> CommitPayload -> (Result Http.Error () -> msg) -> Request msg
createCommit token projectId payload toMsg =
    { method = "POST"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/commits"
    , headers = GitLab.Request.authorized token
    , body = JsonBody (encodeCommitPayload payload)
    , expect = Http.expectWhatever toMsg
    }
