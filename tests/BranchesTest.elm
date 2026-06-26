module BranchesTest exposing (suite)

import Expect
import GitLab.Branches exposing (Branch, branchDecoder)
import Json.Decode as Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "GitLab.Branches Codecs"
        [ test "decodes a valid Branch JSON" <|
            \_ ->
                let
                    jsonStr =
                        """
                        {
                            "name": "master",
                            "commit": {
                                "id": "7b5c3cc8be40ee161ae89a06bba6229da1032a0c"
                            }
                        }
                        """

                    expected =
                        { name = "master"
                        , commitId = "7b5c3cc8be40ee161ae89a06bba6229da1032a0c"
                        }
                in
                Decode.decodeString branchDecoder jsonStr
                    |> Expect.equal (Ok expected)
        ]
