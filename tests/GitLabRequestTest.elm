module GitLabRequestTest exposing (suite)

{-| What the app actually sends to GitLab.

`tests/GitLabDecodersTest.elm` covers reading responses. This covers the other
half — the URLs, headers and bodies the requests are built from — which was
unreachable while these functions returned an opaque `Cmd`.

The bodies matter most. Whether a save is a `create` or an `update`, which file
path it writes and which branch it lands on are all decisions made in `Update`
and expressed only here, and none of them had a test.

Note a `Request` carries an `Http.Expect`, which contains a function, so `==` on
a whole request throws at runtime. Assert on the fields.

-}

import Expect
import GitLab.Branches
import GitLab.Commits
import GitLab.Files
import GitLab.MergeRequests
import GitLab.Projects
import GitLab.Request
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)


type Msg
    = Ignored


suite : Test
suite =
    describe "GitLab requests"
        [ describe "authorization"
            [ test "every call carries the bearer token" <|
                \_ ->
                    (GitLab.Projects.listProjects "secret" 1 (always Ignored)).headers
                        |> Expect.equal [ ( "Authorization", "Bearer secret" ) ]
            , test "listing a tree carries it too" <|
                \_ ->
                    (GitLab.Files.listTree "secret" 7 "main" (always Ignored)).headers
                        |> Expect.equal [ ( "Authorization", "Bearer secret" ) ]
            ]
        , describe "urls"
            [ test "a project path goes in as one percent-encoded segment, slashes and all" <|
                \_ ->
                    (GitLab.Projects.getProject "t" "acme/design" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/acme%2Fdesign"
            , test "a nested namespace encodes every slash" <|
                \_ ->
                    (GitLab.Projects.getProject "t" "acme/team/design" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/acme%2Fteam%2Fdesign"
            , test "listing a tree asks for the ref it was given" <|
                \_ ->
                    -- Not project.defaultBranch: switching branches used to show
                    -- the default branch's contents under the new branch's name.
                    (GitLab.Files.listTree "t" 7 "feature-x" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/tree?ref=feature-x"
            , test "listing a subdirectory encodes the path but keeps the ref readable" <|
                \_ ->
                    (GitLab.Files.listTreeAtPath "t" 7 "main" "components" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/tree?ref=main&path=components"
            , test "a file path is encoded as one segment" <|
                \_ ->
                    (GitLab.Files.getFileRaw "t" 7 "main" "components/Button.json" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/files/components%2FButton.json/raw?ref=main"
            , test "creating a branch encodes the name, so a slash in it survives" <|
                \_ ->
                    -- Git allows & and % in a ref name. Interpolated raw, "a&b"
                    -- would have ended the branch parameter and started another.
                    (GitLab.Branches.createBranch "t" 7 "feature/x" "main" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/branches?branch=feature%2Fx&ref=main"
            , test "creating a branch encodes an ampersand in the name" <|
                \_ ->
                    (GitLab.Branches.createBranch "t" 7 "a&b" "main" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/branches?branch=a%26b&ref=main"
            , test "reading a tree encodes the ref, so a slash in a branch name survives" <|
                \_ ->
                    -- createBranch has always encoded the ref; the read side
                    -- interpolated it raw, so every "feature/x" branch the app
                    -- itself suggests creating was unreadable afterwards.
                    (GitLab.Files.listTree "t" 7 "feature/x" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/tree?ref=feature%2Fx"
            , test "reading a subdirectory encodes an ampersand in the ref" <|
                \_ ->
                    (GitLab.Files.listTreeAtPath "t" 7 "a&b" "components" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/tree?ref=a%26b&path=components"
            , test "reading a file encodes the ref as well as the path" <|
                \_ ->
                    (GitLab.Files.getFileRaw "t" 7 "feature/x" "tokens/tokens.json" (always Ignored)).url
                        |> Expect.equal "https://gitlab.com/api/v4/projects/7/repository/files/tokens%2Ftokens.json/raw?ref=feature%2Fx"
            ]
        , describe "commit payloads"
            [ test "carries the branch, the message and one action per file" <|
                \_ ->
                    commit
                        { branch = "feature-x"
                        , commitMessage = "Save tokens"
                        , actions =
                            [ { action = "update", filePath = "tokens/tokens.json", content = Just "{}" } ]
                        }
                        (Decode.map3 (\b m p -> ( b, m, p ))
                            (Decode.field "branch" Decode.string)
                            (Decode.field "commit_message" Decode.string)
                            (Decode.at [ "actions", "0", "file_path" ] Decode.string)
                        )
                        |> Expect.equal (Ok ( "feature-x", "Save tokens", "tokens/tokens.json" ))
            , test "a create says create" <|
                \_ ->
                    commit
                        { branch = "main"
                        , commitMessage = "Add"
                        , actions = [ { action = "create", filePath = "a.json", content = Just "{}" } ]
                        }
                        (Decode.at [ "actions", "0", "action" ] Decode.string)
                        |> Expect.equal (Ok "create")
            , test "content is sent when there is content" <|
                \_ ->
                    commit
                        { branch = "main"
                        , commitMessage = "Add"
                        , actions = [ { action = "create", filePath = "a.json", content = Just "hello" } ]
                        }
                        (Decode.at [ "actions", "0", "content" ] Decode.string)
                        |> Expect.equal (Ok "hello")
            , test "a delete omits content rather than sending null" <|
                \_ ->
                    commit
                        { branch = "main"
                        , commitMessage = "Delete"
                        , actions = [ { action = "delete", filePath = "a.json", content = Nothing } ]
                        }
                        (Decode.at [ "actions", "0" ] (Decode.maybe (Decode.field "content" Decode.string)))
                        |> Expect.equal (Ok Nothing)
            , test "several files go in one commit" <|
                \_ ->
                    commit
                        { branch = "main"
                        , commitMessage = "Export"
                        , actions =
                            [ { action = "update", filePath = "exports/variables.css", content = Just "" }
                            , { action = "create", filePath = "exports/tailwind.config.js", content = Just "" }
                            ]
                        }
                        (Decode.field "actions" (Decode.list (Decode.field "file_path" Decode.string)))
                        |> Expect.equal (Ok [ "exports/variables.css", "exports/tailwind.config.js" ])
            ]
        , describe "merge requests"
            [ test "opens from the current branch onto the default one" <|
                \_ ->
                    GitLab.MergeRequests.createMergeRequest "t" 7 "feature-x" "main" "Title" (always Ignored)
                        |> .body
                        |> GitLab.Request.bodyValue
                        |> Maybe.map
                            (Decode.decodeValue
                                (Decode.map3 (\s tgt title -> ( s, tgt, title ))
                                    (Decode.field "source_branch" Decode.string)
                                    (Decode.field "target_branch" Decode.string)
                                    (Decode.field "title" Decode.string)
                                )
                            )
                        |> Expect.equal (Just (Ok ( "feature-x", "main", "Title" )))
            , test "only open merge requests are listed" <|
                \_ ->
                    -- The panel answers "what of mine is waiting for review", and
                    -- a busy repository's merged history would bury that.
                    (GitLab.MergeRequests.listMergeRequests "t" 7 (always Ignored)).url
                        |> String.contains "state=opened"
                        |> Expect.equal True
            ]
        , describe "bodies that are not JSON"
            [ test "a GET sends no body" <|
                \_ ->
                    (GitLab.Files.listTree "t" 7 "main" (always Ignored)).body
                        |> GitLab.Request.bodyValue
                        |> Expect.equal Nothing
            ]
        ]


commit : GitLab.Commits.CommitPayload -> Decode.Decoder a -> Result Decode.Error a
commit payload decoder =
    GitLab.Commits.createCommit "t" 7 payload (always Ignored)
        |> .body
        |> GitLab.Request.bodyValue
        |> Maybe.map (Decode.decodeValue decoder)
        |> Maybe.withDefault (Err (Decode.Failure "the commit had no JSON body" Encode.null))
