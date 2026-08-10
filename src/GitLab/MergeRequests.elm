module GitLab.MergeRequests exposing (MergeRequest, createMergeRequest, decoder, listMergeRequests)

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
-}
listMergeRequests : String -> Int -> (Result Http.Error (List MergeRequest) -> msg) -> Request msg
listMergeRequests token projectId toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/merge_requests?state=opened&per_page=20"
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg (Decode.list decoder)
    }


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
