module GitLab.Files exposing (TreeItem, getFileRaw, listTree, listTreeAtPath, treeItemDecoder)

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


{-| The ref is percent-encoded for the same reason
`GitLab.Branches.createBranch` encodes it: git allows characters in a ref name
that mean something else in a query string. The app suggests `feature/`, `fix/`
and friends as branch prefixes, so a slash in a ref is the common case, not the
exotic one — interpolated raw it truncated the parameter and the read came back
from the wrong branch, or not at all.
-}
listTree : String -> Int -> String -> (Result Http.Error (List TreeItem) -> msg) -> Request msg
listTree token projectId ref toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/tree?ref=" ++ Url.percentEncode ref
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


getFileRaw : String -> Int -> String -> String -> (Result Http.Error String -> msg) -> Request msg
getFileRaw token projectId ref filePath toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/files/" ++ Url.percentEncode filePath ++ "/raw?ref=" ++ Url.percentEncode ref
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectString toMsg
    }
