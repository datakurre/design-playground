module GitLab.Branches exposing (Branch, branchDecoder, createBranch, listBranches, pageSize)

import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Decode as Decode exposing (Decoder)
import Url


type alias Branch =
    { name : String
    , commitId : String
    , default : Bool
    , protected : Bool
    }


{-| `default` and `protected` are required rather than optional-with-a-`False`
default, and that is the load-bearing decision in this module: the app decides
whether a branch may be edited from these two fields, and a silently defaulted
`protected = False` would present a protected branch as writable — the unsafe
direction to be wrong in.

Required means a schema surprise fails the whole list instead. `Model.branches`
stays `Nothing`, `Guard` reads that as "nothing is known to be writable", and
the app goes read-only and says so. Loud and closed beats quiet and open.

-}
branchDecoder : Decoder Branch
branchDecoder =
    Decode.map4 Branch
        (Decode.field "name" Decode.string)
        (Decode.at [ "commit", "id" ] Decode.string)
        (Decode.field "default" Decode.bool)
        (Decode.field "protected" Decode.bool)


{-| How many branches one request asks for. This used to send no `per_page` at
all, so GitLab's default of 20 applied — and a branch beyond the first twenty
was not merely hidden from the picker. `Guard.writability` fails closed on a
branch it can't find in the list, so being on branch twenty-one made the whole
app read-only, with a message about an unknown branch.
-}
pageSize : Int
pageSize =
    100


listBranches : String -> Int -> Int -> (Result Http.Error (List Branch) -> msg) -> Request msg
listBranches token projectId page toMsg =
    { method = "GET"
    , url =
        "https://gitlab.com/api/v4/projects/"
            ++ String.fromInt projectId
            ++ "/repository/branches?per_page="
            ++ String.fromInt pageSize
            ++ "&page="
            ++ String.fromInt page
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
