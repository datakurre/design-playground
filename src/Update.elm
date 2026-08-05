module Update exposing (update)

import Auth
import Browser
import Browser.Navigation as Nav
import Components
import Export
import GitLab.Branches
import GitLab.Commits
import GitLab.Files
import GitLab.MergeRequests
import GitLab.Projects
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Screens exposing (ScreenNode(..))
import Themes
import Tokens
import Types exposing (..)
import Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External hrefString ->
                    ( model, Nav.load hrefString )

        UrlChanged url ->
            ( { model | url = url }, Cmd.none )

        GotTokenResult result ->
            case result of
                Ok token ->
                    let
                        currentUrl = model.url
                        newUrl = { currentUrl | query = Nothing }
                    in
                    ( { model | token = Just token, error = Nothing }
                    , Cmd.batch
                        [ Ports.cacheToken token
                        , Auth.fetchProfile token GotProfile
                        , Nav.replaceUrl model.key (Url.toString newUrl)
                        ]
                    )

                Err _ ->
                    ( { model | error = Just "Failed to exchange authorization code for token." }, Cmd.none )

        GotProfile result ->
            case result of
                Ok user ->
                    ( { model | user = Just user, error = Nothing }
                    , case model.token of
                        Just t ->
                            GitLab.Projects.listProjects t 1 GotProjects

                        Nothing ->
                            Cmd.none
                    )

                Err _ ->
                    -- On error (e.g., token expired), clear the token
                    ( { model | token = Nothing, user = Nothing, error = Just "Failed to fetch profile. Token may have expired." }
                    , Ports.clearToken ()
                    )

        Logout ->
            ( { model | token = Nothing, user = Nothing, error = Nothing, projects = Nothing, projectsPage = 1, selectedProject = Nothing, repositoryTree = Nothing, commitStatus = Nothing, originalTokens = Nothing, tokensFileExists = False, tokens = Nothing, themes = [], existingThemes = [], existingComponents = [], existingScreens = [], activeThemeName = Nothing, newThemeName = "", newTokenPath = "", newTokenType = "color", newTokenValue = "", activeTab = TokenStudio, components = Nothing, selectedComponentName = Nothing, newComponentName = "", newComponentVariant = "", newComponentSlot = "", newComponentState = "", screens = Nothing, selectedScreenName = Nothing, newScreenName = "" }
            , Ports.clearToken ()
            )

        FetchProjects ->
            case model.token of
                Just token ->
                    ( model, GitLab.Projects.listProjects token 1 GotProjects )

                Nothing ->
                    ( model, Cmd.none )

        GotProjects result ->
            case result of
                Ok projects ->
                    ( { model | projects = Just projects, projectsPage = 1 }, Cmd.none )

                Err _ ->
                    ( { model | error = Just "Failed to fetch projects." }, Cmd.none )

        LoadMoreProjects ->
            case ( model.token, model.projectsPage ) of
                ( Just token, page ) ->
                    ( model, GitLab.Projects.listProjects token (page + 1) GotMoreProjects )

                _ ->
                    ( model, Cmd.none )

        GotMoreProjects result ->
            case result of
                Ok newProjects ->
                    let
                        currentProjects =
                            model.projects |> Maybe.withDefault []
                    in
                    ( { model | projects = Just (currentProjects ++ newProjects), projectsPage = model.projectsPage + 1 }, Cmd.none )

                Err _ ->
                    ( { model | error = Just "Failed to load more projects." }, Cmd.none )

        SelectProject project ->
            case model.token of
                Just token ->
                    ( { model | selectedProject = Just project, repositoryTree = Nothing, commitStatus = Nothing, originalTokens = Nothing, tokensFileExists = False, tokens = Nothing, themes = [], existingThemes = [], existingComponents = [], existingScreens = [], activeThemeName = Nothing, originalComponents = Nothing, components = Nothing, selectedComponentName = Nothing, screens = Nothing, selectedScreenName = Nothing, currentBranch = Just project.defaultBranch, exportTargets = [ "css", "tailwind" ] }
                    , Cmd.batch
                        [ GitLab.Files.listTree token project.id project.defaultBranch GotTree
                        , GitLab.Files.getFileRaw token project.id project.defaultBranch "tokens/tokens.json" GotTokensFile
                        , GitLab.Files.listTreeAtPath token project.id project.defaultBranch "themes" GotThemesTree
                        , GitLab.Files.listTreeAtPath token project.id project.defaultBranch "components" GotComponentsTree
                        , GitLab.Files.listTreeAtPath token project.id project.defaultBranch "layouts" GotScreensTree
                        , GitLab.Branches.listBranches token project.id GotBranches
                        ]
                    )

                Nothing ->
                    ( model, Cmd.none )

        UnselectProject ->
            ( { model | selectedProject = Nothing, repositoryTree = Nothing, tokens = Nothing, themes = [], components = Nothing, screens = Nothing, activeThemeName = Nothing, selectedComponentName = Nothing, selectedScreenName = Nothing, commitStatus = Nothing }, Cmd.none )

        GotTree result ->
            case result of
                Ok tree ->
                    ( { model | repositoryTree = Just tree }, Cmd.none )

                Err _ ->
                    ( { model | error = Just "Failed to fetch repository tree." }, Cmd.none )

        WriteTestFile ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    let
                        actionType =
                            case model.repositoryTree of
                                Just tree ->
                                    if List.any (\item -> item.path == "test-commit.txt") tree then
                                        "update"
                                    else
                                        "create"

                                Nothing ->
                                    "create"

                        payload =
                            { branch = project.defaultBranch
                            , commitMessage = "Test commit from Design Playground"
                            , actions =
                                [ { action = actionType
                                  , filePath = "test-commit.txt"
                                  , content = Just "This is a test commit."
                                  }
                                ]
                            }
                    in
                    ( { model | commitStatus = Just "Writing..." }
                    , GitLab.Commits.createCommit token project.id payload GotCommitResult
                    )

                _ ->
                    ( model, Cmd.none )

        GotCommitResult result ->
            case result of
                Ok () ->
                    ( { model | commitStatus = Just "Success!" }, Cmd.none )

                Err _ ->
                    ( { model | commitStatus = Just "Failed to commit." }, Cmd.none )

        FetchTokens ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    ( model
                    , GitLab.Files.getFileRaw token project.id project.defaultBranch "tokens/tokens.json" GotTokensFile
                    )

                _ ->
                    ( model, Cmd.none )

        GotTokensFile result ->
            case result of
                Ok content ->
                    case Decode.decodeString Tokens.decoder content of
                        Ok tokensList ->
                            ( { model | tokens = Just tokensList, originalTokens = Just tokensList, tokensFileExists = True, error = Nothing }, Cmd.none )

                        Err err ->
                            ( { model | error = Just ("Failed to parse tokens: " ++ Decode.errorToString err) }, Cmd.none )

                Err _ ->
                    ( { model | tokens = Just [], originalTokens = Just [], tokensFileExists = False, error = Just "No tokens found or failed to fetch. Start fresh!" }, Cmd.none )

        GotThemesTree result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name) tree

                        themeNames =
                            List.map (\item -> String.replace ".json" "" item.name) jsonFiles

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id project.defaultBranch file.path (GotThemeFile file.name))
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( { model | existingThemes = themeNames }, Cmd.batch cmds )

                Err _ ->
                    ( model, Cmd.none )

        GotThemeFile filename result ->
            case result of
                Ok content ->
                    case Decode.decodeString Tokens.decoder content of
                        Ok tokensList ->
                            let
                                themeName =
                                    String.replace ".json" "" filename

                                newTheme =
                                    Themes.fromTokens themeName tokensList

                                newThemes =
                                    newTheme :: List.filter (\t -> t.name /= themeName) model.themes
                            in
                            ( { model | themes = newThemes }, Cmd.none )

                        Err _ ->
                            ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        SelectTheme themeName ->
            ( { model | activeThemeName = themeName }, Cmd.none )

        UpdateNewThemeName name ->
            ( { model | newThemeName = name }, Cmd.none )

        CreateTheme ->
            let
                name =
                    String.trim model.newThemeName
            in
            if name /= "" && not (List.any (\t -> t.name == name) model.themes) then
                let
                    newTheme =
                        Themes.fromTokens name []
                in
                ( { model | themes = newTheme :: model.themes, activeThemeName = Just name, newThemeName = "" }, Cmd.none )

            else
                ( model, Cmd.none )

        UpdateToken path newValue ->
            case model.activeThemeName of
                Nothing ->
                    let
                        updateToken ( p, t ) =
                            if p == path then
                                ( p, { t | value = newValue } )

                            else
                                ( p, t )

                        newTokens =
                            Maybe.map (List.map updateToken) model.tokens
                    in
                    ( { model | tokens = newTokens }, Cmd.none )

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
                                                        ( p, { t | value = newValue } )

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
                                                    theme.overrides ++ [ ( path, { bt | value = newValue } ) ]

                                                Nothing ->
                                                    theme.overrides
                                in
                                { theme | overrides = newOverrides }

                            else
                                theme
                    in
                    ( { model | themes = List.map updateTheme model.themes }, Cmd.none )

        UpdateNewTokenPath path ->
            ( { model | newTokenPath = path }, Cmd.none )

        UpdateNewTokenType t ->
            ( { model | newTokenType = t }, Cmd.none )

        UpdateNewTokenValue value ->
            ( { model | newTokenValue = value }, Cmd.none )

        CreateToken ->
            case model.tokens of
                Just tokensList ->
                    let
                        path =
                            String.split "." model.newTokenPath |> List.map String.trim |> List.filter (\s -> s /= "")

                        newToken =
                            { value = model.newTokenValue
                            , type_ = model.newTokenType
                            , description = Nothing
                            }

                        tokenExists =
                            List.any (\( p, _ ) -> p == path) tokensList
                    in
                    if not (List.isEmpty path) && not tokenExists then
                        let
                            newTokens =
                                ( path, newToken ) :: tokensList
                        in
                        ( { model | tokens = Just newTokens, newTokenPath = "", newTokenValue = "" }, Cmd.none )

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        SaveTokens ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    case model.activeThemeName of
                        Nothing ->
                            case model.tokens of
                                Just tokensList ->
                                    let
                                        jsonString =
                                            Encode.encode 2 (Tokens.encoder tokensList)

                                        payload =
                                            { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                                            , commitMessage = "Update base design tokens"
                                            , actions =
                                                [ { action =
                                                        if model.tokensFileExists then
                                                            "update"
                                                        else
                                                            "create"
                                                  , filePath = "tokens/tokens.json"
                                                  , content = Just jsonString
                                                  }
                                                ]
                                            }
                                    in
                                    ( { model | commitStatus = Just "Saving base tokens...", tokensFileExists = True }
                                    , GitLab.Commits.createCommit token project.id payload GotCommitResult
                                    )

                                Nothing ->
                                    ( model, Cmd.none )

                        Just activeName ->
                            let
                                activeTheme =
                                    List.filter (\t -> t.name == activeName) model.themes |> List.head
                            in
                            case activeTheme of
                                Just theme ->
                                    let
                                        jsonString =
                                            Encode.encode 2 (Tokens.encoder theme.overrides)

                                        payload =
                                            { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                                            , commitMessage = "Update " ++ activeName ++ " theme"
                                            , actions =
                                                [ { action =
                                                        if List.member activeName model.existingThemes then
                                                            "update"
                                                        else
                                                            "create"
                                                  , filePath = "themes/" ++ activeName ++ ".json"
                                                  , content = Just jsonString
                                                  }
                                                ]
                                            }
                                        newExistingThemes =
                                            if not (List.member activeName model.existingThemes) then
                                                activeName :: model.existingThemes
                                            else
                                                model.existingThemes
                                    in
                                    ( { model | commitStatus = Just "Saving theme...", existingThemes = newExistingThemes }
                                    , GitLab.Commits.createCommit token project.id payload GotCommitResult
                                    )

                                Nothing ->
                                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SwitchTab tab ->
            ( { model | activeTab = tab }, Cmd.none )

        GotComponentsTree result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name) tree

                        componentNames =
                            List.map (\item -> String.replace ".json" "" item.name) jsonFiles

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id project.defaultBranch file.path (GotComponentFile file.name))
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( { model | components = Just [], existingComponents = componentNames }, Cmd.batch cmds )

                Err _ ->
                    ( { model | components = Just [] }, Cmd.none )

        GotComponentFile filename result ->
            case result of
                Ok content ->
                    case Decode.decodeString Components.decoder content of
                        Ok component ->
                            let
                                currentComponents =
                                    model.components |> Maybe.withDefault []

                                newComponents =
                                    component :: List.filter (\c -> c.name /= component.name) currentComponents
                            in
                            ( { model | components = Just newComponents, originalComponents = Just newComponents }, Cmd.none )

                        Err _ ->
                            ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        SelectComponent name ->
            ( { model | selectedComponentName = name }, Cmd.none )

        UpdateNewComponentName name ->
            ( { model | newComponentName = name }, Cmd.none )

        CreateComponent ->
            let
                name =
                    String.trim model.newComponentName

                currentComponents =
                    model.components |> Maybe.withDefault []
            in
            if name /= "" && not (List.any (\c -> c.name == name) currentComponents) then
                let
                    newComponent =
                        { name = name, description = Nothing, variants = [], slots = [], states = [], layout = Nothing }
                in
                ( { model | components = Just (newComponent :: currentComponents), selectedComponentName = Just name, newComponentName = "" }, Cmd.none )

            else
                ( model, Cmd.none )

        UpdateNewComponentVariant name ->
            ( { model | newComponentVariant = name }, Cmd.none )

        AddComponentVariant ->
            let
                variant =
                    String.trim model.newComponentVariant
            in
            if variant /= "" then
                case model.selectedComponentName of
                    Just name ->
                        let
                            currentComponents =
                                model.components |> Maybe.withDefault []

                            updateComponent c =
                                if c.name == name && not (List.member variant c.variants) then
                                    { c | variants = c.variants ++ [ variant ] }

                                else
                                    c
                        in
                        ( { model | components = Just (List.map updateComponent currentComponents), newComponentVariant = "" }, Cmd.none )

                    Nothing ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        UpdateNewComponentSlot name ->
            ( { model | newComponentSlot = name }, Cmd.none )

        AddComponentSlot ->
            let
                slot =
                    String.trim model.newComponentSlot
            in
            if slot /= "" then
                case model.selectedComponentName of
                    Just name ->
                        let
                            currentComponents =
                                model.components |> Maybe.withDefault []

                            updateComponent c =
                                if c.name == name && not (List.member slot c.slots) then
                                    { c | slots = c.slots ++ [ slot ] }

                                else
                                    c
                        in
                        ( { model | components = Just (List.map updateComponent currentComponents), newComponentSlot = "" }, Cmd.none )

                    Nothing ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        UpdateNewComponentState name ->
            ( { model | newComponentState = name }, Cmd.none )

        AddComponentState ->
            let
                state =
                    String.trim model.newComponentState
            in
            if state /= "" then
                case model.selectedComponentName of
                    Just name ->
                        let
                            currentComponents =
                                model.components |> Maybe.withDefault []

                            updateComponent c =
                                if c.name == name && not (List.member state c.states) then
                                    { c | states = c.states ++ [ state ] }

                                else
                                    c
                        in
                        ( { model | components = Just (List.map updateComponent currentComponents), newComponentState = "", screens = Nothing, selectedScreenName = Nothing, newScreenName = "" }, Cmd.none )

                    Nothing ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        SaveComponent ->
            case ( model.token, model.selectedProject, model.selectedComponentName ) of
                ( Just token, Just project, Just activeName ) ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        activeComponent =
                            List.filter (\c -> c.name == activeName) currentComponents |> List.head
                    in
                    case activeComponent of
                        Just comp ->
                            let
                                jsonString =
                                    Encode.encode 2 (Components.encoder comp)

                                -- Wait, how to know if we should create or update?
                                -- Since we fetched components, if the tree had it, it's an update, else create.
                                -- Let's just use create and fall back?
                                -- Actually, GitLab allows create, but fails if it exists.
                                -- Let's just use "create" if it doesn't exist in repo tree.
                                -- The user's code just says "createCommit", let's use "create" because we didn't handle saving new tokens. Wait, the old code used "update" for saving token/theme overrides.
                                -- If we just created it, maybe it's not in the tree yet.
                                -- I will just write action = "update" and if it fails, the user will see an error. But actually for a brand new component we should use "create".
                                -- Let's determine based on `model.repositoryTree`. Actually, `model.repositoryTree` has `components/name.json`? No, it's `GotComponentsTree` that gave us `tree`. But we don't save that tree.
                                -- For simplicity, let's just use "create". If they edit it later, it should be "update". Let's assume it's always "create" for now since the test says "Save the component and verify the structured data file is committed". Wait, the prompt says "Save the component".
                                -- I will use "create" for now, or maybe the Commits API has a force push?
                                -- No. Let's just do `create`. Wait, if we use `update` and it doesn't exist, it fails.
                                actionType =
                                    if List.member activeName model.existingComponents then
                                        "update"
                                    else
                                        "create"

                                payload =
                                    { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                                    , commitMessage = "Save component " ++ comp.name
                                    , actions =
                                        [ { action = actionType
                                          , filePath = "components/" ++ comp.name ++ ".json"
                                          , content = Just jsonString
                                          }
                                        ]
                                    }

                                newExistingComponents =
                                    if not (List.member activeName model.existingComponents) then
                                        activeName :: model.existingComponents
                                    else
                                        model.existingComponents
                            in
                            ( { model | commitStatus = Just ("Saving component " ++ comp.name ++ "..."), existingComponents = newExistingComponents }
                            , GitLab.Commits.createCommit token project.id payload GotCommitResult
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        InitComponentLayout ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                { c | layout = Just (Components.Stack { direction = "column", padding = Nothing, gap = Nothing, backgroundColor = Nothing } []) }

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdateLayoutPadding p ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just (Components.Stack props children) ->
                                        { c
                                            | layout =
                                                Just
                                                    (Components.Stack
                                                        { props
                                                            | padding =
                                                                if p == "" then
                                                                    Nothing

                                                                else
                                                                    Just p
                                                        }
                                                        children
                                                    )
                                        }

                                    _ ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdateLayoutBackgroundColor bg ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just (Components.Stack props children) ->
                                        { c
                                            | layout =
                                                Just
                                                    (Components.Stack
                                                        { props
                                                            | backgroundColor =
                                                                if bg == "" then
                                                                    Nothing

                                                                else
                                                                    Just bg
                                                        }
                                                        children
                                                    )
                                        }

                                    _ ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        AddLayoutText content ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just (Components.Stack props children) ->
                                        { c | layout = Just (Components.Stack props (children ++ [ Components.Element { isSlot = False, color = Nothing, typography = Nothing } content ])) }

                                    _ ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        GotScreensTree result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name) tree

                        screenNames =
                            List.map (\item -> String.replace ".json" "" item.name) jsonFiles

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id project.defaultBranch file.path (GotScreenFile file.name))
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( { model | screens = Just [], existingScreens = screenNames }, Cmd.batch cmds )

                Err _ ->
                    ( { model | screens = Just [] }, Cmd.none )

        GotScreenFile filename result ->
            case result of
                Ok content ->
                    case Decode.decodeString Screens.decoder content of
                        Ok screen ->
                            let
                                currentScreens =
                                    model.screens |> Maybe.withDefault []

                                newScreens =
                                    screen :: List.filter (\s -> s.name /= screen.name) currentScreens
                            in
                            ( { model | screens = Just newScreens }, Cmd.none )

                        Err _ ->
                            ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        SelectScreen name ->
            ( { model | selectedScreenName = name }, Cmd.none )

        UpdateNewScreenName name ->
            ( { model | newScreenName = name }, Cmd.none )

        CreateScreen ->
            let
                name =
                    String.trim model.newScreenName

                currentScreens =
                    model.screens |> Maybe.withDefault []
            in
            if name /= "" && not (List.any (\s -> s.name == name) currentScreens) then
                let
                    newScreen =
                        { name = name, path = "/" ++ String.replace " " "-" (String.toLower name), root = Container { direction = "column", padding = Just "2rem", gap = Just "1rem" } [] }
                in
                ( { model | screens = Just (newScreen :: currentScreens), selectedScreenName = Just name, newScreenName = "" }, Cmd.none )

            else
                ( model, Cmd.none )

        SaveScreen ->
            case ( model.token, model.selectedProject, model.selectedScreenName ) of
                ( Just token, Just project, Just activeName ) ->
                    let
                        currentScreens =
                            model.screens |> Maybe.withDefault []

                        activeScreen =
                            List.filter (\s -> s.name == activeName) currentScreens |> List.head
                    in
                    case activeScreen of
                        Just screen ->
                            let
                                jsonString =
                                    Encode.encode 2 (Screens.encoder screen)

                                payload =
                                    { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                                    , commitMessage = "Save screen " ++ screen.name
                                    , actions =
                                        [ { action =
                                                if List.member activeName model.existingScreens then
                                                    "update"
                                                else
                                                    "create"
                                          , filePath = "layouts/" ++ screen.name ++ ".json"
                                          , content = Just jsonString
                                          }
                                        ]
                                    }
                                newExistingScreens =
                                    if not (List.member activeName model.existingScreens) then
                                        activeName :: model.existingScreens
                                    else
                                        model.existingScreens
                            in
                            ( { model | commitStatus = Just ("Saving screen " ++ screen.name ++ "..."), existingScreens = newExistingScreens }
                            , GitLab.Commits.createCommit token project.id payload GotCommitResult
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

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
                    ( { model | screens = Just (List.map updateScreen currentScreens) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )
        DeleteToken path ->
            case model.activeThemeName of
                Nothing ->
                    let
                        newTokens =
                            Maybe.map (List.filter (\( p, _ ) -> p /= path)) model.tokens
                    in
                    ( { model | tokens = newTokens }, Cmd.none )

                Just activeName ->
                    let
                        updateTheme theme =
                            if theme.name == activeName then
                                { theme | overrides = List.filter (\( p, _ ) -> p /= path) theme.overrides }

                            else
                                theme
                    in
                    ( { model | themes = List.map updateTheme model.themes }, Cmd.none )

        DeleteTheme name ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    let
                        payload =
                            { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                            , commitMessage = "Delete theme " ++ name
                            , actions =
                                [ { action = "delete"
                                  , filePath = "themes/" ++ name ++ ".json"
                                  , content = Nothing
                                  }
                                ]
                            }
                    in
                    ( { model | themes = List.filter (\t -> t.name /= name) model.themes, activeThemeName = Nothing, commitStatus = Just ("Deleting theme " ++ name ++ "...") }
                    , GitLab.Commits.createCommit token project.id payload GotCommitResult
                    )

                _ ->
                    ( model, Cmd.none )

        DeleteComponent name ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    let
                        payload =
                            { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                            , commitMessage = "Delete component " ++ name
                            , actions =
                                [ { action = "delete"
                                  , filePath = "components/" ++ name ++ ".json"
                                  , content = Nothing
                                  }
                                ]
                            }
                        
                        currentComponents =
                            model.components |> Maybe.withDefault []
                    in
                    ( { model | components = Just (List.filter (\c -> c.name /= name) currentComponents), selectedComponentName = Nothing, commitStatus = Just ("Deleting component " ++ name ++ "...") }
                    , GitLab.Commits.createCommit token project.id payload GotCommitResult
                    )

                _ ->
                    ( model, Cmd.none )

        DeleteScreen name ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    let
                        payload =
                            { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                            , commitMessage = "Delete screen " ++ name
                            , actions =
                                [ { action = "delete"
                                  , filePath = "layouts/" ++ name ++ ".json"
                                  , content = Nothing
                                  }
                                ]
                            }
                        
                        currentScreens =
                            model.screens |> Maybe.withDefault []
                    in
                    ( { model | screens = Just (List.filter (\s -> s.name /= name) currentScreens), selectedScreenName = Nothing, commitStatus = Just ("Deleting screen " ++ name ++ "...") }
                    , GitLab.Commits.createCommit token project.id payload GotCommitResult
                    )

                _ ->
                    ( model, Cmd.none )
        GotBranches result ->
            case result of
                Ok branchList ->
                    ( { model | branches = Just branchList }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        SwitchBranch branchName ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    ( { model | currentBranch = Just branchName, repositoryTree = Nothing, originalComponents = Nothing, components = Nothing, originalTokens = Nothing, tokens = Nothing, themes = [], screens = Nothing, commitStatus = Just ("Switched to branch " ++ branchName) }
                    , Cmd.batch
                        [ GitLab.Files.listTree token project.id branchName GotTree
                        , GitLab.Files.getFileRaw token project.id branchName "tokens/tokens.json" GotTokensFile
                        , GitLab.Files.listTreeAtPath token project.id branchName "themes" GotThemesTree
                        , GitLab.Files.listTreeAtPath token project.id branchName "components" GotComponentsTree
                        , GitLab.Files.listTreeAtPath token project.id branchName "layouts" GotScreensTree
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateNewBranchName name ->
            ( { model | newBranchName = name }, Cmd.none )

        CreateBranch ->
            case ( model.token, model.selectedProject, model.currentBranch ) of
                ( Just token, Just project, Just currentBranch ) ->
                    let
                        branchName =
                            String.trim model.newBranchName
                    in
                    if branchName /= "" then
                        ( { model | commitStatus = Just "Creating branch..." }
                        , GitLab.Branches.createBranch token project.id branchName currentBranch GotCreateBranchResult
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotCreateBranchResult result ->
            case result of
                Ok branch ->
                    let
                        currentBranches =
                            model.branches |> Maybe.withDefault []
                    in
                    ( { model | branches = Just (branch :: currentBranches), commitStatus = Just "Branch created!", newBranchName = "", currentBranch = Just branch.name }, Cmd.none )

                Err _ ->
                    ( { model | commitStatus = Just "Failed to create branch." }, Cmd.none )

        UpdateMRTitle title ->
            ( { model | mrTitle = title }, Cmd.none )

        CreateMergeRequest ->
            case ( model.token, model.selectedProject, model.currentBranch ) of
                ( Just token, Just project, Just currentBranch ) ->
                    if currentBranch /= project.defaultBranch && model.mrTitle /= "" then
                        ( { model | commitStatus = Just "Creating Merge Request..." }
                        , GitLab.MergeRequests.createMergeRequest token project.id currentBranch project.defaultBranch model.mrTitle GotMRResult
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotMRResult result ->
            case result of
                Ok mr ->
                    let
                        currentMRs =
                            model.mergeRequests |> Maybe.withDefault []
                    in
                    ( { model | mergeRequests = Just (mr :: currentMRs), commitStatus = Just ("Merge Request Created: " ++ mr.webUrl), mrTitle = "" }, Cmd.none )

                Err _ ->
                    ( { model | commitStatus = Just "Failed to create Merge Request." }, Cmd.none )

        ToggleExportTarget target ->
            let
                newTargets =
                    if List.member target model.exportTargets then
                        List.filter (\t -> t /= target) model.exportTargets

                    else
                        target :: model.exportTargets
            in
            ( { model | exportTargets = newTargets }, Cmd.none )

        RunExportPipeline ->
            case ( model.token, model.selectedProject, model.currentBranch ) of
                ( Just token, Just project, Just currentBranch ) ->
                    case model.tokens of
                        Just tokensList ->
                            let
                                actions =
                                    List.filterMap
                                        (\target ->
                                            if target == "css" then
                                                Just
                                                    { action = "update"
                                                    , filePath = "exports/variables.css"
                                                    , content = Just (Export.generateCssVariables tokensList)
                                                    }

                                            else if target == "tailwind" then
                                                Just
                                                    { action = "update"
                                                    , filePath = "exports/tailwind.config.js"
                                                    , content = Just (Export.generateTailwindConfig tokensList)
                                                    }

                                            else
                                                Nothing
                                        )
                                        model.exportTargets

                                finalActions =
                                    List.map
                                        (\act ->
                                            let
                                                exists =
                                                    model.repositoryTree
                                                        |> Maybe.withDefault []
                                                        |> List.any (\item -> item.path == act.filePath)
                                            in
                                            { act
                                                | action =
                                                    if exists then
                                                        "update"

                                                    else
                                                        "create"
                                            }
                                        )
                                        actions

                                payload =
                                    { branch = currentBranch
                                    , commitMessage = "Export Design Tokens pipeline"
                                    , actions = finalActions
                                    }
                            in
                            if List.isEmpty finalActions then
                                ( model, Cmd.none )

                            else
                                ( { model | commitStatus = Just "Running export pipeline..." }
                                , GitLab.Commits.createCommit token project.id payload GotCommitResult
                                )

                        Nothing ->
                            ( { model | commitStatus = Just "Export failed: Tokens not loaded." }, Cmd.none )

                _ ->
                    ( { model | commitStatus = Just "Export failed: Project or branch not selected." }, Cmd.none )
