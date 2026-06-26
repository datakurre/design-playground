module MergeRequestsTest exposing (suite)

import Expect
import GitLab.MergeRequests exposing (decoder)
import Json.Decode as Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "GitLab.MergeRequests Codecs"
        [ test "decodes a valid Merge Request JSON" <|
            \_ ->
                let
                    jsonStr =
                        """
                        {
                            "id": 1,
                            "iid": 1,
                            "project_id": 3,
                            "title": "test1",
                            "state": "merged",
                            "created_at": "2017-04-29T08:46:00Z",
                            "web_url": "http://example.com/example/example/merge_requests/1"
                        }
                        """

                    expected =
                        { id = 1
                        , iid = 1
                        , title = "test1"
                        , state = "merged"
                        , webUrl = "http://example.com/example/example/merge_requests/1"
                        }
                in
                Decode.decodeString decoder jsonStr
                    |> Expect.equal (Ok expected)
        ]
