module GitLab.Branches exposing (Branch, listBranches, branchDecoder)

import Http
import Json.Decode as Decode exposing (Decoder)


type alias Branch =
    { name : String
    , commitId : String
    }


branchDecoder : Decoder Branch
branchDecoder =
    Decode.map2 Branch
        (Decode.field "name" Decode.string)
        (Decode.at [ "commit", "id" ] Decode.string)


listBranches : String -> Int -> (Result Http.Error (List Branch) -> msg) -> Cmd msg
listBranches token projectId toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/branches"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (Decode.list branchDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }
