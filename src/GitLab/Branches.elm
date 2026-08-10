module GitLab.Branches exposing (Branch, branchDecoder, createBranch, listBranches)

import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Decode as Decode exposing (Decoder)
import Url


type alias Branch =
    { name : String
    , commitId : String
    }


branchDecoder : Decoder Branch
branchDecoder =
    Decode.map2 Branch
        (Decode.field "name" Decode.string)
        (Decode.at [ "commit", "id" ] Decode.string)


listBranches : String -> Int -> (Result Http.Error (List Branch) -> msg) -> Request msg
listBranches token projectId toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/repository/branches"
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg (Decode.list branchDecoder)
    }


{-| The name and the ref are percent-encoded because git allows characters in a
ref name that mean something else in a query string. Interpolated raw, a branch
called `a&b` ended the `branch` parameter and started another one.
-}
createBranch : String -> Int -> String -> String -> (Result Http.Error Branch -> msg) -> Request msg
createBranch token projectId branchName ref toMsg =
    { method = "POST"
    , url =
        "https://gitlab.com/api/v4/projects/"
            ++ String.fromInt projectId
            ++ "/repository/branches?branch="
            ++ Url.percentEncode branchName
            ++ "&ref="
            ++ Url.percentEncode ref
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg branchDecoder
    }
