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
import Effect exposing (Effect)
import Expect
import GitLab.Files
import GitLab.Request
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
                    signedIn
                        |> withComponent "Button"
                        |> (\m -> { m | existingComponents = [] })
                        |> save
                        |> commitField (Decode.at [ "actions", "0", "action" ] Decode.string)
                        |> Expect.equal (Ok "create")
            , test "a component the repository already has is updated" <|
                \_ ->
                    signedIn
                        |> withComponent "Button"
                        |> (\m -> { m | existingComponents = [ "Button" ] })
                        |> save
                        |> commitField (Decode.at [ "actions", "0", "action" ] Decode.string)
                        |> Expect.equal (Ok "update")
            , test "it writes the component's own file path" <|
                \_ ->
                    signedIn
                        |> withComponent "Button"
                        |> save
                        |> commitField (Decode.at [ "actions", "0", "file_path" ] Decode.string)
                        |> Expect.equal (Ok "components/Button.json")
            ]
        , describe "commits target the branch you are on"
            [ test "the current branch, not the project's default" <|
                \_ ->
                    -- Five separate `Maybe.withDefault project.defaultBranch
                    -- model.currentBranch` expressions decide this. One going
                    -- stale would be invisible.
                    signedIn
                        |> withComponent "Button"
                        |> (\m -> { m | currentBranch = Just "feature-x" })
                        |> save
                        |> commitField (Decode.field "branch" Decode.string)
                        |> Expect.equal (Ok "feature-x")
            , test "falls back to the default branch when none is chosen" <|
                \_ ->
                    signedIn
                        |> withComponent "Button"
                        |> (\m -> { m | currentBranch = Nothing })
                        |> save
                        |> commitField (Decode.field "branch" Decode.string)
                        |> Expect.equal (Ok "main")
            ]
        , describe "saving validates before it commits"
            [ test "SaveComponent asks for validation and issues no request yet" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update SaveComponent (withComponent "Button" signedIn)
                    in
                    ( Effect.requests effect |> List.length
                    , Effect.toList effect |> List.map isValidateSchema
                    )
                        |> Expect.equal ( 0, [ True ] )
            , test "a failed validation reports it and commits nothing" <|
                \_ ->
                    let
                        ( pending, _ ) =
                            Update.update SaveComponent (withComponent "Button" signedIn)

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
                            Update.update SaveComponent (withComponent "Button" signedIn)

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
            [ test "refetches everything at the new ref" <|
                \_ ->
                    -- Not project.defaultBranch. The Msg comment in Types
                    -- records that this exact bug already happened once:
                    -- switching branches showed the default branch's contents
                    -- under the new branch's name.
                    let
                        ( _, effect ) =
                            Update.update (SwitchBranch "feature-x") signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> List.filter (\u -> not (String.contains "feature-x" u))
                        |> Expect.equal []
            , test "forgets the branch you were on before" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update (SwitchBranch "feature-x")
                                (withComponent "Button" signedIn
                                    |> (\m -> { m | existingComponents = [ "Button" ], tokensFileExists = True })
                                )
                    in
                    ( model.components, model.existingComponents, model.tokensFileExists )
                        |> Expect.equal ( Nothing, [], False )
            ]
        , describe "listing the components directory"
            [ test "fetches every component and contract at the ref it was listed from" <|
                \_ ->
                    let
                        ( _, effect ) =
                            Update.update
                                (GotComponentsTree "feature-x"
                                    (Ok
                                        [ treeItem "Button.json"
                                        , treeItem "Button.contract.json"
                                        , treeItem "README.md"
                                        ]
                                    )
                                )
                                signedIn
                    in
                    Effect.requests effect
                        |> List.map .url
                        |> Expect.equal
                            [ "https://gitlab.com/api/v4/projects/7/repository/files/components%2FButton.json/raw?ref=feature-x"
                            , "https://gitlab.com/api/v4/projects/7/repository/files/components%2FButton.contract.json/raw?ref=feature-x"
                            ]
            , test "tells a contract apart from the component it belongs to" <|
                \_ ->
                    let
                        ( model, _ ) =
                            Update.update
                                (GotComponentsTree "main"
                                    (Ok
                                        [ treeItem "Button.json"
                                        , treeItem "Button.contract.json"
                                        , treeItem "README.md"
                                        ]
                                    )
                                )
                                signedIn
                    in
                    ( model.existingComponents, model.existingContracts )
                        |> Expect.equal ( [ "Button" ], [ "Button" ] )
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
                        ( onBranch, _ ) =
                            Update.update CreateMergeRequest
                                { signedIn | currentBranch = Just "main", mrTitle = "Title" }

                        ( untitled, effect ) =
                            Update.update CreateMergeRequest
                                { signedIn | currentBranch = Just "feature-x", mrTitle = "  " }
                    in
                    ( Maybe.map Tuple.second untitled.commitStatus /= Maybe.map Tuple.second onBranch.commitStatus
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
                                { signedIn
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
                                { signedIn | tokens = Just [], newTokenPath = "  " }
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
                                { signedIn | tokens = Nothing, newTokenPath = "color.brand.500" }
                    in
                    model.commitStatus
                        |> Expect.equal (Just ( Working, "Tokens are still loading" ))
            , test "an empty export selection refuses rather than committing nothing" <|
                \_ ->
                    let
                        ( model, effect ) =
                            Update.update RunExportPipeline { signedIn | exportTargets = [] }
                    in
                    ( Maybe.map Tuple.first model.commitStatus
                    , Effect.requests effect |> List.length
                    )
                        |> Expect.equal ( Just Failed, 0 )
            ]
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


signedOutWithToken : Types.Model
signedOutWithToken =
    Types.initial (url "#/")
        { token = Just "secret", pkceChallenge = "challenge", pkceVerifier = "verifier" }


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


{-| A tree entry as GitLab lists it. Only `name` and `path` matter here.
-}
treeItem : String -> GitLab.Files.TreeItem
treeItem name =
    { id = "abc123"
    , name = name
    , type_ = "blob"
    , path = "components/" ++ name
    , mode = "100644"
    }


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
        { signedIn
            | exportTargets = targets
            , tokens = Just []
            , currentBranch = Just "main"
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
