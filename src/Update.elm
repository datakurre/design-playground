module Update exposing (applyRoute, update)

import Auth
import Browser
import Components
import Contracts
import Dict
import Effect exposing (Effect)
import Export
import GitLab.Branches
import GitLab.Commits
import GitLab.Files
import GitLab.MergeRequests
import GitLab.Projects
import Guard
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Naming
import RepoPaths
import Route
import Screens exposing (ScreenNode(..))
import Templates
import Themes
import TokenScale
import Tokens
import Types exposing (..)
import Url


{-| The "add a variant / slot / state" forms are the same form three times
over: check the typed name against what the component already has, append it,
clear the field.

They used to clear the field unconditionally while a `not (List.member ...)`
guard inside the mapper quietly dropped duplicates — so adding "primary" twice
looked like it worked and didn't. Routing all three through `Naming` means a
duplicate says so and the field keeps what you typed.

-}
addNameToComponent :
    { noun : String
    , hint : String
    , typed : String
    , get : Components.Component -> List String
    , set : List String -> Components.Component -> Components.Component
    , clear : Model -> Model
    }
    -> Model
    -> ( Model, Effect Msg )
addNameToComponent config model =
    case model.selectedComponentName of
        Nothing ->
            ( { model | commitStatus = Just ( Failed, "Pick a component first" ) }, Effect.none )

        Just selected ->
            let
                currentComponents =
                    model.components |> Maybe.withDefault []

                existing =
                    currentComponents
                        |> List.filter (\c -> c.name == selected)
                        |> List.head
                        |> Maybe.map config.get
                        |> Maybe.withDefault []
            in
            case Naming.check config.typed existing of
                Err problem ->
                    ( { model | commitStatus = Just ( Failed, Naming.describe config.noun config.hint problem ) }, Effect.none )

                Ok name ->
                    let
                        appendTo c =
                            if c.name == selected then
                                config.set (config.get c ++ [ name ]) c

                            else
                                c
                    in
                    ( config.clear { model | components = Just (List.map appendTo currentComponents), commitStatus = Nothing }
                    , Effect.none
                    )


{-| The mirror of `addNameToComponent`, with one job more: the layout can point
at a variant, state or slot _by name_, so dropping the name has to drop what
points at it. Left behind, a `When` on a deleted variant is a condition that can
never match again and a placeholder for a deleted slot renders as nothing —
neither of which the editor gives you any way to see, let alone fix.
-}
removeNameFromComponent :
    { get : Components.Component -> List String
    , set : List String -> Components.Component -> Components.Component
    , forget : String -> Components.Layout -> Components.Layout
    }
    -> String
    -> Model
    -> ( Model, Effect Msg )
removeNameFromComponent config name model =
    updateSelectedComponent
        (\c ->
            let
                stripped =
                    config.set (List.filter (\n -> n /= name) (config.get c)) c
            in
            { stripped | layout = Maybe.map (Components.mapLayout (config.forget name)) stripped.layout }
        )
        model


{-| The component being edited, changed. Twelve messages used to open with the
same four lines — unwrap `selectedComponentName`, default `components` to `[]`,
map over it, compare names — and the interesting part of each was one expression
buried inside that.
-}
updateSelectedComponent : (Components.Component -> Components.Component) -> Model -> ( Model, Effect Msg )
updateSelectedComponent f model =
    case model.selectedComponentName of
        Nothing ->
            ( model, Effect.none )

        Just selected ->
            let
                apply c =
                    if c.name == selected then
                        f c

                    else
                        c
            in
            ( { model | components = Just (List.map apply (Maybe.withDefault [] model.components)) }
            , Effect.none
            )


{-| One node of the selected component's layout, addressed by path. A component
with no layout yet has nothing to address, and is left alone.
-}
updateLayoutAt : List Int -> (Components.Layout -> Components.Layout) -> Model -> ( Model, Effect Msg )
updateLayoutAt path f model =
    updateSelectedComponent (\c -> { c | layout = Maybe.map (Components.updateLayoutNode path f) c.layout }) model


{-| Deleting the variant you were editing drops you back to the base, rather
than leaving the editor pointed at a context the component no longer has.
-}
forgetEditingVariant : String -> Model -> Model
forgetEditingVariant name model =
    if model.editingVariant == Just name then
        { model | editingVariant = Nothing }

    else
        model


{-| As `forgetEditingVariant`, for states.
-}
forgetEditingState : String -> Model -> Model
forgetEditingState name model =
    if model.editingState == Just name then
        { model | editingState = Nothing }

    else
        model


{-| Adding a child is the same job whatever kind of node it goes into, which is
why five messages spelled out the same `Stack`/`Grid`/`When` triple. An
`Element` renders text or a slot and holds no children, so it takes none.
-}
appendChild : Components.Layout -> Components.Layout -> Components.Layout
appendChild child node =
    case node of
        Components.Stack props children ->
            Components.Stack props (children ++ [ child ])

        Components.Grid props children ->
            Components.Grid props (children ++ [ child ])

        Components.When props children ->
            Components.When props (children ++ [ child ])

        Components.Element _ _ ->
            node


{-| The other half of `appendChild`. This used to leave `When` out, so the
delete button on anything inside a conditional did nothing at all.
-}
removeChildAt : Int -> Components.Layout -> Components.Layout
removeChildAt index node =
    let
        without children =
            List.indexedMap Tuple.pair children
                |> List.filter (\( i, _ ) -> i /= index)
                |> List.map Tuple.second
    in
    case node of
        Components.Stack props children ->
            Components.Stack props (without children)

        Components.Grid props children ->
            Components.Grid props (without children)

        Components.When props children ->
            Components.When props (without children)

        Components.Element _ _ ->
            node


{-| Forgets the repository. Opening a project, closing one and logging out all
have to forget the same set, and listing what to _forget_ never worked: each
call site used to spell it out inline and each was missing something different,
then the shared helper inherited the same problem — a merge request from the
last repository would still be sitting in the panel under the next one.

So it runs the other way round. Rebuild from `Types.initial` and name only what
survives leaving a repository, which is the session (who you are, which projects
you can see) and where you are looking. Anything added to the model from now on
is forgotten by default, which is the safe direction to be wrong in.

-}
clearProjectState : Model -> Model
clearProjectState model =
    let
        fresh =
            Types.initial model.url
                { token = model.token
                , refreshToken = model.refreshToken
                , pkceChallenge = model.pkceChallenge
                , pkceVerifier = model.pkceVerifier
                , authConfig = model.authConfig
                }
    in
    { fresh
        | user = model.user
        , projects = model.projects
        , projectsPage = model.projectsPage
        , projectSearch = model.projectSearch
        , activeTab = model.activeTab

        -- Whether the app has finished booting is a fact about the session,
        -- not about the repository. Dropping it here sent `#/` back to
        -- `Booting`, and since nothing else was in flight to end it, the home
        -- route showed the loading throbber forever.
        , startupStatus = model.startupStatus
    }


{-| Opening a repository, on the branch the URL asked for. `Nothing` means the
project's default branch — which is read-only, and is the right place to land:
browsing is what you do before you decide to change anything.
-}
resetForProject : GitLab.Projects.Project -> Maybe String -> Model -> Model
resetForProject project branch model =
    let
        cleared =
            clearProjectState model
    in
    { cleared
        | selectedProject = Just project
        , currentBranch = Just (Maybe.withDefault project.defaultBranch branch)
    }


{-| The state a branch change leaves behind: everything read from the old branch
forgotten, so nothing from it can be saved onto the new one.

`pendingCommit` is in here for a reason of its own. A save in flight belongs to
the branch it was clicked on, and letting one survive a switch meant its
validation result arriving later and committing against a model that had moved.
It carries its own branch now, but dropping it is still the honest thing to do:
the user navigated away from that save.

-}
forgetBranchState : String -> Model -> Model
forgetBranchState branchName model =
    { model
        | currentBranch = Just branchName
        , repositoryTree = Nothing
        , originalComponents = Nothing
        , components = Nothing
        , originalTokens = Nothing
        , tokens = Nothing
        , themes = []
        , screens = Nothing
        , existingComponents = []
        , existingThemes = []
        , existingScreens = []
        , tokensFileExists = False

        -- Versions and read errors both belong to the ref they were collected
        -- at. Carrying either across a branch change would send one branch's
        -- `last_commit_id` with the other branch's save.
        , fileVersions = Dict.empty
        , loadErrors = []
        , contracts = Nothing
        , existingContracts = []
        , newContractRuleType = "allowedTokenGroups"
        , newContractRuleFields = Dict.empty
        , pendingCommit = Nothing
    }


{-| Everything a route needs from the model: the right project loaded, the right
tab open, the right thing selected. `UrlChanged` runs it on every navigation and
`Main.init` runs it once at boot, which is what makes a deep link or a refresh
land where the URL says rather than on an empty Tokens tab.
-}
applyRoute : Route.Route -> Model -> ( Model, Effect Msg )
applyRoute route model =
    case route of
        Route.Home ->
            ( { model | activeTab = TokenStudio } |> clearProjectState, Effect.none )

        Route.Repo repo ->
            let
                ( opened, openEffect ) =
                    openProject repo.path repo.branch model

                ( branched, branchEffect ) =
                    applyBranch repo.branch opened
            in
            ( selectFromRoute repo.tab branched, Effect.batch [ openEffect, branchEffect ] )


{-| Moves to the branch the URL names, if that is a move at all.

The "if that is a move at all" is load-bearing. Every tab click is a navigation
and so runs through here, and without the check each one would forget the
repository and refetch all six files. That would present as the app being slow,
not as a routing bug, which is why `UpdateTest` asserts that switching tabs
issues no requests.

`openProject` has already put a freshly opened repository on the right branch,
so this sees no change there either.

-}
applyBranch : Maybe String -> Model -> ( Model, Effect Msg )
applyBranch requested model =
    case ( model.token, model.selectedProject ) of
        ( Just token, Just project ) ->
            let
                wanted =
                    Maybe.withDefault project.defaultBranch requested
            in
            if model.currentBranch == Just wanted then
                ( model, Effect.none )

            else
                ( forgetBranchState wanted model
                    |> (\m -> { m | commitStatus = Just ( Done, "On branch " ++ wanted ) })
                , fetchAtRef token project wanted
                )

        _ ->
            -- No repository yet: `GotProject` will land on the right branch
            -- once it arrives.
            ( model, Effect.none )


{-| A route only speaks for its own tab. Leaving the other tab's selection alone
is what lets you look at Screens and come back to the component you had open.

Moving to a different component does drop the editing context, though: variants
and states are named per component, so `primary` carried over from the last one
would mean editing a layer this one never declared.

-}
selectFromRoute : Route.TabRoute -> Model -> Model
selectFromRoute tabRoute model =
    let
        movedToAnotherComponent =
            case tabRoute of
                Route.ComponentsTab name ->
                    name /= model.selectedComponentName

                _ ->
                    False
    in
    { model
        | activeTab = Route.toTab tabRoute
        , editingVariant =
            if movedToAnotherComponent then
                Nothing

            else
                model.editingVariant
        , editingState =
            if movedToAnotherComponent then
                Nothing

            else
                model.editingState
        , selectedComponentName =
            case tabRoute of
                Route.ComponentsTab name ->
                    name

                _ ->
                    model.selectedComponentName
        , selectedScreenName =
            case tabRoute of
                Route.ScreensTab name ->
                    name

                _ ->
                    model.selectedScreenName
    }


{-| Re-reads the tab and selection out of the address bar. Needed when something
lands after the navigation that asked for it.
-}
selectFromUrl : Url.Url -> Model -> Model
selectFromUrl url model =
    case Route.parse url of
        Just (Route.Repo repo) ->
            selectFromRoute repo.tab model

        _ ->
            model


{-| Changing tabs and changing selection are both navigations, so that the URL
and the model can never disagree about what you're looking at. With no project
open there's no route to push, so the change is made directly.
-}
navigateToTab : Route.TabRoute -> Model -> ( Model, Effect Msg )
navigateToTab tabRoute model =
    case model.selectedProject of
        Just project ->
            ( model, Effect.PushUrl (Route.toString (Route.forProject project model.currentBranch tabRoute)) )

        Nothing ->
            ( selectFromRoute tabRoute model, Effect.none )


{-| Loads the project the route names, unless it is already the one open. It may
be one we've already listed, in which case we have its id and can go straight for
the contents; otherwise — a deep link, a fresh tab — it has to be looked up by
path first, and `GotProject` picks the work back up.
-}
openProject : String -> Maybe String -> Model -> ( Model, Effect Msg )
openProject path branch model =
    if Maybe.map .pathWithNamespace model.selectedProject == Just path then
        ( model, Effect.none )

    else
        case model.token of
            Nothing ->
                ( model, Effect.none )

            Just token ->
                let
                    alreadyListed =
                        model.projects
                            |> Maybe.withDefault []
                            |> List.filter (\p -> p.pathWithNamespace == path)
                            |> List.head
                in
                case alreadyListed of
                    Just project ->
                        ( resetForProject project branch model
                        , fetchProjectData token project (Maybe.withDefault project.defaultBranch branch)
                        )

                    Nothing ->
                        ( { model | selectedProject = Nothing, commitStatus = Just ( Working, "Loading repository..." ) }
                        , GitLab.Projects.getProject token path GotProject |> Effect.SendRequest
                        )


{-| The model with the session gone.

Not `clearProjectState`: that keeps the session and drops the repository, which
is the opposite of what has happened here.

-}
signedOut : String -> Model -> Model
signedOut reason model =
    { model
        | token = Nothing
        , refreshToken = Nothing
        , user = Nothing
        , error = Just reason
        , startupStatus = Ready
    }


{-| What to do about a request that failed because of who we are rather than
what we asked for.

A 401 used to be recognised in exactly one place — `GET /user` — so an expired
token discovered by a commit reported "Couldn't save to GitLab" and the user
re-clicked Save against a credential that would never work again. Every caller
that can meet a 401 now comes through here.

A refresh token turns expiry into something the app can fix by itself. Without
one, expiry is a sign-in.

-}
handleAuthFailure : Http.Error -> String -> Model -> ( Model, Effect Msg )
handleAuthFailure error fallback model =
    case error of
        Http.BadStatus 401 ->
            case model.refreshToken of
                Just refresh ->
                    ( { model | error = Nothing }
                    , Auth.refreshToken model.authConfig refresh GotRefreshResult |> Effect.SendRequest
                    )

                Nothing ->
                    ( signedOut "Your GitLab session has expired. Sign in again." model
                    , Effect.ClearToken
                    )

        _ ->
            ( { model | error = Just fallback, startupStatus = Ready }, Effect.none )


{-| One file change in a commit, at the version this branch was read at.

Every write goes through here so that no call site can quietly omit the
version: `Dict.get` on a path never read is `Nothing`, which is the right answer
for a create and the honest answer for anything else.

-}
fileAction : Model -> { action : String, filePath : String, content : Maybe String } -> GitLab.Commits.Action
fileAction model fields =
    GitLab.Commits.action
        { action = fields.action
        , filePath = fields.filePath
        , content = fields.content
        , lastCommitId = Dict.get fields.filePath model.fileVersions
        }


{-| Remembers which commit a file was read at, so a later save can say what it
was based on.
-}
noteFileVersion : String -> Maybe String -> Model -> Model
noteFileVersion path lastCommitId model =
    case lastCommitId of
        Just commitId ->
            { model | fileVersions = Dict.insert path commitId model.fileVersions }

        Nothing ->
            model


{-| Records a file the app couldn't use, replacing any earlier report for the
same path so a reload doesn't stack duplicates.
-}
noteLoadError : String -> String -> Model -> Model
noteLoadError path reason model =
    { model
        | loadErrors =
            { path = path, reason = reason }
                :: List.filter (\e -> e.path /= path) model.loadErrors
    }


{-| Why a file couldn't be read, in the terms the person who has to fix it
needs. A decode failure names a file in the repository that is the wrong shape;
everything else is between the browser and GitLab.
-}
httpErrorReason : Http.Error -> String
httpErrorReason error =
    case error of
        Http.BadStatus 404 ->
            "Not found."

        Http.BadStatus 401 ->
            "Not authorised — the session may have expired."

        Http.BadStatus 403 ->
            "Access denied."

        Http.BadStatus code ->
            "GitLab returned " ++ String.fromInt code ++ "."

        Http.Timeout ->
            "The request timed out."

        Http.NetworkError ->
            "Couldn't reach GitLab."

        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.BadBody body ->
            body


{-| A deep link can name a project that doesn't exist, isn't yours, or that your
token has expired out of — three different things to do about it, so say which.
-}
projectErrorMessage : Http.Error -> String
projectErrorMessage error =
    case error of
        Http.BadStatus 404 ->
            "No repository at that address, or you don't have access to it."

        Http.BadStatus 401 ->
            "Your GitLab session has expired. Sign in again."

        _ ->
            "Couldn't reach GitLab to open that repository."


{-| Everything the app reads out of a repository, at one ref.

Opening a repository and switching branch want exactly this list, and they used
to spell it out separately — with the switch missing contracts, so the contracts
you saw after a switch were still the previous branch's.

There used to be a seventh request here, for a `contracts.json` at the
repository root. It was a second convention that could only ever be read: every
write goes to `components/<name>.contract.json`, and both paths decoded a single
`Contract`, so the root file could hold exactly one component's rules and no UI
could produce it. It also raced — it and the components tree listing landed in
whatever order the network chose, and the tree handler reset `contracts`, so a
root file loaded first was intermittently wiped. One convention, and the race
has nowhere to happen.

-}
fetchAtRef : String -> GitLab.Projects.Project -> String -> Effect Msg
fetchAtRef token project ref =
    Effect.batch
        [ GitLab.Files.listTree token project.id ref 1 (GotTree ref 1) |> Effect.SendRequest
        , GitLab.Files.getFileRaw token project.id ref RepoPaths.tokensFile GotTokensFile |> Effect.SendRequest
        , GitLab.Files.listTreeAtPath token project.id ref "themes" (GotThemesTree ref) |> Effect.SendRequest
        , GitLab.Files.listTreeAtPath token project.id ref "components" (GotComponentsTree ref) |> Effect.SendRequest
        , GitLab.Files.listTreeAtPath token project.id ref "layouts" (GotScreensTree ref) |> Effect.SendRequest
        ]


{-| The above, plus the two things that belong to the repository rather than to
any one branch.
-}
fetchProjectData : String -> GitLab.Projects.Project -> String -> Effect Msg
fetchProjectData token project ref =
    Effect.batch
        [ fetchAtRef token project ref
        , GitLab.Branches.listBranches token project.id GotBranches |> Effect.SendRequest
        , GitLab.MergeRequests.listMergeRequests token project.id GotMergeRequests |> Effect.SendRequest
        ]


updateTokenPathLogic : Model -> Msg -> Tokens.TokenPath -> ( Model, Effect Msg )
updateTokenPathLogic model msg path =
    let
        modifyTokenValue currentMsg currentVal =
            case ( currentMsg, currentVal ) of
                ( UpdateToken _ newVal, _ ) ->
                    Tokens.StringValue newVal

                ( UpdateCompositeToken _ prop newVal, Tokens.CompositeValue dict ) ->
                    Tokens.CompositeValue (Dict.insert prop newVal dict)

                ( AddCompositeProperty _ prop, Tokens.CompositeValue dict ) ->
                    Tokens.CompositeValue (Dict.insert prop "" dict)

                ( AddCompositeProperty _ prop, Tokens.StringValue str ) ->
                    Tokens.CompositeValue (Dict.fromList [ ( "value", str ), ( prop, "" ) ])

                ( DeleteCompositeProperty _ prop, Tokens.CompositeValue dict ) ->
                    Tokens.CompositeValue (Dict.remove prop dict)

                ( RevertToSingleValue _, Tokens.CompositeValue dict ) ->
                    Tokens.StringValue (Dict.get "value" dict |> Maybe.withDefault "")

                _ ->
                    currentVal

        applyMsgToToken t =
            { t | value = modifyTokenValue msg t.value }
    in
    case model.activeThemeName of
        Nothing ->
            let
                updateToken ( p, t ) =
                    if p == path then
                        ( p, applyMsgToToken t )

                    else
                        ( p, t )

                newTokens =
                    Maybe.map (List.map updateToken) model.tokens
            in
            ( { model | tokens = newTokens }, Effect.none )

        Just activeName ->
            let
                updateTheme theme =
                    if theme.name == activeName then
                        let
                            hasOverride =
                                List.any (\( p, _ ) -> p == path) theme.overrides

                            newOverrides =
                                if hasOverride then
                                    List.map
                                        (\( p, t ) ->
                                            if p == path then
                                                ( p, applyMsgToToken t )

                                            else
                                                ( p, t )
                                        )
                                        theme.overrides

                                else
                                    let
                                        baseToken =
                                            model.tokens
                                                |> Maybe.andThen (\ts -> List.filter (\( p, _ ) -> p == path) ts |> List.head)
                                                |> Maybe.map Tuple.second
                                    in
                                    case baseToken of
                                        Just bt ->
                                            theme.overrides ++ [ ( path, applyMsgToToken bt ) ]

                                        Nothing ->
                                            theme.overrides
                        in
                        { theme | overrides = newOverrides }

                    else
                        theme
            in
            ( { model | themes = List.map updateTheme model.themes }, Effect.none )


{-| One choke point for the read-only rule, in front of everything else.

The alternative was to disable the controls in the views and leave it there.
That is cheaper and it is also unverifiable: nothing at this level could be
tested, and any second route to the same message — a link, a keyboard shortcut,
a view branch someone forgets to gate — would silently reopen the hole. The
views disable their controls _as well_; a disabled button is the affordance,
this is the guarantee.

-}
update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case ( Guard.isMutating msg, Guard.readOnly model ) of
        ( True, Just reason ) ->
            ( { model | commitStatus = Just ( Failed, Guard.refusal reason ) }, Effect.none )

        _ ->
            updateAllowed msg model


{-| Everything `update` used to be, reached only once the branch has been found
writable. Kept private so there is no way to skip the check.
-}
updateAllowed : Msg -> Model -> ( Model, Effect Msg )
updateAllowed msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Effect.PushUrl (Url.toString url) )

                Browser.External hrefString ->
                    ( model, Effect.LoadUrl hrefString )

        UrlChanged url ->
            case Route.parse url of
                Just route ->
                    applyRoute route { model | url = url }

                Nothing ->
                    ( { model | url = url }, Effect.none )

        GotTokenResult result ->
            case result of
                Ok session ->
                    let
                        currentUrl =
                            model.url

                        -- The code and the state have been used. Leaving them
                        -- in the address bar means a refresh replays a callback
                        -- that can no longer succeed.
                        newUrl =
                            { currentUrl | query = Nothing }
                    in
                    ( { model
                        | token = Just session.accessToken
                        , refreshToken = session.refreshToken
                        , error = Nothing
                      }
                    , Effect.batch
                        [ Effect.CacheSession session
                        , Auth.fetchProfile session.accessToken GotProfile |> Effect.SendRequest
                        , Effect.ReplaceUrl (Url.toString newUrl)
                        ]
                    )

                Err _ ->
                    ( { model | error = Just "Failed to exchange authorization code for token.", startupStatus = Ready }, Effect.none )

        GotRefreshResult result ->
            case result of
                Ok session ->
                    ( { model
                        | token = Just session.accessToken

                        -- GitLab rotates refresh tokens, so the one that came
                        -- back replaces the one that was sent rather than
                        -- joining it.
                        , refreshToken = session.refreshToken
                        , error = Nothing
                      }
                    , Effect.batch
                        [ Effect.CacheSession session
                        , Auth.fetchProfile session.accessToken GotProfile |> Effect.SendRequest
                        ]
                    )

                Err _ ->
                    ( signedOut "Your GitLab session expired and couldn't be renewed. Sign in again." model
                    , Effect.ClearToken
                    )

        GotProfile result ->
            case result of
                Ok user ->
                    ( { model | user = Just user, error = Nothing }
                    , case model.token of
                        Just t ->
                            GitLab.Projects.listProjects t 1 GotProjects |> Effect.SendRequest

                        Nothing ->
                            Effect.none
                    )

                Err error ->
                    handleAuthFailure error "Failed to fetch your GitLab profile." model

        DismissLoadErrors ->
            ( { model | loadErrors = [] }, Effect.none )

        Logout ->
            ( clearProjectState
                { model
                    | token = Nothing
                    , refreshToken = Nothing
                    , user = Nothing
                    , error = Nothing
                    , projects = Nothing
                    , projectsPage = 1
                    , projectSearch = ""
                    , activeTab = TokenStudio
                }
            , Effect.batch
                [ Effect.ClearToken
                , Effect.PushUrl (Route.toString Route.Home)
                ]
            )

        FetchProjects ->
            case model.token of
                Just token ->
                    ( model, GitLab.Projects.listProjects token 1 GotProjects |> Effect.SendRequest )

                Nothing ->
                    ( model, Effect.none )

        GotProjects result ->
            let
                -- A deep link names a repository, so the project list arriving
                -- is not the end of loading — `GotProject` still has to answer.
                -- Revealing the picker in between would flash it for a moment
                -- and then replace it with the editor.
                --
                -- This asks the URL rather than comparing `commitStatus`
                -- against "Loading repository...". Inferring control flow from
                -- the text of a status message is how `StatusLevel` came to
                -- exist (see its docstring): a copy edit would silently turn
                -- the loading screen off.
                stillFetchingProject =
                    case Route.parse model.url of
                        Just (Route.Repo _) ->
                            model.selectedProject == Nothing

                        _ ->
                            False

                status =
                    if stillFetchingProject then
                        Booting

                    else
                        Ready
            in
            case result of
                Ok projects ->
                    ( { model | projects = Just projects, projectsPage = 1, startupStatus = status }, Effect.none )

                Err _ ->
                    ( { model | error = Just "Failed to fetch projects.", startupStatus = status }, Effect.none )

        LoadMoreProjects ->
            case ( model.token, model.projectsPage ) of
                ( Just token, page ) ->
                    ( model, GitLab.Projects.listProjects token (page + 1) GotMoreProjects |> Effect.SendRequest )

                _ ->
                    ( model, Effect.none )

        GotMoreProjects result ->
            case result of
                Ok newProjects ->
                    let
                        currentProjects =
                            model.projects |> Maybe.withDefault []
                    in
                    ( { model | projects = Just (currentProjects ++ newProjects), projectsPage = model.projectsPage + 1 }, Effect.none )

                Err _ ->
                    ( { model | error = Just "Failed to load more projects." }, Effect.none )

        UpdateProjectSearch search ->
            ( { model | projectSearch = search }, Effect.none )

        SelectProject project ->
            -- No branch yet: the project has not been fetched, so its default
            -- branch is not known. `applyRoute` fills it in once it is.
            ( model, Effect.PushUrl (Route.toString (Route.Repo { path = project.pathWithNamespace, branch = Nothing, tab = Route.TokensTab })) )

        UnselectProject ->
            ( model, Effect.PushUrl (Route.toString Route.Home) )

        GotProject result ->
            case ( result, model.token ) of
                ( Ok project, Just token ) ->
                    -- The route asked for this project, and resetting for it
                    -- necessarily forgot what was selected. The rest of the
                    -- route still says, so it applies again — otherwise a deep
                    -- link to a component would land on the right tab with
                    -- nothing chosen the moment the repository arrived.
                    let
                        branch =
                            Route.branchOf model.url

                        resetModel =
                            resetForProject project branch model |> selectFromUrl model.url
                    in
                    ( { resetModel | startupStatus = Ready }
                    , fetchProjectData token project (Maybe.withDefault project.defaultBranch branch)
                    )

                ( Ok _, Nothing ) ->
                    ( { model | commitStatus = Nothing, startupStatus = Ready }, Effect.none )

                ( Err error, _ ) ->
                    ( { model | error = Just (projectErrorMessage error), commitStatus = Nothing, startupStatus = Ready }, Effect.none )

        GotTree ref page result ->
            case result of
                Ok tree ->
                    let
                        -- Page 1 replaces, later pages append. Anything else
                        -- and a re-open of the same branch doubles the tree.
                        accumulated =
                            if page == 1 then
                                tree

                            else
                                (model.repositoryTree |> Maybe.withDefault []) ++ tree

                        -- A full page is the only evidence there might be
                        -- another one; GitLab's total-count headers aren't
                        -- readable from here.
                        more =
                            if List.length tree < GitLab.Files.treePageSize then
                                Effect.none

                            else
                                case ( model.token, model.selectedProject ) of
                                    ( Just token, Just project ) ->
                                        GitLab.Files.listTree token project.id ref (page + 1) (GotTree ref (page + 1))
                                            |> Effect.SendRequest

                                    _ ->
                                        Effect.none
                    in
                    ( { model | repositoryTree = Just accumulated }, more )

                Err _ ->
                    ( { model | error = Just "Failed to fetch repository tree." }, Effect.none )

        GotSchemaValidationResult { valid, errors } ->
            case model.pendingCommit of
                Just pending ->
                    if valid then
                        case ( model.token, model.selectedProject ) of
                            ( Just token, Just project ) ->
                                let
                                    payload =
                                        -- pending.branch, not the branch the
                                        -- model is on now: validation is a
                                        -- round trip through JavaScript, and
                                        -- the user can switch branches inside
                                        -- it.
                                        { branch = pending.branch
                                        , commitMessage = pending.commitMessage
                                        , actions =
                                            [ fileAction model
                                                { action = pending.actionType
                                                , filePath = pending.filePath
                                                , content = Just pending.jsonString
                                                }
                                            ]
                                        }
                                in
                                ( { model | pendingCommit = Nothing, commitStatus = Just ( Working, "Saving..." ) }
                                , GitLab.Commits.createCommit token project.id payload (GotCommitResult pending.commitContext) |> Effect.SendRequest
                                )

                            _ ->
                                ( { model | pendingCommit = Nothing }, Effect.none )

                    else
                        ( { model | pendingCommit = Nothing, commitStatus = Just ( Failed, "Schema validation failed: " ++ String.join ", " errors ) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        GotCommitResult context result ->
            case result of
                Ok () ->
                    let
                        addUnique item lst =
                            if not (List.member item lst) then
                                item :: lst

                            else
                                lst

                        newModel =
                            case context of
                                CommitTokens ->
                                    { model | tokensFileExists = True, originalTokens = model.tokens }

                                CommitTheme name ->
                                    { model | existingThemes = addUnique name model.existingThemes }

                                CommitComponent name ->
                                    { model | existingComponents = addUnique name model.existingComponents, originalComponents = model.components }

                                CommitScreen name ->
                                    { model | existingScreens = addUnique name model.existingScreens }

                                CommitDeleteTheme name ->
                                    { model | existingThemes = List.filter ((/=) name) model.existingThemes }

                                CommitDeleteComponent name ->
                                    { model
                                        | existingComponents = List.filter ((/=) name) model.existingComponents
                                        , existingContracts = List.filter ((/=) name) model.existingContracts
                                    }

                                CommitDeleteScreen name ->
                                    { model | existingScreens = List.filter ((/=) name) model.existingScreens }

                                CommitContract name ->
                                    { model | existingContracts = addUnique name model.existingContracts }

                                CommitDeleteContract name ->
                                    { model | existingContracts = List.filter ((/=) name) model.existingContracts }

                                _ ->
                                    model
                    in
                    ( { newModel | commitStatus = Just ( Done, "Saved" ) }, Effect.none )

                Err error ->
                    case GitLab.Commits.classifyError error of
                        -- Deliberately not auto-merged and not retried. The
                        -- app has no idea what the other change was, and the
                        -- only honest thing it can do is stop and say the file
                        -- moved.
                        GitLab.Commits.StaleFile _ ->
                            ( { model
                                | commitStatus =
                                    Just
                                        ( Failed
                                        , "This file changed in GitLab since you opened the branch. Reload the branch to see the current version — saving now would overwrite that change."
                                        )
                              }
                            , Effect.none
                            )

                        GitLab.Commits.Unauthorized ->
                            handleAuthFailure (Http.BadStatus 401) "Couldn't save to GitLab" model

                        GitLab.Commits.Forbidden ->
                            ( { model | commitStatus = Just ( Failed, "GitLab refused the write to this branch. It may be protected." ) }
                            , Effect.none
                            )

                        GitLab.Commits.OtherError message ->
                            ( { model | commitStatus = Just ( Failed, "Couldn't save to GitLab: " ++ message ) }, Effect.none )

        GotTokensFile result ->
            case result of
                Ok file ->
                    case Decode.decodeString Tokens.decoder file.content of
                        Ok tokensList ->
                            ( noteFileVersion RepoPaths.tokensFile
                                file.lastCommitId
                                { model | tokens = Just tokensList, originalTokens = Just tokensList, tokensFileExists = True, error = Nothing }
                            , Effect.none
                            )

                        Err decodeError ->
                            ( noteLoadError RepoPaths.tokensFile
                                (Decode.errorToString decodeError)
                                { model | error = Just "Couldn't read tokens/tokens.json — the file may be malformed." }
                            , Effect.none
                            )

                -- No tokens file yet is the normal state of a fresh repository,
                -- not an error. The Tokens page shows an empty state for it.
                Err _ ->
                    ( { model | tokens = Just [], originalTokens = Just [], tokensFileExists = False, error = Nothing }, Effect.none )

        GotThemesTree ref result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name) tree

                        themeNames =
                            List.map (\item -> RepoPaths.nameFromThemeFile item.name) jsonFiles

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotThemeFile file.path) |> Effect.SendRequest)
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( { model | existingThemes = themeNames }, Effect.batch cmds )

                Err _ ->
                    ( { model | existingThemes = [] }, Effect.none )

        GotThemeFile path result ->
            case result of
                Ok file ->
                    case Decode.decodeString Tokens.decoder file.content of
                        Ok tokensList ->
                            let
                                themeName =
                                    RepoPaths.nameFromThemeFile path

                                newTheme =
                                    Themes.fromTokens themeName tokensList

                                newThemes =
                                    newTheme :: List.filter (\t -> t.name /= themeName) model.themes
                            in
                            ( noteFileVersion path file.lastCommitId { model | themes = newThemes }, Effect.none )

                        Err decodeError ->
                            ( noteLoadError path (Decode.errorToString decodeError) model, Effect.none )

                Err httpError ->
                    ( noteLoadError path (httpErrorReason httpError) model, Effect.none )

        SelectTheme themeName ->
            -- Each of these two filters is only meaningful in one of the two
            -- modes, and the checkbox for it is only rendered there, so leaving
            -- one ticked across a switch would narrow the list with no visible
            -- control to un-narrow it.
            ( { model | activeThemeName = themeName, tokenOverriddenOnly = False, tokenChangedOnly = False }, Effect.none )

        UpdateNewThemeName name ->
            ( { model | newThemeName = name, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        UpdateNewThemeTemplate template ->
            ( { model | newThemeTemplate = template }, Effect.none )

        CreateTheme ->
            case Naming.check model.newThemeName (List.map .name model.themes) of
                Err problem ->
                    ( { model | commitStatus = Just ( Failed, Naming.describe "theme" "Dark" problem ) }, Effect.none )

                Ok name ->
                    let
                        newTheme =
                            Templates.themeTemplates
                                |> List.filter (\t -> t.id == model.newThemeTemplate)
                                |> List.head
                                |> Maybe.map (\t -> t.build name)
                                |> Maybe.withDefault (Themes.fromTokens name [])
                    in
                    ( { model | themes = newTheme :: model.themes, activeThemeName = Just name, newThemeName = "", newThemeTemplate = "empty", commitStatus = Nothing }, Effect.none )

        UpdateToken path _ ->
            updateTokenPathLogic model msg path

        UpdateCompositeToken path _ _ ->
            updateTokenPathLogic model msg path

        AddCompositeProperty path _ ->
            updateTokenPathLogic model msg path

        DeleteCompositeProperty path _ ->
            updateTokenPathLogic model msg path

        RevertToSingleValue path ->
            updateTokenPathLogic model msg path

        UpdateNewCompositePropertyName name ->
            ( { model | newCompositePropertyName = name }, Effect.none )

        UpdateNewCompositePropertyValue value ->
            ( { model | newCompositePropertyValue = value }, Effect.none )

        UpdateNewTokenPath path ->
            ( { model | newTokenPath = path, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        UpdateNewTokenType t ->
            ( { model | newTokenType = t }, Effect.none )

        UpdateNewTokenValue value ->
            ( { model | newTokenValue = value }, Effect.none )

        CreateToken ->
            case model.tokens of
                Just tokensList ->
                    let
                        -- Segments are split on ".", so joining them back is
                        -- injective and `Naming` can work on the dotted path
                        -- the user actually typed.
                        segments =
                            String.split "." model.newTokenPath |> List.map String.trim |> List.filter (\s -> s /= "")

                        existing =
                            List.map (\( p, _ ) -> String.join "." p) tokensList
                    in
                    case Naming.check (String.join "." segments) existing of
                        Err problem ->
                            ( { model | commitStatus = Just ( Failed, Naming.describe "token" "color.brand.500" problem ) }, Effect.none )

                        Ok _ ->
                            let
                                newToken =
                                    { value = Tokens.StringValue model.newTokenValue
                                    , type_ = model.newTokenType
                                    , description = Nothing
                                    }
                            in
                            ( { model | tokens = Just (( segments, newToken ) :: tokensList), newTokenPath = "", newTokenValue = "", commitStatus = Nothing }, Effect.none )

                Nothing ->
                    ( { model | commitStatus = Just ( Working, "Tokens are still loading" ) }, Effect.none )

        ApplyStarterTokenScale ->
            case model.tokens of
                Just existing ->
                    ( { model | tokens = Just (TokenScale.mergeStarterScale existing) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        UpdateTokenSearch search ->
            ( { model | tokenSearch = search }, Effect.none )

        UpdateTokenTypeFilter type_ ->
            ( { model | tokenTypeFilter = type_ }, Effect.none )

        ToggleTokenOverriddenOnly ->
            ( { model | tokenOverriddenOnly = not model.tokenOverriddenOnly }, Effect.none )

        ToggleTokenChangedOnly ->
            ( { model | tokenChangedOnly = not model.tokenChangedOnly }, Effect.none )

        ClearTokenFilters ->
            ( { model | tokenSearch = "", tokenTypeFilter = "", tokenOverriddenOnly = False, tokenChangedOnly = False }, Effect.none )

        -- The four Save handlers resolve the branch here, at the click, and
        -- carry it in the pending commit. `Guard.writableBranch` returns
        -- Nothing when there is no project open, so it subsumes the
        -- `selectedProject` check these used to make.
        SaveTokens ->
            case ( model.token, Guard.writableBranch model ) of
                ( Just token, Just branch ) ->
                    case model.activeThemeName of
                        Nothing ->
                            case model.tokens of
                                Just tokensList ->
                                    let
                                        jsonValue =
                                            Tokens.encoder tokensList

                                        jsonString =
                                            Encode.encode 2 jsonValue

                                        pending =
                                            { commitContext = CommitTokens
                                            , branch = branch
                                            , actionType =
                                                if model.tokensFileExists then
                                                    "update"

                                                else
                                                    "create"
                                            , filePath = RepoPaths.tokensFile
                                            , commitMessage = "Update base design tokens"
                                            , jsonString = jsonString
                                            }
                                    in
                                    ( { model | commitStatus = Just ( Working, "Validating tokens..." ), pendingCommit = Just pending }
                                    , Effect.ValidateSchema { schema = "tokens", data = jsonValue, context = Encode.null }
                                    )

                                Nothing ->
                                    ( model, Effect.none )

                        Just activeName ->
                            let
                                activeTheme =
                                    List.filter (\t -> t.name == activeName) model.themes |> List.head
                            in
                            case activeTheme of
                                Just theme ->
                                    let
                                        jsonValue =
                                            Tokens.encoder theme.overrides

                                        jsonString =
                                            Encode.encode 2 jsonValue

                                        pending =
                                            { commitContext = CommitTheme activeName
                                            , branch = branch
                                            , actionType =
                                                if List.member activeName model.existingThemes then
                                                    "update"

                                                else
                                                    "create"
                                            , filePath = RepoPaths.themeFile activeName
                                            , commitMessage = "Update " ++ activeName ++ " theme"
                                            , jsonString = jsonString
                                            }
                                    in
                                    ( { model | commitStatus = Just ( Working, "Validating theme..." ), pendingCommit = Just pending }
                                    , Effect.ValidateSchema { schema = "tokens", data = jsonValue, context = Encode.null }
                                    )

                                Nothing ->
                                    ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        SwitchTab tab ->
            navigateToTab (Route.tabRouteFor tab model.selectedComponentName model.selectedScreenName) model

        GotComponentsTree ref result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name && not (RepoPaths.isContractFile item.name)) tree

                        componentNames =
                            List.map (\item -> RepoPaths.nameFromComponentFile item.name) jsonFiles

                        contractFiles =
                            List.filter (\item -> RepoPaths.isContractFile item.name) tree

                        contractComponentNames =
                            List.map (\item -> RepoPaths.nameFromContractFile item.name) contractFiles

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotComponentFile file.path) |> Effect.SendRequest)
                                        jsonFiles
                                        ++ List.map
                                            (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotContractFile file.path) |> Effect.SendRequest)
                                            contractFiles

                                _ ->
                                    []
                    in
                    -- `contracts` is emptied rather than merged into because
                    -- this is the listing that says which contracts the branch
                    -- has at all; a contract for a component deleted on another
                    -- branch must not survive into this one. `forgetBranchState`
                    -- clears it too, so nothing loaded for this ref can be in
                    -- here yet.
                    ( { model | components = Just [], existingComponents = componentNames, contracts = Just [], existingContracts = contractComponentNames }, Effect.batch cmds )

                Err _ ->
                    ( { model | components = Just [], contracts = Just [] }, Effect.none )

        GotComponentFile path result ->
            case result of
                Ok file ->
                    case Decode.decodeString Components.decoder file.content of
                        Ok component ->
                            let
                                currentComponents =
                                    model.components |> Maybe.withDefault []

                                newComponents =
                                    component :: List.filter (\c -> c.name /= component.name) currentComponents
                            in
                            ( noteFileVersion path
                                file.lastCommitId
                                { model | components = Just newComponents, originalComponents = Just newComponents }
                            , Effect.none
                            )

                        -- Swallowing this made a malformed component look
                        -- exactly like one that isn't there — and the app would
                        -- then offer to `create` a file that already exists.
                        Err decodeError ->
                            ( noteLoadError path (Decode.errorToString decodeError) model, Effect.none )

                Err httpError ->
                    ( noteLoadError path (httpErrorReason httpError) model, Effect.none )

        SelectComponent name ->
            navigateToTab (Route.ComponentsTab name) model

        UpdateNewComponentName name ->
            ( { model | newComponentName = name, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        UpdateNewComponentTemplate template ->
            ( { model | newComponentTemplate = template }, Effect.none )

        CreateComponent ->
            let
                currentComponents =
                    model.components |> Maybe.withDefault []
            in
            case Naming.check model.newComponentName (List.map .name currentComponents) of
                Err problem ->
                    ( { model | commitStatus = Just ( Failed, Naming.describe "component" "Button" problem ) }, Effect.none )

                Ok name ->
                    let
                        newComponent =
                            Templates.componentTemplates
                                |> List.filter (\t -> t.id == model.newComponentTemplate)
                                |> List.head
                                |> Maybe.map (\t -> t.build name)
                                |> Maybe.withDefault (Templates.emptyComponent name)
                    in
                    ( { model | components = Just (newComponent :: currentComponents), selectedComponentName = Just name, newComponentName = "", newComponentTemplate = "empty", commitStatus = Nothing }, Effect.none )

        UpdateNewComponentVariant name ->
            ( { model | newComponentVariant = name, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        AddComponentVariant ->
            addNameToComponent
                { noun = "variant"
                , hint = "primary"
                , typed = model.newComponentVariant
                , get = .variants
                , set = \names c -> { c | variants = names }
                , clear = \m -> { m | newComponentVariant = "" }
                }
                model

        RemoveComponentVariant name ->
            removeNameFromComponent
                { get = .variants
                , set = \names c -> { c | variants = names }
                , forget = Components.forgetVariant
                }
                name
                model
                |> Tuple.mapFirst (forgetEditingVariant name)

        UpdateNewComponentSlot name ->
            ( { model | newComponentSlot = name, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        AddComponentSlot ->
            addNameToComponent
                { noun = "slot"
                , hint = "label"
                , typed = model.newComponentSlot
                , get = .slots
                , set = \names c -> { c | slots = names }
                , clear = \m -> { m | newComponentSlot = "" }
                }
                model

        RemoveComponentSlot name ->
            removeNameFromComponent
                { get = .slots
                , set = \names c -> { c | slots = names }
                , forget = Components.forgetSlot
                }
                name
                model

        UpdateNewComponentState name ->
            ( { model | newComponentState = name, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        AddComponentState ->
            addNameToComponent
                { noun = "state"
                , hint = "hover"
                , typed = model.newComponentState
                , get = .states
                , set = \names c -> { c | states = names }
                , clear = \m -> { m | newComponentState = "" }
                }
                model

        RemoveComponentState name ->
            removeNameFromComponent
                { get = .states
                , set = \names c -> { c | states = names }
                , forget = Components.forgetState
                }
                name
                model
                |> Tuple.mapFirst (forgetEditingState name)

        SaveComponent ->
            case ( model.token, Guard.writableBranch model, model.selectedComponentName ) of
                ( Just token, Just branch, Just activeName ) ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        activeComponent =
                            List.filter (\c -> c.name == activeName) currentComponents |> List.head
                    in
                    case activeComponent of
                        Just comp ->
                            let
                                jsonValue =
                                    Components.encoder comp

                                jsonString =
                                    Encode.encode 2 jsonValue

                                actionType =
                                    if List.member activeName model.existingComponents then
                                        "update"

                                    else
                                        "create"

                                pending =
                                    { commitContext = CommitComponent comp.name
                                    , branch = branch
                                    , actionType = actionType
                                    , filePath = RepoPaths.componentFile comp.name
                                    , commitMessage = "Save component " ++ comp.name
                                    , jsonString = jsonString
                                    }
                            in
                            ( { model | commitStatus = Just ( Working, "Validating " ++ comp.name ++ "..." ), pendingCommit = Just pending }
                            , Effect.ValidateSchema { schema = "components", data = jsonValue, context = Encode.null }
                            )

                        Nothing ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        InitComponentLayout newLayout ->
            updateSelectedComponent (\c -> { c | layout = Just newLayout }) model

        UpdateLayoutProperty path prop value ->
            updateLayoutAt path (Components.mapContextStyles (editingContext model) (Dict.insert prop value)) model
                |> Tuple.mapFirst (\m -> { m | newLayoutPropertyName = "", newLayoutPropertyValue = "" })

        RemoveLayoutProperty path prop ->
            -- In the base context this drops the property. In a variant or
            -- state it drops only that layer's opinion of it, so the node goes
            -- back to inheriting — which is what the editor's × means there.
            updateLayoutAt path (Components.mapContextStyles (editingContext model) (Dict.remove prop)) model

        UpdateNewLayoutPropertyName name ->
            ( { model | newLayoutPropertyName = name }, Effect.none )

        UpdateNewLayoutPropertyValue value ->
            ( { model | newLayoutPropertyValue = value }, Effect.none )

        AddLayoutText path content ->
            updateLayoutAt path (appendChild (Components.Element { isSlot = False, styles = Dict.empty, overrides = [] } content)) model

        AddLayoutSlot path ->
            updateLayoutAt path (appendChild (Components.Element { isSlot = True, styles = Dict.empty, overrides = [] } "")) model

        AddLayoutStack path ->
            updateLayoutAt path (appendChild (Components.Stack { direction = "column", styles = Dict.empty, overrides = [] } [])) model

        AddLayoutGrid path ->
            updateLayoutAt path (appendChild (Components.Grid { columns = 2, styles = Dict.empty, overrides = [] } [])) model

        AddLayoutWhen path ->
            updateLayoutAt path (appendChild (Components.When { variant = Nothing, state = Nothing } [])) model

        UpdateLayoutText path newContent ->
            updateLayoutAt path
                (\node ->
                    case node of
                        Components.Element props _ ->
                            Components.Element props newContent

                        _ ->
                            node
                )
                model

        ToggleLayoutNodeIsSlot path isSlot ->
            updateLayoutAt path
                (\node ->
                    case node of
                        -- `content` is the text when this is a text element and
                        -- the slot name when it isn't, so flipping the switch
                        -- used to blank it. Keeping it means toggling back gets
                        -- your text back; an unmatched name just leaves the slot
                        -- picker on its "choose one" prompt.
                        Components.Element props content ->
                            Components.Element { props | isSlot = isSlot } content

                        _ ->
                            node
                )
                model

        UpdateLayoutWhenCondition path field value ->
            let
                newValue =
                    if value == "" then
                        Nothing

                    else
                        Just value
            in
            updateLayoutAt path
                (\node ->
                    case node of
                        Components.When props children ->
                            if field == "variant" then
                                Components.When { props | variant = newValue } children

                            else if field == "state" then
                                Components.When { props | state = newValue } children

                            else
                                node

                        _ ->
                            node
                )
                model

        UpdateEditingVariant variant ->
            ( { model | editingVariant = variant }, Effect.none )

        UpdateEditingState state ->
            ( { model | editingState = state }, Effect.none )

        ClearEditingContext ->
            ( { model | editingVariant = Nothing, editingState = Nothing }, Effect.none )

        DeleteLayoutNode path ->
            -- A node is removed by its parent, so the root — which has no
            -- parent — can't be removed this way.
            case List.reverse path of
                [] ->
                    ( model, Effect.none )

                index :: reversedParent ->
                    updateLayoutAt (List.reverse reversedParent) (removeChildAt index) model

        GotScreensTree ref result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name) tree

                        screenNames =
                            List.map (\item -> RepoPaths.nameFromScreenFile item.name) jsonFiles

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotScreenFile file.path) |> Effect.SendRequest)
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( { model | screens = Just [], existingScreens = screenNames }, Effect.batch cmds )

                Err _ ->
                    ( { model | screens = Just [], existingScreens = [] }, Effect.none )

        GotScreenFile path result ->
            case result of
                Ok file ->
                    case Decode.decodeString Screens.decoder file.content of
                        Ok screen ->
                            let
                                currentScreens =
                                    model.screens |> Maybe.withDefault []

                                newScreens =
                                    screen :: List.filter (\s -> s.name /= screen.name) currentScreens
                            in
                            ( noteFileVersion path file.lastCommitId { model | screens = Just newScreens }, Effect.none )

                        Err decodeError ->
                            ( noteLoadError path (Decode.errorToString decodeError) model, Effect.none )

                Err httpError ->
                    ( noteLoadError path (httpErrorReason httpError) model, Effect.none )

        SelectScreen name ->
            navigateToTab (Route.ScreensTab name) model

        UpdateNewScreenName name ->
            ( { model | newScreenName = name, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        UpdateNewScreenTemplate template ->
            ( { model | newScreenTemplate = template }, Effect.none )

        CreateScreen ->
            let
                currentScreens =
                    model.screens |> Maybe.withDefault []
            in
            case Naming.check model.newScreenName (List.map .name currentScreens) of
                Err problem ->
                    ( { model | commitStatus = Just ( Failed, Naming.describe "screen" "Login" problem ) }, Effect.none )

                Ok name ->
                    let
                        newScreen =
                            Templates.screenTemplates
                                |> List.filter (\t -> t.id == model.newScreenTemplate)
                                |> List.head
                                |> Maybe.map (\t -> t.build name)
                                |> Maybe.withDefault (Templates.emptyScreen name)
                    in
                    ( { model | screens = Just (newScreen :: currentScreens), selectedScreenName = Just name, newScreenName = "", newScreenTemplate = "empty", commitStatus = Nothing }, Effect.none )

        SaveScreen ->
            case ( model.token, Guard.writableBranch model, model.selectedScreenName ) of
                ( Just token, Just branch, Just activeName ) ->
                    let
                        currentScreens =
                            model.screens |> Maybe.withDefault []

                        activeScreen =
                            List.filter (\s -> s.name == activeName) currentScreens |> List.head
                    in
                    case activeScreen of
                        Just screen ->
                            let
                                jsonValue =
                                    Screens.encoder screen

                                jsonString =
                                    Encode.encode 2 jsonValue

                                pending =
                                    { commitContext = CommitScreen screen.name
                                    , branch = branch
                                    , actionType =
                                        if List.member activeName model.existingScreens then
                                            "update"

                                        else
                                            "create"
                                    , filePath = RepoPaths.screenFile screen.name
                                    , commitMessage = "Save screen " ++ screen.name
                                    , jsonString = jsonString
                                    }
                            in
                            ( { model | commitStatus = Just ( Working, "Validating " ++ screen.name ++ "..." ), pendingCommit = Just pending }
                            , Effect.ValidateSchema { schema = "screens", data = jsonValue, context = Encode.null }
                            )

                        Nothing ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        AddComponentToScreen componentName ->
            case model.selectedScreenName of
                Just activeName ->
                    let
                        currentScreens =
                            model.screens |> Maybe.withDefault []

                        updateScreen s =
                            if s.name == activeName then
                                case s.root of
                                    Container props children ->
                                        let
                                            newNode =
                                                ComponentInstance { componentName = componentName, variant = Nothing, state = Nothing, slots = [] }
                                        in
                                        { s | root = Container props (children ++ [ newNode ]) }

                                    _ ->
                                        s

                            else
                                s
                    in
                    ( { model | screens = Just (List.map updateScreen currentScreens) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        AddScreenToScreen screenName ->
            case model.selectedScreenName of
                Just activeName ->
                    let
                        currentScreens =
                            model.screens |> Maybe.withDefault []

                        updateScreen s =
                            if s.name == activeName then
                                case s.root of
                                    Container props children ->
                                        let
                                            newNode =
                                                ScreenInstance { screenName = screenName }
                                        in
                                        { s | root = Container props (children ++ [ newNode ]) }

                                    _ ->
                                        s

                            else
                                s
                    in
                    ( { model | screens = Just (List.map updateScreen currentScreens) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        RemoveScreenNode index ->
            case model.selectedScreenName of
                Just activeName ->
                    let
                        currentScreens =
                            model.screens |> Maybe.withDefault []

                        updateScreen s =
                            if s.name == activeName then
                                case s.root of
                                    Container props children ->
                                        let
                                            newChildren =
                                                List.take index children ++ List.drop (index + 1) children
                                        in
                                        { s | root = Container props newChildren }

                                    _ ->
                                        s

                            else
                                s
                    in
                    ( { model | screens = Just (List.map updateScreen currentScreens) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        DeleteToken path ->
            case model.activeThemeName of
                Nothing ->
                    let
                        newTokens =
                            Maybe.map (List.filter (\( p, _ ) -> p /= path)) model.tokens
                    in
                    ( { model | tokens = newTokens }, Effect.none )

                Just activeName ->
                    let
                        updateTheme theme =
                            if theme.name == activeName then
                                { theme | overrides = List.filter (\( p, _ ) -> p /= path) theme.overrides }

                            else
                                theme
                    in
                    ( { model | themes = List.map updateTheme model.themes }, Effect.none )

        DeleteTheme name ->
            case ( model.token, model.selectedProject, Guard.writableBranch model ) of
                ( Just token, Just project, Just branch ) ->
                    let
                        payload =
                            { branch = branch
                            , commitMessage = "Delete theme " ++ name
                            , actions =
                                [ fileAction model
                                    { action = "delete"
                                    , filePath = RepoPaths.themeFile name
                                    , content = Nothing
                                    }
                                ]
                            }
                    in
                    ( { model | themes = List.filter (\t -> t.name /= name) model.themes, activeThemeName = Nothing, commitStatus = Just ( Working, "Deleting " ++ name ++ "..." ) }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteTheme name)) |> Effect.SendRequest
                    )

                _ ->
                    ( model, Effect.none )

        DeleteComponent name ->
            case ( model.token, model.selectedProject, Guard.writableBranch model ) of
                ( Just token, Just project, Just branch ) ->
                    let
                        contractActions =
                            if List.member name model.existingContracts then
                                [ fileAction model
                                    { action = "delete"
                                    , filePath = RepoPaths.contractFile name
                                    , content = Nothing
                                    }
                                ]

                            else
                                []

                        payload =
                            { branch = branch
                            , commitMessage = "Delete component " ++ name
                            , actions =
                                fileAction model
                                    { action = "delete"
                                    , filePath = RepoPaths.componentFile name
                                    , content = Nothing
                                    }
                                    :: contractActions
                            }

                        currentComponents =
                            model.components |> Maybe.withDefault []

                        currentContracts =
                            model.contracts |> Maybe.withDefault []
                    in
                    ( { model
                        | components = Just (List.filter (\c -> c.name /= name) currentComponents)
                        , contracts = Just (List.filter (\c -> c.component /= name) currentContracts)
                        , selectedComponentName = Nothing
                        , commitStatus = Just ( Working, "Deleting " ++ name ++ "..." )
                      }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteComponent name)) |> Effect.SendRequest
                    )

                _ ->
                    ( model, Effect.none )

        DeleteScreen name ->
            case ( model.token, model.selectedProject, Guard.writableBranch model ) of
                ( Just token, Just project, Just branch ) ->
                    let
                        payload =
                            { branch = branch
                            , commitMessage = "Delete screen " ++ name
                            , actions =
                                [ fileAction model
                                    { action = "delete"
                                    , filePath = RepoPaths.screenFile name
                                    , content = Nothing
                                    }
                                ]
                            }

                        currentScreens =
                            model.screens |> Maybe.withDefault []
                    in
                    ( { model | screens = Just (List.filter (\s -> s.name /= name) currentScreens), selectedScreenName = Nothing, commitStatus = Just ( Working, "Deleting " ++ name ++ "..." ) }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteScreen name)) |> Effect.SendRequest
                    )

                _ ->
                    ( model, Effect.none )

        GotContractFile path result ->
            case result of
                Ok file ->
                    case Decode.decodeString Contracts.decoder file.content of
                        Ok contract ->
                            let
                                currentContracts =
                                    model.contracts |> Maybe.withDefault []

                                newContracts =
                                    contract :: List.filter (\c -> c.component /= contract.component) currentContracts
                            in
                            ( noteFileVersion path file.lastCommitId { model | contracts = Just newContracts }, Effect.none )

                        -- The one the JSON Schema can't catch: `rules` is typed
                        -- as a bare array of objects, so a malformed rule
                        -- validates, commits, and then fails to decode here.
                        Err decodeError ->
                            ( noteLoadError path (Decode.errorToString decodeError) model, Effect.none )

                Err httpError ->
                    ( noteLoadError path (httpErrorReason httpError) model, Effect.none )

        UpdateNewContractRuleType type_ ->
            ( { model | newContractRuleType = type_ }, Effect.none )

        UpdateNewContractRuleField key value ->
            ( { model | newContractRuleFields = Dict.insert key value model.newContractRuleFields }, Effect.none )

        AddContractRule ->
            case model.selectedComponentName of
                Just compName ->
                    let
                        getFloat k =
                            Dict.get k model.newContractRuleFields |> Maybe.andThen String.toFloat

                        getList k =
                            Dict.get k model.newContractRuleFields |> Maybe.map (\s -> String.split "," s |> List.map String.trim |> List.filter ((/=) "")) |> Maybe.withDefault []

                        getString k =
                            Dict.get k model.newContractRuleFields
                                |> Maybe.andThen
                                    (\s ->
                                        if String.trim s == "" then
                                            Nothing

                                        else
                                            Just (String.trim s)
                                    )

                        maybeRule =
                            case model.newContractRuleType of
                                "allowedTokenGroups" ->
                                    let
                                        groups =
                                            getList "groups" |> List.map (String.split ".")
                                    in
                                    if List.isEmpty groups then
                                        Nothing

                                    else
                                        Just (Contracts.AllowedTokenGroups groups)

                                "noHardcodedValues" ->
                                    let
                                        props =
                                            getList "properties"
                                    in
                                    if List.isEmpty props then
                                        Nothing

                                    else
                                        Just (Contracts.NoHardcodedValues props)

                                "spacingOnScale" ->
                                    case ( getList "properties", getString "scale" ) of
                                        ( props, Just scaleStr ) ->
                                            if List.isEmpty props then
                                                Nothing

                                            else
                                                Just (Contracts.SpacingOnScale props (String.split "." scaleStr))

                                        _ ->
                                            Nothing

                                "contrastThreshold" ->
                                    case ( getString "foreground", getString "background", getFloat "minimumRatio" ) of
                                        ( Just fg, Just bg, Just ratio ) ->
                                            Just (Contracts.ContrastThreshold { foreground = fg, background = bg, minimumRatio = ratio })

                                        _ ->
                                            Nothing

                                _ ->
                                    Nothing
                    in
                    case maybeRule of
                        Just rule ->
                            let
                                currentContracts =
                                    model.contracts |> Maybe.withDefault []

                                existingContract =
                                    List.filter (\c -> c.component == compName) currentContracts |> List.head

                                newContract =
                                    case existingContract of
                                        Just c ->
                                            { c | rules = c.rules ++ [ rule ] }

                                        Nothing ->
                                            { component = compName, rules = [ rule ] }

                                newContracts =
                                    newContract :: List.filter (\c -> c.component /= compName) currentContracts
                            in
                            ( { model | contracts = Just newContracts, newContractRuleFields = Dict.empty }, Effect.none )

                        Nothing ->
                            ( model, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        RemoveContractRule index ->
            case model.selectedComponentName of
                Just compName ->
                    let
                        currentContracts =
                            model.contracts |> Maybe.withDefault []

                        existingContract =
                            List.filter (\c -> c.component == compName) currentContracts |> List.head
                    in
                    case existingContract of
                        Just c ->
                            let
                                newRules =
                                    List.take index c.rules ++ List.drop (index + 1) c.rules

                                newContract =
                                    { c | rules = newRules }

                                newContracts =
                                    newContract :: List.filter (\contract -> contract.component /= compName) currentContracts
                            in
                            ( { model | contracts = Just newContracts }, Effect.none )

                        Nothing ->
                            ( model, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        SaveContract ->
            case ( model.token, Guard.writableBranch model, model.selectedComponentName ) of
                ( Just token, Just branch, Just activeName ) ->
                    let
                        currentContracts =
                            model.contracts |> Maybe.withDefault []

                        activeContract =
                            List.filter (\c -> c.component == activeName) currentContracts |> List.head
                    in
                    case activeContract of
                        Just contract ->
                            let
                                jsonValue =
                                    Contracts.encoder contract

                                jsonString =
                                    Encode.encode 2 jsonValue

                                actionType =
                                    if List.member activeName model.existingContracts then
                                        "update"

                                    else
                                        "create"

                                pending =
                                    { commitContext = CommitContract activeName
                                    , branch = branch
                                    , actionType = actionType
                                    , filePath = RepoPaths.contractFile activeName
                                    , commitMessage = "Save contract for " ++ activeName
                                    , jsonString = jsonString
                                    }
                            in
                            ( { model | commitStatus = Just ( Working, "Validating contract for " ++ activeName ++ "..." ), pendingCommit = Just pending }
                            , Effect.ValidateSchema { schema = "contracts", data = jsonValue, context = Encode.null }
                            )

                        Nothing ->
                            -- No contract exists in the model yet, so there is nothing to
                            -- commit. Say so rather than letting the button look broken.
                            ( { model | commitStatus = Just ( Failed, "Add at least one rule before saving." ) }, Effect.none )

                _ ->
                    ( model, Effect.none )

        DeleteContract name ->
            case ( model.token, model.selectedProject, Guard.writableBranch model ) of
                ( Just token, Just project, Just branch ) ->
                    let
                        payload =
                            { branch = branch
                            , commitMessage = "Delete contract for " ++ name
                            , actions =
                                [ fileAction model
                                    { action = "delete"
                                    , filePath = RepoPaths.contractFile name
                                    , content = Nothing
                                    }
                                ]
                            }

                        currentContracts =
                            model.contracts |> Maybe.withDefault []
                    in
                    ( { model | contracts = Just (List.filter (\c -> c.component /= name) currentContracts), commitStatus = Just ( Working, "Deleting contract for " ++ name ++ "..." ) }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteContract name)) |> Effect.SendRequest
                    )

                _ ->
                    ( model, Effect.none )

        JumpToComponent name ->
            ( { model | activeTab = ComponentRegistry, selectedComponentName = Just name }, Effect.none )

        GotBranches result ->
            case result of
                Ok branchList ->
                    ( { model | branches = Just branchList }, Effect.none )

                Err _ ->
                    -- This used to be swallowed, which was defensible when the
                    -- list only filled a dropdown. It decides whether the app
                    -- is editable at all now: without it `Guard` finds nothing
                    -- known to be writable and everything goes read-only, so
                    -- staying quiet would present as the app being inexplicably
                    -- frozen.
                    ( { model | error = Just "Couldn't list this repository's branches, so editing is off until it can. Reload to try again." }
                    , Effect.none
                    )

        -- Merge requests belong to the project, not the branch, so this arrives
        -- once with the rest of the repository and `SwitchBranch` leaves it be.
        -- A repository can perfectly well have none, and failing to list them
        -- is no reason to put an error across the page.
        GotMergeRequests result ->
            case result of
                Ok mrs ->
                    ( { model | mergeRequests = Just mrs }, Effect.none )

                Err _ ->
                    ( model, Effect.none )

        -- A branch change is a navigation, like changing tabs and changing
        -- selection: pushing the URL and letting `applyRoute` do the work is
        -- what keeps the address bar and the model from disagreeing, and it is
        -- what makes Back walk you off a branch again.
        SwitchBranch branchName ->
            case model.selectedProject of
                Just project ->
                    ( model
                    , Effect.PushUrl
                        (Route.toString
                            (Route.forProject project
                                (Just branchName)
                                (Route.tabRouteFor model.activeTab model.selectedComponentName model.selectedScreenName)
                            )
                        )
                    )

                Nothing ->
                    ( model, Effect.none )

        UpdateNewBranchName name ->
            ( { model | newBranchName = name, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        CreateBranch ->
            case ( model.token, model.selectedProject, model.currentBranch ) of
                ( Just token, Just project, Just currentBranch ) ->
                    let
                        -- Checking for a collision here rather than letting
                        -- GitLab 400 keeps the reason specific: the generic
                        -- "Couldn't create the branch" never said which of the
                        -- several possible causes it was.
                        existing =
                            model.branches |> Maybe.withDefault [] |> List.map .name
                    in
                    case Naming.check model.newBranchName existing of
                        Err problem ->
                            ( { model | commitStatus = Just ( Failed, Naming.describe "branch" "feature/new-colors" problem ) }, Effect.none )

                        Ok branchName ->
                            ( { model | commitStatus = Just ( Working, "Creating branch..." ) }
                            , GitLab.Branches.createBranch token project.id branchName currentBranch GotCreateBranchResult |> Effect.SendRequest
                            )

                _ ->
                    ( model, Effect.none )

        GotCreateBranchResult result ->
            case result of
                Ok branch ->
                    let
                        currentBranches =
                            model.branches |> Maybe.withDefault []

                        moved =
                            { model
                                | branches = Just (branch :: currentBranches)
                                , commitStatus = Just ( Done, "Branch created" )
                                , newBranchName = ""
                                , currentBranch = Just branch.name
                            }
                    in
                    -- Note the order, and do not "tidy" it into a plain
                    -- PushUrl: `currentBranch` moves *first*, so the
                    -- `applyBranch` that the pushed URL triggers sees no change
                    -- and does not refetch. That is what lets edits you made
                    -- while browsing the default branch come with you onto the
                    -- branch you just cut for them, which is the whole reason
                    -- read-only mode is bearable.
                    ( moved
                    , case model.selectedProject of
                        Just project ->
                            Effect.PushUrl
                                (Route.toString
                                    (Route.forProject project
                                        (Just branch.name)
                                        (Route.tabRouteFor moved.activeTab moved.selectedComponentName moved.selectedScreenName)
                                    )
                                )

                        Nothing ->
                            Effect.none
                    )

                Err _ ->
                    ( { model | commitStatus = Just ( Failed, "Couldn't create the branch" ) }, Effect.none )

        UpdateMRTitle title ->
            ( { model | mrTitle = title, commitStatus = Naming.clearFailure model.commitStatus }, Effect.none )

        CreateMergeRequest ->
            case ( model.token, model.selectedProject, model.currentBranch ) of
                ( Just token, Just project, Just currentBranch ) ->
                    -- Two different refusals, and they need different remedies:
                    -- being on the default branch takes three steps to fix, so
                    -- report it first rather than collapsing both into one
                    -- "can't do that".
                    if currentBranch == project.defaultBranch then
                        ( { model | commitStatus = Just ( Failed, "You're on " ++ project.defaultBranch ++ " — create a branch, save your changes onto it, then open a merge request" ) }
                        , Effect.none
                        )

                    else if String.trim model.mrTitle == "" then
                        ( { model | commitStatus = Just ( Failed, "Describe what you changed in the merge request title" ) }
                        , Effect.none
                        )

                    else
                        ( { model | commitStatus = Just ( Working, "Opening merge request..." ) }
                        , GitLab.MergeRequests.createMergeRequest token project.id currentBranch project.defaultBranch model.mrTitle GotMRResult |> Effect.SendRequest
                        )

                _ ->
                    ( model, Effect.none )

        GotMRResult result ->
            case result of
                Ok mr ->
                    let
                        currentMRs =
                            model.mergeRequests |> Maybe.withDefault []
                    in
                    ( { model | mergeRequests = Just (mr :: currentMRs), commitStatus = Just ( Done, "Merge request opened" ), mrTitle = "" }, Effect.none )

                Err _ ->
                    ( { model | commitStatus = Just ( Failed, "Couldn't open the merge request" ) }, Effect.none )

        ToggleExportTarget target ->
            let
                newTargets =
                    if List.member target model.exportTargets then
                        List.filter (\t -> t /= target) model.exportTargets

                    else
                        target :: model.exportTargets
            in
            ( { model | exportTargets = newTargets }, Effect.none )

        RunExportPipeline ->
            case ( model.token, model.selectedProject, Guard.writableBranch model ) of
                ( Just token, Just project, Just branch ) ->
                    case model.tokens of
                        Just tokensList ->
                            let
                                -- Whether the file is already there decides
                                -- create-versus-update, and getting it wrong is
                                -- a rejected commit either way. The tree
                                -- listing is recursive now, so a nested path
                                -- like `exports/variables.css` actually appears
                                -- in it; before, nothing ever matched and every
                                -- export after the first one failed.
                                exists path =
                                    model.repositoryTree
                                        |> Maybe.withDefault []
                                        |> List.any (\item -> item.path == path)

                                exportAction path content =
                                    fileAction model
                                        { action =
                                            if exists path then
                                                "update"

                                            else
                                                "create"
                                        , filePath = path
                                        , content = Just content
                                        }

                                finalActions =
                                    List.filterMap
                                        (\target ->
                                            if target == "css" then
                                                Just (exportAction RepoPaths.exportCss (Export.generateCssVariables tokensList))

                                            else if target == "tailwind" then
                                                Just (exportAction RepoPaths.exportTailwind (Export.generateTailwindConfig tokensList))

                                            else
                                                Nothing
                                        )
                                        model.exportTargets

                                payload =
                                    { branch = branch
                                    , commitMessage = "Export Design Tokens pipeline"
                                    , actions = finalActions
                                    }
                            in
                            if List.isEmpty finalActions then
                                ( { model | commitStatus = Just ( Failed, "Pick at least one export format" ) }, Effect.none )

                            else
                                ( { model | commitStatus = Just ( Working, "Exporting..." ) }
                                , GitLab.Commits.createCommit token project.id payload (GotCommitResult CommitOther) |> Effect.SendRequest
                                )

                        Nothing ->
                            ( { model | commitStatus = Just ( Failed, "Load tokens before exporting" ) }, Effect.none )

                _ ->
                    ( { model | commitStatus = Just ( Failed, "Pick a repository and branch before exporting" ) }, Effect.none )
