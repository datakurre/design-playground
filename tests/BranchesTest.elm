module BranchesTest exposing (suite)

import Expect
import GitLab.Branches exposing (branchDecoder)
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
                            },
                            "default": true,
                            "protected": true
                        }
                        """

                    expected =
                        { name = "master"
                        , commitId = "7b5c3cc8be40ee161ae89a06bba6229da1032a0c"
                        , default = True
                        , protected = True
                        }
                in
                Decode.decodeString branchDecoder jsonStr
                    |> Expect.equal (Ok expected)
        , test "a branch that is neither default nor protected is writable" <|
            \_ ->
                let
                    jsonStr =
                        """
                        {
                            "name": "feature/new-colors",
                            "commit": { "id": "abc123" },
                            "default": false,
                            "protected": false
                        }
                        """

                    expected =
                        { name = "feature/new-colors"
                        , commitId = "abc123"
                        , default = False
                        , protected = False
                        }
                in
                Decode.decodeString branchDecoder jsonStr
                    |> Expect.equal (Ok expected)
        , test "a protected branch that is not the default one still decodes as protected" <|
            \_ ->
                let
                    jsonStr =
                        """
                        {
                            "name": "release/1.0",
                            "commit": { "id": "def456" },
                            "default": false,
                            "protected": true
                        }
                        """
                in
                Decode.decodeString branchDecoder jsonStr
                    |> Result.map (\b -> ( b.default, b.protected ))
                    |> Expect.equal (Ok ( False, True ))
        , test "a payload without \"protected\" fails rather than defaulting to writable" <|
            \_ ->
                -- The whole read-only rule rests on these two fields, and a
                -- missing one defaulting to False would make a protected
                -- branch look writable. Failing the decode leaves `branches`
                -- as Nothing, which Guard reads as read-only.
                let
                    jsonStr =
                        """
                        {
                            "name": "main",
                            "commit": { "id": "abc123" },
                            "default": true
                        }
                        """
                in
                Decode.decodeString branchDecoder jsonStr
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]
