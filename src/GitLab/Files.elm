module GitLab.Files exposing (TreeItem, getFileRaw, listTree, treeItemDecoder)

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


listTree : String -> Int -> String -> (Result Http.Error (List TreeItem) -> msg) -> Cmd msg
listTree token projectId ref toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/tree?ref=" ++ ref
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (Decode.list treeItemDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


getFileRaw : String -> Int -> String -> String -> (Result Http.Error String -> msg) -> Cmd msg
getFileRaw token projectId ref filePath toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/files/" ++ Url.percentEncode filePath ++ "/raw?ref=" ++ ref
        , body = Http.emptyBody
        , expect = Http.expectString toMsg
        , timeout = Nothing
        , tracker = Nothing
        }
