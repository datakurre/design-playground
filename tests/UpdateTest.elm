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

import Effect exposing (Effect)
import Expect
import GitLab.Request
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
