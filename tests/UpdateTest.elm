module UpdateTest exposing (suite)

{-| State transitions, run through `Update.update` itself.

None of this was reachable before: `Types.Model` carried a `Nav.Key`, which
cannot be constructed outside a running `Browser.application`, so `Types.initial`
could not be called from a test and neither could anything taking a `Model`.
`Effect` moved the key out to `Main`, and this is the payoff.

Assertions go through `Effect.requests` and `Effect.toList`, never
`Expect.equal` on a whole `Effect`: `SendRequest` carries an `Http.Expect`,
which contains a function, and Elm's `==` throws at runtime on functions. It
would work for `PushUrl` and `ClearToken`, which makes the trap worse rather
than better.

-}

import Browser
import Dict
import Effect exposing (Effect)
import Expect
import GitLab.Branches
import GitLab.Files
import GitLab.Request
import Guard
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Types exposing (Msg(..), StatusLevel(..))
import Update
import Url



-- THE TESTS


suite : Test
suite =
    describe "Update"
        [ describe "saving decides create vs update from what the repository already has"
            [ test "a component the repository does not have is created" <|
                \_ ->
                    onBranch
                        |> withComponent "Button"
                        |> (\m -> { m | existingComponents = [] })
                        |> save
                        |> commitField (Decode.at [ "actions", "0", "action" ] Decode.string)
                        |> Expect.equal (Ok "create")
            , test "a component the repository already has is updated" <|
                \_ ->
                    onBranch
                        |> withComponent "Button"
                        |> (\m -> { m | existingComponents = [ "Button" ] })
                        |> save
                        |> commitField (Decode.at [ "actions", "0", "action" ] Decode.string)
                        |> Expect.equal (Ok "update")
            , test "it writes the component's own file path" <|
                \_ ->
                    onBranch
                        |> withComponent "Button"
                        |> save
                        |> commitField (Decode.at [ "actions", "0", "file_path" ] Decode.string)
                        |> Expect.equal (Ok "components/Button.json")
            ]
        , describe "commits target the branch you are on"
            [ test "the current branch, not the project's default" <|
                \_ ->
                    onBranch
                        |> withComponent "Button"
                        |> save
                        |> commitField (Decode.field "branch" Decode.string)
                        |> Expect.equal (Ok "feature-x")
            , test "the branch the save was clicked on, even if you have since moved" <|
                \_ ->
                    -- Validation is a round trip through ajv in JavaScript, and
                    -- the branch picker stays live throughout it. Resolving the
                    -- branch when the result comes back committed one branch's
                    -- edit onto another.
                    let
                        ( pending, _ ) =
                            Update.update SaveComponent (withComponent "Button" onBranch)

                        ( _, effect ) =
                            Update.update
                                (GotSchemaValidationResult { valid = True, errors = [], context = Encode.null })
                                { pending | currentBranch = Just "release/1.0" }
                    in
                    commitField (Decode.field "branch" Decode.string) effect
                        |> Expect.equal (Ok "feature-x")
            , test "refuses to save when no branch is chosen, and sends nothing" <|
                \_ ->
                    -- This used to fall back to project.defaultBranch, which is
                    -- to say: not choosing a branch committed to main. The
                    -- fallback is gone, and its absence is the whole feature.
                    let
                        ( model, effect ) =
                            Update.update SaveComponent (withComponent "Button" signedIn)
                    in
                    ( Maybe.map Tuple.first model.commitStatus, Effect.requests effect |> List.length )
                        |> Expect.equal ( Just Failed, 0 )
            ]
        , describe "saving validates before it commits"
            [ test "SaveComponent asks for validation and issues no request yet" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update SaveComponent (withComponent "Button" onBranch)
                    in
                    ( Effect.requests effect |> List.length
                    , Effect.toList effect |> List.map isValidateSchema
                    )
                        |> Expect.equal ( 0, [ True ] )
            , test "a failed validation reports it and commits nothing" <|
                \_ ->
                    let
                        ( pending, _ ) =
                            Update.update SaveComponent (withComponent "Button" onBranch)

                        ( model, effect ) =
                            Update.update
                                (GotSchemaValidationResult
                                    { valid = False, errors = [ "root must have name" ], context = Encode.null }
                                )
                                pending
                    in
                    ( model.commitStatus, Effect.requests effect |> List.length )
                        |> Expect.equal
                            ( Just ( Failed, "Schema validation failed: root must have name" ), 0 )
            , test "a failed validation drops the pending commit rather than leaving it armed" <|
                \_ ->
                    let
                        ( pending, _ ) =
                            Update.update SaveComponent (withComponent "Button" onBranch)

                        ( model, _ ) =
                            Update.update
                                (GotSchemaValidationResult
                                    { valid = False, errors = [ "nope" ], context = Encode.null }
                                )
                                pending
                    in
                    model.pendingCommit |> Expect.equal Nothing
            ]
        , describe "signing out"
            [ test "clears the cached token and goes home" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update Logout signedIn
                    in
                    Effect.toList effect
                        |> Expect.equal [ Effect.ClearToken, Effect.PushUrl "#/" ]
            , test "forgets the repository it was in" <|
                \_ ->
                    -- A merge request from the last repository used to sit in
                    -- the panel under the next one. clearProjectState rebuilds
                    -- from Types.initial and carries a short list forward; a
                    -- field drifting onto that list would leak again, silently.
                    let
                        ( model, _ ) =
                            Update.update Logout (withComponent "Button" signedIn)
                    in
                    ( model.selectedProject, model.components, model.token )
                        |> Expect.equal ( Nothing, Nothing, Nothing )
            ]
        , describe "opening a repository"
            [ test "asks GitLab for the project by path, encoded as one segment" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens")) signedOutWithToken
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> List.filter (String.contains "/projects/acme")
                        |> Expect.equal [ "https://gitlab.com/api/v4/projects/acme%2Fdesign" ]
            ]
        , describe "switching branches"
            [ test "is a navigation, so the address bar and the model cannot disagree" <|
                \_ ->
                    -- Doing the work here instead would leave a branch change
                    -- invisible to the URL, un-shareable, and lost on reload —
                    -- which now means silently back on a read-only branch.
                    let
                        ( _, effect ) =
                            Update.update (SwitchBranch "feature-x") signedIn
                    in
                    Effect.toList effect
                        |> Expect.equal [ Effect.PushUrl "#/acme/design/tokens?branch=feature-x" ]
            , test "arriving on the new branch refetches everything at that ref" <|
                \_ ->
                    -- Not project.defaultBranch. The Msg comment in Types
                    -- records that this exact bug already happened once:
                    -- switching branches showed the default branch's contents
                    -- under the new branch's name.
                    let
                        ( _, effect ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens?branch=feature-x")) signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> List.filter (\u -> not (String.contains "ref=feature-x" u))
                        |> Expect.equal []
            , test "and refetches everything the branch owns, not some of it" <|
                \_ ->
                    -- Switching used to leave the contracts behind, so the
                    -- contracts panel kept showing the previous branch's rules.
                    -- Two requests now: the recursive tree, which every other
                    -- file is read from once it lands, and the tokens file,
                    -- whose path is fixed and needs no listing to find.
                    let
                        ( _, effect ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens?branch=feature-x")) signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> Expect.equal
                            [ "https://gitlab.com/api/v4/projects/7/repository/tree?recursive=true&ref=feature-x&per_page=100&page=1"
                            , "https://gitlab.com/api/v4/projects/7/repository/files/tokens%2Ftokens.json/raw?ref=feature-x"
                            ]
            , test "no request goes to a root contracts.json, because nothing writes one" <|
                \_ ->
                    -- It was a read-only second convention: every save writes
                    -- components/<name>.contract.json, and both paths decoded a
                    -- single Contract, so the root file could hold exactly one
                    -- component's rules and no UI could produce it.
                    let
                        ( _, effect ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens?branch=feature-x")) signedIn
                    in
                    Effect.requests effect
                        |> List.filter (\r -> String.contains "contracts.json" r.url)
                        |> Expect.equal []
            , test "a branch name with a slash in it is escaped in the ref, not truncated" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens?branch=feature%2Fx")) signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> List.filter (\u -> not (String.contains "ref=feature%2Fx" u))
                        |> Expect.equal []
            , test "forgets the branch you were on before" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens?branch=feature-x"))
                                (withComponent "Button" signedIn
                                    |> (\m -> { m | existingComponents = [ "Button" ], tokensFileExists = True })
                                )
                    in
                    ( model.components, model.existingComponents, model.tokensFileExists )
                        |> Expect.equal ( Nothing, [], False )
            , test "changing tabs on a branch refetches nothing" <|
                \_ ->
                    -- Every tab click runs through applyRoute, so without the
                    -- "is this actually a change?" guard in applyBranch each one
                    -- would forget the repository and refetch all six files.
                    -- That would present as the app being slow, not as a bug.
                    let
                        ( _, effect ) =
                            Update.update (UrlChanged (url "#/acme/design/components?branch=feature-x")) onBranch
                    in
                    ( Effect.requests effect |> List.length, Update.update (UrlChanged (url "#/acme/design/components?branch=feature-x")) onBranch |> Tuple.first |> .currentBranch )
                        |> Expect.equal ( 0, Just "feature-x" )
            , test "a URL with no branch means the default branch, and is read-only" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens")) onBranch
                    in
                    ( model.currentBranch, Guard.readOnly model )
                        |> Expect.equal ( Just "main", Just (Guard.DefaultBranch "main") )
            ]
        , describe "creating a branch takes your work with you"
            [ test "moves onto the new branch and says so in the URL" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update (GotCreateBranchResult (Ok featureBranch))
                                { signedIn | currentBranch = Just "main", newBranchName = "feature-x" }
                    in
                    ( model.currentBranch, Effect.toList effect )
                        |> Expect.equal
                            ( Just "feature-x", [ Effect.PushUrl "#/acme/design/tokens?branch=feature-x" ] )
            , test "and the navigation that follows refetches nothing, so edits in hand survive" <|
                \_ ->
                    -- The asymmetry with SwitchBranch is deliberate: the model
                    -- moves branch first, so applyBranch sees no change. Edits
                    -- made while browsing the default branch come along to the
                    -- branch just cut for them.
                    let
                        ( created, _ ) =
                            Update.update (GotCreateBranchResult (Ok featureBranch))
                                (withComponent "Button" { signedIn | currentBranch = Just "main" })

                        ( arrived, effect ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens?branch=feature-x")) created
                    in
                    ( Effect.requests effect |> List.length, Maybe.map (List.map .name) arrived.components )
                        |> Expect.equal ( 0, Just [ "Button" ] )
            ]
        , describe "reading the design system off the repository tree"
            [ test "fetches every file at the ref the tree was listed from" <|
                \_ ->
                    -- One recursive listing, not four per-directory ones. The
                    -- per-directory listings weren't recursive and had no
                    -- per_page, so GitLab's default of 20 silently capped each.
                    let
                        ( _, effect ) =
                            Update.update (GotTree "feature-x" 1 (Ok designSystemTree)) signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> Expect.equal
                            [ "https://gitlab.com/api/v4/projects/7/repository/files/themes%2FDark.json/raw?ref=feature-x"
                            , "https://gitlab.com/api/v4/projects/7/repository/files/components%2FButton.json/raw?ref=feature-x"
                            , "https://gitlab.com/api/v4/projects/7/repository/files/components%2FButton.contract.json/raw?ref=feature-x"
                            , "https://gitlab.com/api/v4/projects/7/repository/files/layouts%2FHome.json/raw?ref=feature-x"
                            ]
            , test "tells a contract apart from the component it belongs to" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (GotTree "main" 1 (Ok designSystemTree)) signedIn
                    in
                    ( model.existingComponents, model.existingContracts )
                        |> Expect.equal ( [ "Button" ], [ "Button" ] )
            , test "ignores files that aren't part of the design system" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (GotTree "main" 1 (Ok designSystemTree)) signedIn
                    in
                    ( model.existingThemes, model.existingScreens )
                        |> Expect.equal ( [ "Dark" ], [ "Home" ] )
            , test "a full page asks for the next one instead of reading a partial tree" <|
                \_ ->
                    -- A full page is the only evidence there might be another,
                    -- and reading the design system off half a listing would
                    -- present the missing half as deleted.
                    let
                        fullPage =
                            List.repeat GitLab.Files.treePageSize (blob "components/Button.json")

                        ( _, effect ) =
                            Update.update (GotTree "main" 1 (Ok fullPage)) signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> Expect.equal
                            [ "https://gitlab.com/api/v4/projects/7/repository/tree?recursive=true&ref=main&per_page=100&page=2" ]
            ]
        , describe "listings that used to stop at twenty"
            [ test "a full page of branches asks for the next one" <|
                \_ ->
                    -- listBranches sent no per_page at all, so GitLab's default
                    -- of 20 applied — and Guard.writability fails closed on a
                    -- branch missing from the list, so being on branch 21 made
                    -- the whole app read-only.
                    let
                        fullPage =
                            List.repeat GitLab.Branches.pageSize featureBranch

                        ( _, effect ) =
                            Update.update (GotBranches 1 (Ok fullPage)) signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> Expect.equal
                            [ "https://gitlab.com/api/v4/projects/7/repository/branches?per_page=100&page=2" ]
            , test "a short page of branches stops" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update (GotBranches 1 (Ok [ mainBranch ])) signedIn
                    in
                    ( Effect.requests effect |> List.length, Maybe.map List.length model.branches )
                        |> Expect.equal ( 0, Just 1 )
            , test "later pages append rather than replace" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (GotBranches 2 (Ok [ featureBranch ]))
                                { signedIn | branches = Just [ mainBranch ] }
                    in
                    Maybe.map (List.map .name) model.branches
                        |> Expect.equal (Just [ "main", "feature-x" ])
            ]
        , describe "opening a merge request"
            [ test "refuses on the default branch, with a remedy, and sends nothing" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update CreateMergeRequest
                                { signedIn | currentBranch = Just "main", mrTitle = "Title" }
                    in
                    ( Maybe.map Tuple.first model.commitStatus, Effect.requests effect |> List.length )
                        |> Expect.equal ( Just Failed, 0 )
            , test "refuses an untitled merge request differently, and sends nothing" <|
                \_ ->
                    -- Two refusals with different remedies: being on the default
                    -- branch takes three steps to fix. Collapsing them into one
                    -- message would lose that.
                    let
                        ( onDefault, _ ) =
                            Update.update CreateMergeRequest
                                { signedIn | currentBranch = Just "main", mrTitle = "Title" }

                        ( untitled, effect ) =
                            Update.update CreateMergeRequest
                                { signedIn | currentBranch = Just "feature-x", mrTitle = "  " }
                    in
                    ( Maybe.map Tuple.second untitled.commitStatus /= Maybe.map Tuple.second onDefault.commitStatus
                    , Maybe.map Tuple.first untitled.commitStatus
                    , Effect.requests effect |> List.length
                    )
                        |> Expect.equal ( True, Just Failed, 0 )
            , test "opens from the current branch onto the default one" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update CreateMergeRequest
                                { signedIn | currentBranch = Just "feature-x", mrTitle = "Nicer buttons" }
                    in
                    Effect.requests effect
                        |> List.head
                        |> Maybe.andThen (.body >> GitLab.Request.bodyValue)
                        |> Maybe.map
                            (Decode.decodeValue
                                (Decode.map2 Tuple.pair
                                    (Decode.field "source_branch" Decode.string)
                                    (Decode.field "target_branch" Decode.string)
                                )
                            )
                        |> Expect.equal (Just (Ok ( "feature-x", "main" )))
            ]
        , describe "the export pipeline"
            [ test "creates a file the repository does not have yet" <|
                \_ ->
                    exporting { targets = [ "css" ], tree = [] }
                        |> commitField (Decode.at [ "actions", "0", "action" ] Decode.string)
                        |> Expect.equal (Ok "create")
            , test "updates one it does" <|
                \_ ->
                    -- The branch builds every action as "update" and rewrites it
                    -- in a second pass. The create case depends entirely on that
                    -- pass surviving future edits.
                    exporting { targets = [ "css" ], tree = [ "exports/variables.css" ] }
                        |> commitField (Decode.at [ "actions", "0", "action" ] Decode.string)
                        |> Expect.equal (Ok "update")
            , test "writes one file per selected target and no more" <|
                \_ ->
                    exporting { targets = [ "css" ], tree = [] }
                        |> commitField (Decode.field "actions" (Decode.list (Decode.field "file_path" Decode.string)))
                        |> Expect.equal (Ok [ "exports/variables.css" ])
            ]
        , describe "deleting"
            [ test "deleting a component also deletes its contract if it exists" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update (DeleteComponent "Button")
                                { onBranch
                                    | existingComponents = [ "Button" ]
                                    , components = Just [ { name = "Button", description = Nothing, variants = [], slots = [], states = [], layout = Nothing } ]
                                    , existingContracts = [ "Button" ]
                                    , contracts = Just [ { component = "Button", rules = [] } ]
                                }
                    in
                    commitField (Decode.field "actions" (Decode.list (Decode.field "file_path" Decode.string))) effect
                        |> Expect.equal (Ok [ "components/Button.json", "components/Button.contract.json" ])
            ]
        , describe "navigation"
            [ test "an external link loads, rather than being pushed into the fragment router" <|
                \_ ->
                    -- This is the OAuth sign-in path. Pushing it would put a
                    -- gitlab.com URL into our own history and never leave.
                    Update.update (LinkClicked (Browser.External "https://gitlab.com/oauth/authorize")) signedIn
                        |> Tuple.second
                        |> Effect.toList
                        |> Expect.equal [ Effect.LoadUrl "https://gitlab.com/oauth/authorize" ]
            ]
        , describe "the startup screen gets out of the way"
            [ test "the project list arriving is the end of loading" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (GotProjects (Ok []))
                                { signedOutWithToken | startupStatus = Types.Booting }
                    in
                    model.startupStatus |> Expect.equal Types.Ready
            , test "failing to fetch the project list still ends loading" <|
                \_ ->
                    -- Otherwise the throbber spins forever over an error the
                    -- user cannot see.
                    let
                        ( model, _ ) =
                            Update.update (GotProjects (Err (Http.BadStatus 500)))
                                { signedOutWithToken | startupStatus = Types.Booting }
                    in
                    model.startupStatus |> Expect.equal Types.Ready
            , test "a deep link keeps loading until the repository itself arrives" <|
                \_ ->
                    -- The list is not what a deep link is waiting for. Going
                    -- Ready here would flash the repository picker and then
                    -- replace it with the editor.
                    let
                        ( model, _ ) =
                            Update.update (GotProjects (Ok []))
                                { signedOutWithToken
                                    | url = url "#/acme/design/tokens"
                                    , selectedProject = Nothing
                                    , startupStatus = Types.Booting
                                }
                    in
                    model.startupStatus |> Expect.equal Types.Booting
            , test "and stops once that repository has arrived" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (GotProjects (Ok []))
                                { signedIn
                                    | url = url "#/acme/design/tokens"
                                    , startupStatus = Types.Booting
                                }
                    in
                    model.startupStatus |> Expect.equal Types.Ready
            , test "and going home does not put it back, so the landing page is not a throbber" <|
                \_ ->
                    -- Home clears the project state, and "clear" used to include
                    -- startupStatus. Nothing was in flight to end the loading it
                    -- restarted, so #/ showed the boot throbber forever.
                    let
                        ( model, _ ) =
                            Update.update (UrlChanged (url "#/")) { signedIn | startupStatus = Types.Ready }
                    in
                    model.startupStatus |> Expect.equal Types.Ready
            , test "an expired token ends loading rather than spinning forever" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (GotProfile (Err (Http.BadStatus 401)))
                                { signedOutWithToken | startupStatus = Types.Booting }
                    in
                    ( model.startupStatus, model.token )
                        |> Expect.equal ( Types.Ready, Nothing )
            , test "a failed project fetch ends loading and says why" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (GotProject (Err (Http.BadStatus 404)))
                                { signedOutWithToken | startupStatus = Types.Booting }
                    in
                    ( model.startupStatus, model.error )
                        |> Expect.equal
                            ( Types.Ready
                            , Just "No repository at that address, or you don't have access to it."
                            )
            ]
        , describe "refusals do not reach the network"
            [ test "creating a token with a blank name says so and sends nothing" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update CreateToken
                                { onBranch | tokens = Just [], newTokenPath = "  " }
                    in
                    ( Maybe.map Tuple.first model.commitStatus
                    , Effect.requests effect |> List.length
                    )
                        |> Expect.equal ( Just Failed, 0 )
            , test "creating a token before they have loaded says so rather than refusing" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update CreateToken
                                { onBranch | tokens = Nothing, newTokenPath = "color.brand.500" }
                    in
                    model.commitStatus
                        |> Expect.equal (Just ( Working, "Tokens are still loading" ))
            , test "an empty export selection refuses rather than committing nothing" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update RunExportPipeline { onBranch | exportTargets = [] }
                    in
                    ( Maybe.map Tuple.first model.commitStatus
                    , Effect.requests effect |> List.length
                    )
                        |> Expect.equal ( Just Failed, 0 )
            ]
        , describe "the default branch is read-only"
            [ test "every write refuses on the default branch and sends nothing" <|
                \_ ->
                    -- The test this whole change exists for. Nine buttons across
                    -- four tabs used to commit straight to main; four of them go
                    -- through schema validation first and five do not, so a guard
                    -- placed at either end alone would have missed the other.
                    writeMessages
                        |> List.map (refuseOn { signedIn | currentBranch = Just "main" })
                        |> Expect.equal (List.repeat (List.length writeMessages) ( Just Failed, 0 ))
            , test "and on a protected branch that is not the default one" <|
                \_ ->
                    writeMessages
                        |> List.map (refuseOn { onBranch | currentBranch = Just "release/1.0" })
                        |> Expect.equal (List.repeat (List.length writeMessages) ( Just Failed, 0 ))
            , test "and while the branch list has not loaded, because nothing is known to be safe" <|
                \_ ->
                    writeMessages
                        |> List.map (refuseOn { onBranch | branches = Nothing })
                        |> Expect.equal (List.repeat (List.length writeMessages) ( Just Failed, 0 ))
            , test "local edits are refused too, leaving the model untouched" <|
                \_ ->
                    -- Not just "no request went out": the point of full read-only
                    -- is that nothing accumulates in memory either, so the branch
                    -- you eventually create starts from what the repository says.
                    let
                        readOnlyModel =
                            { signedIn
                                | currentBranch = Just "main"
                                , tokens = Just []
                                , newTokenPath = "color.brand.500"
                                , newTokenValue = "#fff"
                                , newThemeName = "Dark"
                                , newComponentName = "Button"
                                , newScreenName = "Home"
                            }

                        after m =
                            { tokens = m.tokens, themes = m.themes, components = m.components, screens = m.screens }
                    in
                    [ CreateToken, CreateTheme, CreateComponent, CreateScreen, AddContractRule ]
                        |> List.map (\msg -> Update.update msg readOnlyModel |> Tuple.first |> after)
                        |> Expect.equal (List.repeat 5 (after readOnlyModel))
            , test "the escape hatch still works from inside the read-only state" <|
                \_ ->
                    -- If creating a branch were ever classified as a mutation,
                    -- the only way off the default branch would be a reload.
                    let
                        ( _, effect ) =
                            Update.update CreateBranch
                                { signedIn | currentBranch = Just "main", newBranchName = "feature/new-colors" }
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> Expect.equal
                            [ "https://gitlab.com/api/v4/projects/7/repository/branches?branch=feature%2Fnew-colors&ref=main" ]
            , test "so does switching branch, and reading is never blocked" <|
                \_ ->
                    [ SwitchBranch "feature-x", UpdateNewBranchName "x", UpdateMRTitle "x" ]
                        |> List.map
                            (\msg ->
                                Update.update msg { signedIn | currentBranch = Just "main" }
                                    |> Tuple.first
                                    |> .commitStatus
                                    |> Maybe.map Tuple.first
                            )
                        |> List.filter (\level -> level == Just Failed)
                        |> Expect.equal []
            ]
        , describe "saves say which version they are based on"
            [ test "an update carries the last_commit_id the file was read at" <|
                \_ ->
                    -- Without this GitLab takes the write unconditionally, so
                    -- two tabs, two people, or one edit made in GitLab's own UI
                    -- after the app loaded all silently clobber each other.
                    onBranch
                        |> withComponent "Button"
                        |> (\m -> { m | existingComponents = [ "Button" ] })
                        |> readAt "components/Button.json" "deadbeef"
                        |> save
                        |> commitField (Decode.at [ "actions", "0", "last_commit_id" ] Decode.string)
                        |> Expect.equal (Ok "deadbeef")
            , test "a create carries none, because there is no version to be based on" <|
                \_ ->
                    -- GitLab rejects last_commit_id on a create, so a stale
                    -- entry left in the model must not leak into one.
                    onBranch
                        |> withComponent "Button"
                        |> (\m -> { m | existingComponents = [] })
                        |> readAt "components/Button.json" "deadbeef"
                        |> save
                        |> commitField (Decode.at [ "actions", "0" ] (Decode.maybe (Decode.field "last_commit_id" Decode.string)))
                        |> Expect.equal (Ok Nothing)
            , test "a file never read sends no version rather than a wrong one" <|
                \_ ->
                    onBranch
                        |> withComponent "Button"
                        |> (\m -> { m | existingComponents = [ "Button" ] })
                        |> save
                        |> commitField (Decode.at [ "actions", "0" ] (Decode.maybe (Decode.field "last_commit_id" Decode.string)))
                        |> Expect.equal (Ok Nothing)
            , test "reading a component records the version it came at" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update
                                (GotComponentFile "components/Button.json"
                                    (Ok { content = componentJson, lastCommitId = Just "c0ffee" })
                                )
                                onBranch
                    in
                    Dict.get "components/Button.json" model.fileVersions
                        |> Expect.equal (Just "c0ffee")
            ]
        , describe "files that can't be read are reported rather than dropped"
            [ test "a component that doesn't decode becomes a visible error" <|
                \_ ->
                    -- It used to be swallowed, which made a malformed component
                    -- indistinguishable from one that isn't there — and left
                    -- the app willing to `create` over it.
                    let
                        ( model, _ ) =
                            Update.update
                                (GotComponentFile "components/Broken.json"
                                    (Ok { content = "{ not json", lastCommitId = Nothing })
                                )
                                onBranch
                    in
                    List.map .path model.loadErrors
                        |> Expect.equal [ "components/Broken.json" ]
            , test "a component GitLab won't serve is reported too" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update
                                (GotComponentFile "components/Gone.json" (Err (Http.BadStatus 404)))
                                onBranch
                    in
                    List.map .path model.loadErrors
                        |> Expect.equal [ "components/Gone.json" ]
            , test "a component that loads cleanly reports nothing" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update
                                (GotComponentFile "components/Button.json"
                                    (Ok { content = componentJson, lastCommitId = Nothing })
                                )
                                onBranch
                    in
                    model.loadErrors |> Expect.equal []
            , test "switching branch forgets both the errors and the versions" <|
                \_ ->
                    -- Carrying either across would send one branch's
                    -- last_commit_id with the other branch's save.
                    let
                        loaded =
                            onBranch
                                |> readAt "components/Button.json" "deadbeef"
                                |> (\m -> { m | loadErrors = [ { path = "components/Broken.json", reason = "bad" } ] })

                        -- SwitchBranch only navigates; the branch state is
                        -- forgotten when the URL change lands.
                        ( model, _ ) =
                            Update.update (UrlChanged (url "#/acme/design/tokens?branch=release%2F1.0")) loaded
                    in
                    ( Dict.isEmpty model.fileVersions, model.loadErrors )
                        |> Expect.equal ( True, [] )
            ]
        , describe "a commit GitLab refuses says why"
            [ test "a stale write is reported as a conflict, not as a generic failure" <|
                \_ ->
                    -- The response body used to be discarded by
                    -- Http.expectWhatever, so a protected branch, an expired
                    -- token and a file that moved all came out identically.
                    let
                        ( model, _ ) =
                            Update.update
                                (GotCommitResult Types.CommitOther
                                    (Err (Http.BadBody """{"message":"You are attempting to update a file that has changed since you started editing it."}"""))
                                )
                                onBranch
                    in
                    model.commitStatus
                        |> Maybe.map (Tuple.second >> String.contains "changed in GitLab")
                        |> Expect.equal (Just True)
            , test "a protected branch is named as one" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update
                                (GotCommitResult Types.CommitOther (Err (Http.BadStatus 403)))
                                onBranch
                    in
                    model.commitStatus
                        |> Maybe.map (Tuple.second >> String.contains "protected")
                        |> Expect.equal (Just True)
            , test "a 401 with no refresh token signs the user out instead of blaming the save" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update
                                (GotCommitResult Types.CommitOther (Err (Http.BadStatus 401)))
                                { onBranch | refreshToken = Nothing }
                    in
                    ( model.token, Effect.toList effect )
                        |> Expect.equal ( Nothing, [ Effect.ClearToken ] )
            , test "a 401 with a refresh token renews it rather than signing out" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update
                                (GotCommitResult Types.CommitOther (Err (Http.BadStatus 401)))
                                { onBranch | refreshToken = Just "refresh-me" }
                    in
                    ( model.token /= Nothing
                    , Effect.requests effect |> List.map .url
                    )
                        |> Expect.equal ( True, [ "https://gitlab.com/oauth/token" ] )
            ]
        ]


{-| The smallest component file that decodes.
-}
componentJson : String
componentJson =
    """{"name":"Button","variants":[],"slots":[],"states":[]}"""


{-| A model that has read `path` at commit `commitId`, as loading the branch
would have left it.
-}
readAt : String -> String -> Types.Model -> Types.Model
readAt path commitId model =
    { model | fileVersions = Dict.insert path commitId model.fileVersions }


{-| The nine buttons in the app that write to the repository. Kept in one place
so the read-only tests cannot drift out of sync with each other.
-}
writeMessages : List Msg
writeMessages =
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



-- FIXTURES


{-| A model as it is once a repository is open: token, user, project, and the
tree listing that the create-vs-update decision reads.
-}
signedIn : Types.Model
signedIn =
    { signedOutWithToken
        | selectedProject =
            Just
                { id = 7
                , name = "design"
                , pathWithNamespace = "acme/design"
                , defaultBranch = "main"
                }
        , repositoryTree = Just []
    }


{-| A repository open and a branch of your own checked out, with the branch list
loaded — the state in which the app will actually write anything.

`signedIn` deliberately stops short of this. It has no branch and no branch
list, which `Guard` reads as read-only, so it is the fixture the refusal tests
want and every write test starts from `onBranch` instead.

-}
onBranch : Types.Model
onBranch =
    { signedIn
        | currentBranch = Just "feature-x"
        , branches = Just [ mainBranch, protectedBranch, featureBranch ]
    }


mainBranch : GitLab.Branches.Branch
mainBranch =
    { name = "main", commitId = "aaa", default = True, protected = True }


protectedBranch : GitLab.Branches.Branch
protectedBranch =
    { name = "release/1.0", commitId = "bbb", default = False, protected = True }


featureBranch : GitLab.Branches.Branch
featureBranch =
    { name = "feature-x", commitId = "ccc", default = False, protected = False }


signedOutWithToken : Types.Model
signedOutWithToken =
    Types.initial (url "#/")
        { token = Just "secret"
        , refreshToken = Nothing
        , pkceChallenge = "challenge"
        , pkceVerifier = "verifier"
        , authConfig =
            { clientId = "test-client"
            , redirectUri = "https://example.test/app"
            , scope = "read_api write_repository"
            , state = "test-state"
            }
        }


withComponent : String -> Types.Model -> Types.Model
withComponent name model =
    { model
        | components =
            Just
                [ { name = name
                  , description = Nothing
                  , variants = []
                  , slots = []
                  , states = []
                  , layout = Nothing
                  }
                ]
        , selectedComponentName = Just name
    }


{-| A tree entry as GitLab lists it, given its full repository path. `type_`
matters as much as the path: a recursive listing includes the directories
themselves, and treating one as a file asks GitLab for the contents of
`components`.
-}
blob : String -> GitLab.Files.TreeItem
blob path =
    { id = "abc123"
    , name = path |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault path
    , type_ = "blob"
    , path = path
    , mode = "100644"
    }


treeDir : String -> GitLab.Files.TreeItem
treeDir path =
    let
        item =
            blob path
    in
    { item | type_ = "tree" }


{-| One of each kind of file, plus the directories a recursive listing includes
and two files that are not part of the design system at all.
-}
designSystemTree : List GitLab.Files.TreeItem
designSystemTree =
    [ treeDir "themes"
    , treeDir "components"
    , treeDir "layouts"
    , blob "themes/Dark.json"
    , blob "components/Button.json"
    , blob "components/Button.contract.json"
    , blob "components/README.md"
    , blob "layouts/Home.json"
    , blob "README.md"
    ]


url : String -> Url.Url
url fragment =
    { protocol = Url.Https
    , host = "datakurre.github.io"
    , port_ = Nothing
    , path = "/design-playground"
    , query = Nothing
    , fragment = String.split "#" fragment |> List.drop 1 |> List.head
    }



-- HELPERS


{-| Runs a save the whole way: `SaveComponent` records what it intends and asks
for validation, and the commit is only built once the result comes back. Both
halves have to line up, so both run here.
-}
save : Types.Model -> Effect Msg
save model =
    let
        ( pending, _ ) =
            Update.update SaveComponent model

        ( _, effect ) =
            Update.update
                (GotSchemaValidationResult { valid = True, errors = [], context = Encode.null })
                pending
    in
    effect


{-| Runs the export pipeline with a given selection, against a repository whose
tree already contains `tree`.
-}
exporting : { targets : List String, tree : List String } -> Effect Msg
exporting { targets, tree } =
    Update.update RunExportPipeline
        { onBranch
            | exportTargets = targets
            , tokens = Just []
            , repositoryTree =
                Just
                    (List.map
                        (\path ->
                            { id = "abc123", name = path, type_ = "blob", path = path, mode = "100644" }
                        )
                        tree
                    )
        }
        |> Tuple.second


{-| How a refusal looks from outside: a `Failed` status, and nothing on the
wire.
-}
refuseOn : Types.Model -> Msg -> ( Maybe StatusLevel, Int )
refuseOn model msg =
    let
        ( after, effect ) =
            Update.update msg model
    in
    ( Maybe.map Tuple.first after.commitStatus, Effect.requests effect |> List.length )


commitField : Decode.Decoder a -> Effect Msg -> Result Decode.Error a
commitField decoder effect =
    Effect.requests effect
        |> List.head
        |> Maybe.andThen (.body >> GitLab.Request.bodyValue)
        |> Maybe.map (Decode.decodeValue decoder)
        |> Maybe.withDefault (Err (Decode.Failure "no commit was issued" Encode.null))


isValidateSchema : Effect Msg -> Bool
isValidateSchema effect =
    case effect of
        Effect.ValidateSchema _ ->
            True

        _ ->
            False
