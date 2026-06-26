module GitLabDecodersTest exposing (suite)

import Expect
import GitLab.Branches exposing (branchDecoder)
import GitLab.Files exposing (treeItemDecoder)
import GitLab.Projects exposing (projectDecoder)
import Json.Decode as Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "GitLab API Decoders"
        [ describe "treeItemDecoder"
            [ test "decodes a valid TreeItem JSON" <|
                \_ ->
                    let
                        json =
                            """
                            {
                                "id": "a1b2c3d4",
                                "name": "package.json",
                                "type": "blob",
                                "path": "package.json",
                                "mode": "100644"
                            }
                            """
                    in
                    case Decode.decodeString treeItemDecoder json of
                        Ok item ->
                            Expect.all
                                [ \i -> Expect.equal "a1b2c3d4" i.id
                                , \i -> Expect.equal "package.json" i.name
                                , \i -> Expect.equal "blob" i.type_
                                , \i -> Expect.equal "package.json" i.path
                                , \i -> Expect.equal "100644" i.mode
                                ]
                                item

                        Err err ->
                            Expect.fail (Decode.errorToString err)
            ]
        , describe "projectDecoder"
            [ test "decodes a valid Project JSON" <|
                \_ ->
                    let
                        json =
                            """
                            {
                                "id": 12345,
                                "name": "design-playground",
                                "path_with_namespace": "username/design-playground",
                                "default_branch": "main"
                            }
                            """
                    in
                    case Decode.decodeString projectDecoder json of
                        Ok project ->
                            Expect.all
                                [ \p -> Expect.equal 12345 p.id
                                , \p -> Expect.equal "design-playground" p.name
                                , \p -> Expect.equal "username/design-playground" p.pathWithNamespace
                                , \p -> Expect.equal "main" p.defaultBranch
                                ]
                                project

                        Err err ->
                            Expect.fail (Decode.errorToString err)
            ]
        , describe "branchDecoder"
            [ test "decodes a valid Branch JSON" <|
                \_ ->
                    let
                        json =
                            """
                            {
                                "name": "main",
                                "commit": {
                                    "id": "7b5c3df"
                                }
                            }
                            """
                    in
                    case Decode.decodeString branchDecoder json of
                        Ok branch ->
                            Expect.all
                                [ \b -> Expect.equal "main" b.name
                                , \b -> Expect.equal "7b5c3df" b.commitId
                                ]
                                branch

                        Err err ->
                            Expect.fail (Decode.errorToString err)
            ]
        ]
