module GitLab.MergeRequests exposing (MergeRequest, createMergeRequest, decoder)

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


createMergeRequest : String -> Int -> String -> String -> String -> (Result Http.Error MergeRequest -> msg) -> Cmd msg
createMergeRequest token projectId sourceBranch targetBranch title toMsg =
    let
        payload =
            Encode.object
                [ ( "source_branch", Encode.string sourceBranch )
                , ( "target_branch", Encode.string targetBranch )
                , ( "title", Encode.string title )
                ]
    in
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/projects/" ++ String.fromInt projectId ++ "/merge_requests"
        , body = Http.jsonBody payload
        , expect = Http.expectJson toMsg decoder
        , timeout = Nothing
        , tracker = Nothing
        }
