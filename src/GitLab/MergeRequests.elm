module GitLab.MergeRequests exposing (MergeRequest, createMergeRequest, decoder, listMergeRequests, pageSize)

import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type alias MergeRequest =
    { id : Int
    , iid : Int
    , title : String
    , state : String
    , webUrl : String
    }


decoder : Decoder MergeRequest
decoder =
    Decode.map5 MergeRequest
        (Decode.field "id" Decode.int)
        (Decode.field "iid" Decode.int)
        (Decode.field "title" Decode.string)
        (Decode.field "state" Decode.string)
        (Decode.field "web_url" Decode.string)


{-| Only the open ones: the panel exists to answer "what of mine is waiting for
review", and a busy repository's merged history would bury that.

`per_page` was 20 with no way to ask for more, which is a cap rather than a
default — a repository with twenty-one open merge requests simply didn't show
the twenty-first.

-}
listMergeRequests : String -> Int -> Int -> (Result Http.Error (List MergeRequest) -> msg) -> Request msg
listMergeRequests token projectId page toMsg =
    { method = "GET"
    , url =
        "https://gitlab.com/api/v4/projects/"
            ++ String.fromInt projectId
            ++ "/merge_requests?state=opened&per_page="
            ++ String.fromInt pageSize
            ++ "&page="
            ++ String.fromInt page
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg (Decode.list decoder)
    }


{-| How many merge requests one request asks for.
-}
pageSize : Int
pageSize =
    100


createMergeRequest : String -> Int -> String -> String -> String -> (Result Http.Error MergeRequest -> msg) -> Request msg
createMergeRequest token projectId sourceBranch targetBranch title toMsg =
    { method = "POST"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/merge_requests"
    , headers = GitLab.Request.authorized token
    , body =
        JsonBody
            (Encode.object
                [ ( "source_branch", Encode.string sourceBranch )
                , ( "target_branch", Encode.string targetBranch )
                , ( "title", Encode.string title )
                ]
            )
    , expect = Http.expectJson toMsg decoder
    }
