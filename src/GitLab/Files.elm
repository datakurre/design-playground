module GitLab.Files exposing (FileContent, TreeItem, getFileRaw, listTree, listTreeAtPath, treeItemDecoder, treePageSize)

import Dict
import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Decode as Decode exposing (Decoder)
import Url


type alias TreeItem =
    { id : String
    , name : String
    , type_ : String
    , path : String
    , mode : String
    }


treeItemDecoder : Decoder TreeItem
treeItemDecoder =
    Decode.map5 TreeItem
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "type" Decode.string)
        (Decode.field "path" Decode.string)
        (Decode.field "mode" Decode.string)


{-| How many tree entries one request asks for. GitLab's own default is 20,
which is the kind of default that looks fine until a design system has its
twenty-first component. Exposed because the caller has to compare a page's
length against it to know whether to ask for another one.
-}
treePageSize : Int
treePageSize =
    100


{-| The whole tree at a ref, one page at a time.

`recursive=true` is what makes nested paths — `exports/variables.css`,
`components/Button.contract.json` — appear at all. Without it the listing stops
at the top level, and the export pipeline's "does this file already exist?"
check compared `exports/variables.css` against an entry that only ever said
`exports`, answered no every time, and sent `create` on a file that was already
there.

The ref is percent-encoded for the same reason `GitLab.Branches.createBranch`
encodes it: git allows characters in a ref name that mean something else in a
query string. The app suggests `feature/`, `fix/` and friends as branch
prefixes, so a slash in a ref is the common case, not the exotic one —
interpolated raw it truncated the parameter and the read came back from the
wrong branch, or not at all.

-}
listTree : String -> Int -> String -> Int -> (Result Http.Error (List TreeItem) -> msg) -> Request msg
listTree token projectId ref page toMsg =
    { method = "GET"
    , url =
        "https://gitlab.com/api/v4/projects/"
            ++ String.fromInt projectId
            ++ "/repository/tree?recursive=true&ref="
            ++ Url.percentEncode ref
            ++ "&per_page="
            ++ String.fromInt treePageSize
            ++ "&page="
            ++ String.fromInt page
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg (Decode.list treeItemDecoder)
    }


listTreeAtPath : String -> Int -> String -> String -> (Result Http.Error (List TreeItem) -> msg) -> Request msg
listTreeAtPath token projectId ref path toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/tree?ref=" ++ Url.percentEncode ref ++ "&path=" ++ Url.percentEncode path
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg (Decode.list treeItemDecoder)
    }


{-| A file, and the commit it was last changed in.

The commit id is what makes a save safe. GitLab's commits API accepts a
`last_commit_id` per action and refuses the write if the file has moved on
since — but only if it is told which version the edit was based on, and the
only moment that is knowable is when the file is read.

`Nothing` means GitLab didn't send the header. That is not expected —
`X-Gitlab-Last-Commit-Id` is in the endpoint's `Access-Control-Expose-Headers`
— but a missing version has to mean "save without the check" rather than
"can't save", or one absent header locks the user out of their own repository.

-}
type alias FileContent =
    { content : String
    , lastCommitId : Maybe String
    }


getFileRaw : String -> Int -> String -> String -> (Result Http.Error FileContent -> msg) -> Request msg
getFileRaw token projectId ref filePath toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/files/" ++ Url.percentEncode filePath ++ "/raw?ref=" ++ Url.percentEncode ref
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = expectFileContent toMsg
    }


{-| `Http.expectString` gives the body and nothing else; the version lives in a
response header, so the read has to go one level down.
-}
expectFileContent : (Result Http.Error FileContent -> msg) -> Http.Expect msg
expectFileContent toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ metadata _ ->
                    Err (Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ metadata body ->
                    Ok
                        { content = body
                        , lastCommitId = header "x-gitlab-last-commit-id" metadata
                        }


{-| Browsers lowercase header names in `getAllResponseHeaders`, but nothing in
the type says so, and a case-sensitive lookup that is right by accident is the
kind that stops being right silently.
-}
header : String -> Http.Metadata -> Maybe String
header name metadata =
    metadata.headers
        |> Dict.toList
        |> List.filter (\( k, _ ) -> String.toLower k == String.toLower name)
        |> List.head
        |> Maybe.map Tuple.second
