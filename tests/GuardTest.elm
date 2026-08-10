module GuardTest exposing (suite)

{-| The read-only rule, tested where it is decided rather than where it is
enforced.

`Guard.writability` is the only thing in the app that compares a branch to
`defaultBranch` or reads `protected`, so this file is the whole truth table for
"may I edit here". `UpdateTest` covers what `update` does with the answer.

-}

import Expect
import Guard exposing (Reason(..), Writability(..))
import Test exposing (Test, describe, test)
import Types exposing (Msg(..))
import Url



-- THE TESTS


suite : Test
suite =
    describe "Guard"
        [ describe "writability decides in order, strongest reason first"
            [ test "no repository open" <|
                \_ ->
                    Guard.writability signedOut
                        |> Expect.equal (ReadOnly NoRepository)
            , test "a repository but no branch chosen yet" <|
                \_ ->
                    Guard.writability signedIn
                        |> Expect.equal (ReadOnly NoBranch)
            , test "the project's default branch, answered before the branch list arrives" <|
                \_ ->
                    -- The window this covers is real: a deep link renders the
                    -- editor with Save on screen while GotBranches is still in
                    -- flight, and the answer has to be "no" the whole time.
                    Guard.writability { signedIn | currentBranch = Just "main" }
                        |> Expect.equal (ReadOnly (DefaultBranch "main"))
            , test "a branch the loaded list does not name" <|
                \_ ->
                    Guard.writability { onBranch | currentBranch = Just "typo-x" }
                        |> Expect.equal (ReadOnly (BranchesUnknown "typo-x"))
            , test "a branch chosen before the list has loaded at all" <|
                \_ ->
                    -- Fail closed: not knowing is not the same as knowing it is
                    -- fine, and this is the direction to be wrong in.
                    Guard.writability { onBranch | branches = Nothing }
                        |> Expect.equal (ReadOnly (BranchesUnknown "feature-x"))
            , test "a protected branch that is not the default one" <|
                \_ ->
                    Guard.writability { onBranch | currentBranch = Just "release/1.0" }
                        |> Expect.equal (ReadOnly (ProtectedBranch "release/1.0"))
            , test "a branch flagged default by GitLab even though the project record disagrees" <|
                \_ ->
                    -- Renaming the default branch leaves the cached project
                    -- record stale; the branch list is the fresher fact.
                    Guard.writability { onBranch | currentBranch = Just "trunk" }
                        |> Expect.equal (ReadOnly (DefaultBranch "trunk"))
            , test "a branch of your own is writable" <|
                \_ ->
                    Guard.writability onBranch
                        |> Expect.equal (Writable "feature-x")
            ]
        , describe "the two questions callers actually ask"
            [ test "writableBranch names the commit target on a branch of your own" <|
                \_ ->
                    Guard.writableBranch onBranch
                        |> Expect.equal (Just "feature-x")
            , test "writableBranch refuses rather than falling back to the default branch" <|
                \_ ->
                    -- The bug this replaces: every write site spelled
                    -- `Maybe.withDefault project.defaultBranch`, so refusing to
                    -- answer meant committing to main.
                    Guard.writableBranch { signedIn | currentBranch = Just "main" }
                        |> Expect.equal Nothing
            , test "readOnly is Nothing exactly when writableBranch is Just" <|
                \_ ->
                    ( Guard.readOnly onBranch, Guard.readOnly signedIn )
                        |> Expect.equal ( Nothing, Just NoBranch )
            ]
        , describe "the refusal names the branch and the remedy"
            [ test "the default branch" <|
                \_ ->
                    Guard.refusal (DefaultBranch "main")
                        |> Expect.equal "You're on main, the default branch — create a branch, then make your changes on it"
            , test "a protected branch reads differently, because the cause is different" <|
                \_ ->
                    Guard.refusal (ProtectedBranch "release/1.0")
                        |> Expect.notEqual (Guard.refusal (DefaultBranch "release/1.0"))
            , test "every reason describes itself without an empty string" <|
                \_ ->
                    [ NoRepository, NoBranch, BranchesUnknown "x", DefaultBranch "main", ProtectedBranch "release/1.0" ]
                        |> List.map (Guard.describe >> String.isEmpty)
                        |> Expect.equal [ False, False, False, False, False ]
            ]
        , describe "isMutating"
            [ test "the escape hatch is never blocked" <|
                \_ ->
                    -- If any of these ever classifies as mutating, a user who
                    -- lands on the default branch has no way off it short of
                    -- reloading the page. That is what this test is for.
                    [ SwitchBranch "feature-x"
                    , UpdateNewBranchName "feature/x"
                    , CreateBranch
                    , UpdateMRTitle "Warmer colors"
                    , CreateMergeRequest
                    , Logout
                    , UnselectProject
                    ]
                        |> List.map Guard.isMutating
                        |> Expect.equal (List.repeat 7 False)
            , test "every write button mutates" <|
                \_ ->
                    [ SaveTokens
                    , SaveComponent
                    , SaveScreen
                    , SaveContract
                    , DeleteTheme "Dark"
                    , DeleteComponent "Button"
                    , DeleteScreen "Home"
                    , DeleteContract "Button"
                    , RunExportPipeline
                    ]
                        |> List.map Guard.isMutating
                        |> Expect.equal (List.repeat 9 True)
            , test "local edits mutate too, because a later save would write them" <|
                \_ ->
                    [ CreateTheme
                    , CreateToken
                    , DeleteToken [ "color", "brand" ]
                    , CreateComponent
                    , AddComponentVariant
                    , AddLayoutStack []
                    , CreateScreen
                    , AddContractRule
                    ]
                        |> List.map Guard.isMutating
                        |> Expect.equal (List.repeat 8 True)
            , test "responses from GitLab are never mutations, or nothing could load" <|
                \_ ->
                    [ GotTokensFile (Ok "{}")
                    , GotThemesTree "main" (Ok [])
                    , GotComponentsTree "main" (Ok [])
                    , GotScreensTree "main" (Ok [])
                    , GotContractFile "contracts.json" (Ok "{}")
                    , GotBranches (Ok [])
                    ]
                        |> List.map Guard.isMutating
                        |> Expect.equal (List.repeat 6 False)
            , test "drafts, filters, selections and navigation stay live" <|
                \_ ->
                    [ UpdateNewTokenPath "color.brand.primary"
                    , UpdateNewComponentName "Button"
                    , UpdateNewContractRuleField "min" "4"
                    , UpdateTokenSearch "brand"
                    , ClearTokenFilters
                    , SelectTheme (Just "Dark")
                    , ToggleExportTarget "css"
                    , SwitchTab Types.TokenStudio
                    , JumpToComponent "Button"
                    ]
                        |> List.map Guard.isMutating
                        |> Expect.equal (List.repeat 9 False)
            ]
        ]



-- FIXTURES


signedOut : Types.Model
signedOut =
    Types.initial (url "#/")
        { token = Just "secret", pkceChallenge = "challenge", pkceVerifier = "verifier" }


{-| A repository open, and nothing yet known about its branches — which is what
the app looks like for the moment between opening a project and `GotBranches`
answering.
-}
signedIn : Types.Model
signedIn =
    { signedOut
        | selectedProject =
            Just
                { id = 7
                , name = "design"
                , pathWithNamespace = "acme/design"
                , defaultBranch = "main"
                }
    }


{-| On a branch of your own, with the branch list loaded. `trunk` is flagged
default by GitLab while the project record still says `main`, which is what a
renamed default branch looks like from here.
-}
onBranch : Types.Model
onBranch =
    { signedIn
        | currentBranch = Just "feature-x"
        , branches =
            Just
                [ { name = "main", commitId = "aaa", default = False, protected = True }
                , { name = "trunk", commitId = "bbb", default = True, protected = True }
                , { name = "release/1.0", commitId = "ccc", default = False, protected = True }
                , { name = "feature-x", commitId = "ddd", default = False, protected = False }
                ]
    }


url : String -> Url.Url
url fragment =
    { protocol = Url.Https
    , host = "example.com"
    , port_ = Nothing
    , path = "/"
    , query = Nothing
    , fragment = String.split "#" fragment |> List.drop 1 |> List.head
    }
