module Update exposing (update)

import Auth
import Browser
import Browser.Navigation as Nav
import Components
import Contracts
import Dict
import Export
import GitLab.Branches
import GitLab.Commits
import GitLab.Files
import GitLab.MergeRequests
import GitLab.Projects
import Json.Decode as Decode
import Json.Encode as Encode
import Naming
import Ports
import Screens exposing (ScreenNode(..))
import Templates
import Themes
import Tokens
import TokenScale
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
    -> ( Model, Cmd Msg )
addNameToComponent config model =
    case model.selectedComponentName of
        Nothing ->
            ( { model | commitStatus = Just ( Failed, "Pick a component first" ) }, Cmd.none )

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
                    ( { model | commitStatus = Just ( Failed, Naming.describe config.noun config.hint problem ) }, Cmd.none )

                Ok name ->
                    let
                        appendTo c =
                            if c.name == selected then
                                config.set (config.get c ++ [ name ]) c

                            else
                                c
                    in
                    ( config.clear { model | components = Just (List.map appendTo currentComponents), commitStatus = Nothing }
                    , Cmd.none
                    )


updateLayoutNode : List Int -> (Components.Layout -> Components.Layout) -> Components.Layout -> Components.Layout
updateLayoutNode path updateFn layout =
    case path of
        [] ->
            updateFn layout

        index :: rest ->
            case layout of
                Components.Stack props children ->
                    Components.Stack props
                        (List.indexedMap
                            (\i c ->
                                if i == index then
                                    updateLayoutNode rest updateFn c

                                else
                                    c
                            )
                            children
                        )

                Components.Grid props children ->
                    Components.Grid props
                        (List.indexedMap
                            (\i c ->
                                if i == index then
                                    updateLayoutNode rest updateFn c

                                else
                                    c
                            )
                            children
                        )

                Components.Element _ _ ->
                    layout


updateTokenPathLogic : Model -> Msg -> Tokens.TokenPath -> ( Model, Cmd Msg )
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
            ( { model | themes = List.map updateTheme model.themes }, Cmd.none )


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
                        currentUrl =
                            model.url

                        newUrl =
                            { currentUrl | query = Nothing }
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
            ( { model | token = Nothing, user = Nothing, error = Nothing, projects = Nothing, projectsPage = 1, projectSearch = "", selectedProject = Nothing, repositoryTree = Nothing, commitStatus = Nothing, originalTokens = Nothing, tokensFileExists = False, tokens = Nothing, themes = [], existingThemes = [], existingComponents = [], existingScreens = [], activeThemeName = Nothing, newThemeName = "", newTokenPath = "", newTokenType = "color", newTokenValue = "", tokenSearch = "", tokenTypeFilter = "", tokenOverriddenOnly = False, tokenChangedOnly = False, activeTab = TokenStudio, components = Nothing, selectedComponentName = Nothing, newComponentName = "", newComponentVariant = "", newComponentSlot = "", newComponentState = "", screens = Nothing, selectedScreenName = Nothing, newScreenName = "", contracts = Nothing, existingContracts = [], newContractRuleType = "allowedTokenGroups", newContractRuleFields = Dict.empty }
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

        UpdateProjectSearch search ->
            ( { model | projectSearch = search }, Cmd.none )

        SelectProject project ->
            case model.token of
                Just token ->
                    ( { model | selectedProject = Just project, repositoryTree = Nothing, commitStatus = Nothing, originalTokens = Nothing, tokensFileExists = False, tokens = Nothing, themes = [], existingThemes = [], existingComponents = [], existingScreens = [], activeThemeName = Nothing, originalComponents = Nothing, components = Nothing, selectedComponentName = Nothing, screens = Nothing, selectedScreenName = Nothing, currentBranch = Just project.defaultBranch, exportTargets = [ "css", "tailwind" ], contracts = Nothing, existingContracts = [], newContractRuleType = "allowedTokenGroups", newContractRuleFields = Dict.empty }
                    , Cmd.batch
                        [ GitLab.Files.listTree token project.id project.defaultBranch GotTree
                        , GitLab.Files.getFileRaw token project.id project.defaultBranch "tokens/tokens.json" GotTokensFile
                        , GitLab.Files.listTreeAtPath token project.id project.defaultBranch "themes" (GotThemesTree project.defaultBranch)
                        , GitLab.Files.listTreeAtPath token project.id project.defaultBranch "components" (GotComponentsTree project.defaultBranch)
                        , GitLab.Files.listTreeAtPath token project.id project.defaultBranch "layouts" (GotScreensTree project.defaultBranch)
                        , GitLab.Branches.listBranches token project.id GotBranches
                        ]
                    )

                Nothing ->
                    ( model, Cmd.none )

        UnselectProject ->
            ( { model | selectedProject = Nothing, repositoryTree = Nothing, tokens = Nothing, themes = [], components = Nothing, screens = Nothing, activeThemeName = Nothing, selectedComponentName = Nothing, selectedScreenName = Nothing, commitStatus = Nothing, contracts = Nothing, existingContracts = [], newContractRuleType = "allowedTokenGroups", newContractRuleFields = Dict.empty }, Cmd.none )

        GotTree result ->
            case result of
                Ok tree ->
                    ( { model | repositoryTree = Just tree }, Cmd.none )

                Err _ ->
                    ( { model | error = Just "Failed to fetch repository tree." }, Cmd.none )

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
                                    { model | existingComponents = List.filter ((/=) name) model.existingComponents }

                                CommitDeleteScreen name ->
                                    { model | existingScreens = List.filter ((/=) name) model.existingScreens }

                                CommitContract name ->
                                    { model | existingContracts = addUnique name model.existingContracts }

                                CommitDeleteContract name ->
                                    { model | existingContracts = List.filter ((/=) name) model.existingContracts }

                                _ ->
                                    model
                    in
                    ( { newModel | commitStatus = Just ( Done, "Saved" ) }, Cmd.none )

                Err _ ->
                    ( { model | commitStatus = Just ( Failed, "Couldn't save to GitLab" ) }, Cmd.none )

        GotTokensFile result ->
            case result of
                Ok content ->
                    case Decode.decodeString Tokens.decoder content of
                        Ok tokensList ->
                            ( { model | tokens = Just tokensList, originalTokens = Just tokensList, tokensFileExists = True, error = Nothing }, Cmd.none )

                        Err _ ->
                            ( { model | error = Just "Couldn't read tokens/tokens.json — the file may be malformed." }, Cmd.none )

                -- No tokens file yet is the normal state of a fresh repository,
                -- not an error. The Tokens page shows an empty state for it.
                Err _ ->
                    ( { model | tokens = Just [], originalTokens = Just [], tokensFileExists = False, error = Nothing }, Cmd.none )

        GotThemesTree ref result ->
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
                                        (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotThemeFile file.name))
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( { model | existingThemes = themeNames }, Cmd.batch cmds )

                Err _ ->
                    ( { model | existingThemes = [] }, Cmd.none )

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
            -- Each of these two filters is only meaningful in one of the two
            -- modes, and the checkbox for it is only rendered there, so leaving
            -- one ticked across a switch would narrow the list with no visible
            -- control to un-narrow it.
            ( { model | activeThemeName = themeName, tokenOverriddenOnly = False, tokenChangedOnly = False }, Cmd.none )

        UpdateNewThemeName name ->
            ( { model | newThemeName = name, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

        UpdateNewThemeTemplate template ->
            ( { model | newThemeTemplate = template }, Cmd.none )

        CreateTheme ->
            case Naming.check model.newThemeName (List.map .name model.themes) of
                Err problem ->
                    ( { model | commitStatus = Just ( Failed, Naming.describe "theme" "Dark" problem ) }, Cmd.none )

                Ok name ->
                    let
                        newTheme =
                            Templates.themeTemplates
                                |> List.filter (\t -> t.id == model.newThemeTemplate)
                                |> List.head
                                |> Maybe.map (\t -> t.build name)
                                |> Maybe.withDefault (Themes.fromTokens name [])
                    in
                    ( { model | themes = newTheme :: model.themes, activeThemeName = Just name, newThemeName = "", newThemeTemplate = "empty", commitStatus = Nothing }, Cmd.none )

        UpdateToken path _ ->
            updateTokenPathLogic model msg path

        UpdateCompositeToken path _ _ ->
            updateTokenPathLogic model msg path

        AddCompositeProperty path _ ->
            updateTokenPathLogic model msg path

        DeleteCompositeProperty path _ ->
            updateTokenPathLogic model msg path

        UpdateNewCompositePropertyName name ->
            ( { model | newCompositePropertyName = name }, Cmd.none )

        UpdateNewCompositePropertyValue value ->
            ( { model | newCompositePropertyValue = value }, Cmd.none )

        UpdateNewTokenPath path ->
            ( { model | newTokenPath = path, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

        UpdateNewTokenType t ->
            ( { model | newTokenType = t }, Cmd.none )

        UpdateNewTokenValue value ->
            ( { model | newTokenValue = value }, Cmd.none )

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
                            ( { model | commitStatus = Just ( Failed, Naming.describe "token" "color.brand.500" problem ) }, Cmd.none )

                        Ok _ ->
                            let
                                newToken =
                                    { value = Tokens.StringValue model.newTokenValue
                                    , type_ = model.newTokenType
                                    , description = Nothing
                                    }
                            in
                            ( { model | tokens = Just (( segments, newToken ) :: tokensList), newTokenPath = "", newTokenValue = "", commitStatus = Nothing }, Cmd.none )

                Nothing ->
                    ( { model | commitStatus = Just ( Working, "Tokens are still loading" ) }, Cmd.none )

        ApplyStarterTokenScale ->
            case model.tokens of
                Just existing ->
                    ( { model | tokens = Just (TokenScale.mergeStarterScale existing) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdateTokenSearch search ->
            ( { model | tokenSearch = search }, Cmd.none )

        UpdateTokenTypeFilter type_ ->
            ( { model | tokenTypeFilter = type_ }, Cmd.none )

        ToggleTokenOverriddenOnly ->
            ( { model | tokenOverriddenOnly = not model.tokenOverriddenOnly }, Cmd.none )

        ToggleTokenChangedOnly ->
            ( { model | tokenChangedOnly = not model.tokenChangedOnly }, Cmd.none )

        ClearTokenFilters ->
            ( { model | tokenSearch = "", tokenTypeFilter = "", tokenOverriddenOnly = False, tokenChangedOnly = False }, Cmd.none )

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
                                    ( { model | commitStatus = Just ( Working, "Saving tokens..." ) }
                                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult CommitTokens)
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
                                    in
                                    ( { model | commitStatus = Just ( Working, "Saving theme..." ) }
                                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitTheme activeName))
                                    )

                                Nothing ->
                                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SwitchTab tab ->
            ( { model | activeTab = tab }, Cmd.none )

        GotComponentsTree ref result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name && not (String.endsWith ".contract.json" item.name)) tree

                        componentNames =
                            List.map (\item -> String.replace ".json" "" item.name) jsonFiles

                        contractFiles =
                            List.filter (\item -> String.endsWith ".contract.json" item.name) tree

                        contractComponentNames =
                            List.map (\item -> String.replace ".contract.json" "" item.name) contractFiles

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotComponentFile file.name))
                                        jsonFiles
                                        ++ List.map
                                            (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotContractFile file.name))
                                            contractFiles

                                _ ->
                                    []
                    in
                    ( { model | components = Just [], existingComponents = componentNames, contracts = Just [], existingContracts = contractComponentNames }, Cmd.batch cmds )

                Err _ ->
                    ( { model | components = Just [], contracts = Just [] }, Cmd.none )

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
            ( { model | newComponentName = name, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

        UpdateNewComponentTemplate template ->
            ( { model | newComponentTemplate = template }, Cmd.none )

        CreateComponent ->
            let
                currentComponents =
                    model.components |> Maybe.withDefault []
            in
            case Naming.check model.newComponentName (List.map .name currentComponents) of
                Err problem ->
                    ( { model | commitStatus = Just ( Failed, Naming.describe "component" "Button" problem ) }, Cmd.none )

                Ok name ->
                    let
                        newComponent =
                            Templates.componentTemplates
                                |> List.filter (\t -> t.id == model.newComponentTemplate)
                                |> List.head
                                |> Maybe.map (\t -> t.build name)
                                |> Maybe.withDefault (Templates.emptyComponent name)
                    in
                    ( { model | components = Just (newComponent :: currentComponents), selectedComponentName = Just name, newComponentName = "", newComponentTemplate = "empty", commitStatus = Nothing }, Cmd.none )

        UpdateNewComponentVariant name ->
            ( { model | newComponentVariant = name, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

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

        UpdateNewComponentSlot name ->
            ( { model | newComponentSlot = name, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

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

        UpdateNewComponentState name ->
            ( { model | newComponentState = name, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

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
                            in
                            ( { model | commitStatus = Just ( Working, "Saving " ++ comp.name ++ "..." ) }
                            , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitComponent comp.name))
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
                                { c | layout = Just (Components.Stack { direction = "column", styles = Dict.empty } []) }

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdateLayoutProperty path prop value ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just l ->
                                        { c
                                            | layout =
                                                Just
                                                    (updateLayoutNode path
                                                        (\node ->
                                                            case node of
                                                                Components.Stack p children ->
                                                                    Components.Stack { p | styles = Dict.insert prop value p.styles } children

                                                                Components.Grid p children ->
                                                                    Components.Grid { p | styles = Dict.insert prop value p.styles } children

                                                                _ ->
                                                                    node
                                                        )
                                                        l
                                                    )
                                        }

                                    Nothing ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents), newLayoutPropertyName = "", newLayoutPropertyValue = "" }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        RemoveLayoutProperty path prop ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just l ->
                                        { c
                                            | layout =
                                                Just
                                                    (updateLayoutNode path
                                                        (\node ->
                                                            case node of
                                                                Components.Stack p children ->
                                                                    Components.Stack { p | styles = Dict.remove prop p.styles } children

                                                                Components.Grid p children ->
                                                                    Components.Grid { p | styles = Dict.remove prop p.styles } children

                                                                _ ->
                                                                    node
                                                        )
                                                        l
                                                    )
                                        }

                                    Nothing ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdateNewLayoutPropertyName name ->
            ( { model | newLayoutPropertyName = name }, Cmd.none )

        UpdateNewLayoutPropertyValue value ->
            ( { model | newLayoutPropertyValue = value }, Cmd.none )

        AddLayoutText path content ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just l ->
                                        { c
                                            | layout =
                                                Just
                                                    (updateLayoutNode path
                                                        (\node ->
                                                            case node of
                                                                Components.Stack p children ->
                                                                    Components.Stack p (children ++ [ Components.Element { isSlot = False, styles = Dict.empty } content ])

                                                                Components.Grid p children ->
                                                                    Components.Grid p (children ++ [ Components.Element { isSlot = False, styles = Dict.empty } content ])

                                                                _ ->
                                                                    node
                                                        )
                                                        l
                                                    )
                                        }

                                    Nothing ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        AddLayoutStack path ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just l ->
                                        { c
                                            | layout =
                                                Just
                                                    (updateLayoutNode path
                                                        (\node ->
                                                            case node of
                                                                Components.Stack p children ->
                                                                    Components.Stack p (children ++ [ Components.Stack { direction = "column", styles = Dict.empty } [] ])

                                                                Components.Grid p children ->
                                                                    Components.Grid p (children ++ [ Components.Stack { direction = "column", styles = Dict.empty } [] ])

                                                                _ ->
                                                                    node
                                                        )
                                                        l
                                                    )
                                        }

                                    Nothing ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        AddLayoutGrid path ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just l ->
                                        { c
                                            | layout =
                                                Just
                                                    (updateLayoutNode path
                                                        (\node ->
                                                            case node of
                                                                Components.Stack p children ->
                                                                    Components.Stack p (children ++ [ Components.Grid { columns = 2, styles = Dict.empty } [] ])

                                                                Components.Grid p children ->
                                                                    Components.Grid p (children ++ [ Components.Grid { columns = 2, styles = Dict.empty } [] ])

                                                                _ ->
                                                                    node
                                                        )
                                                        l
                                                    )
                                        }

                                    Nothing ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdateLayoutText path newContent ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just l ->
                                        { c
                                            | layout =
                                                Just
                                                    (updateLayoutNode path
                                                        (\node ->
                                                            case node of
                                                                Components.Element p _ ->
                                                                    Components.Element p newContent

                                                                _ ->
                                                                    node
                                                        )
                                                        l
                                                    )
                                        }

                                    Nothing ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        DeleteLayoutNode path ->
            case model.selectedComponentName of
                Just name ->
                    let
                        currentComponents =
                            model.components |> Maybe.withDefault []

                        parentPath =
                            List.take (List.length path - 1) path

                        indexToRemove =
                            List.drop (List.length path - 1) path |> List.head |> Maybe.withDefault -1

                        updateComponent c =
                            if c.name == name then
                                case c.layout of
                                    Just l ->
                                        if indexToRemove >= 0 then
                                            { c
                                                | layout =
                                                    Just
                                                        (updateLayoutNode parentPath
                                                            (\node ->
                                                                case node of
                                                                    Components.Stack p children ->
                                                                        let
                                                                            newChildren =
                                                                                List.indexedMap Tuple.pair children |> List.filter (\( i, _ ) -> i /= indexToRemove) |> List.map Tuple.second
                                                                        in
                                                                        Components.Stack p newChildren

                                                                    Components.Grid p children ->
                                                                        let
                                                                            newChildren =
                                                                                List.indexedMap Tuple.pair children |> List.filter (\( i, _ ) -> i /= indexToRemove) |> List.map Tuple.second
                                                                        in
                                                                        Components.Grid p newChildren

                                                                    _ ->
                                                                        node
                                                            )
                                                            l
                                                        )
                                            }

                                        else
                                            c

                                    -- Cannot remove root this way
                                    Nothing ->
                                        c

                            else
                                c
                    in
                    ( { model | components = Just (List.map updateComponent currentComponents) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        GotScreensTree ref result ->
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
                                        (\file -> GitLab.Files.getFileRaw token project.id ref file.path (GotScreenFile file.name))
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( { model | screens = Just [], existingScreens = screenNames }, Cmd.batch cmds )

                Err _ ->
                    ( { model | screens = Just [], existingScreens = [] }, Cmd.none )

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
            ( { model | newScreenName = name, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

        UpdateNewScreenTemplate template ->
            ( { model | newScreenTemplate = template }, Cmd.none )

        CreateScreen ->
            let
                currentScreens =
                    model.screens |> Maybe.withDefault []
            in
            case Naming.check model.newScreenName (List.map .name currentScreens) of
                Err problem ->
                    ( { model | commitStatus = Just ( Failed, Naming.describe "screen" "Login" problem ) }, Cmd.none )

                Ok name ->
                    let
                        newScreen =
                            Templates.screenTemplates
                                |> List.filter (\t -> t.id == model.newScreenTemplate)
                                |> List.head
                                |> Maybe.map (\t -> t.build name)
                                |> Maybe.withDefault (Templates.emptyScreen name)
                    in
                    ( { model | screens = Just (newScreen :: currentScreens), selectedScreenName = Just name, newScreenName = "", newScreenTemplate = "empty", commitStatus = Nothing }, Cmd.none )

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
                            in
                            ( { model | commitStatus = Just ( Working, "Saving " ++ screen.name ++ "..." ) }
                            , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitScreen screen.name))
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
                    ( { model | themes = List.filter (\t -> t.name /= name) model.themes, activeThemeName = Nothing, commitStatus = Just ( Working, "Deleting " ++ name ++ "..." ) }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteTheme name))
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
                    ( { model | components = Just (List.filter (\c -> c.name /= name) currentComponents), selectedComponentName = Nothing, commitStatus = Just ( Working, "Deleting " ++ name ++ "..." ) }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteComponent name))
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
                    ( { model | screens = Just (List.filter (\s -> s.name /= name) currentScreens), selectedScreenName = Nothing, commitStatus = Just ( Working, "Deleting " ++ name ++ "..." ) }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteScreen name))
                    )

                _ ->
                    ( model, Cmd.none )

        GotContractFile filename result ->
            case result of
                Ok content ->
                    case Decode.decodeString Contracts.decoder content of
                        Ok contract ->
                            let
                                currentContracts =
                                    model.contracts |> Maybe.withDefault []

                                newContracts =
                                    contract :: List.filter (\c -> c.component /= contract.component) currentContracts
                            in
                            ( { model | contracts = Just newContracts }, Cmd.none )

                        Err _ ->
                            ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        UpdateNewContractRuleType type_ ->
            ( { model | newContractRuleType = type_ }, Cmd.none )

        UpdateNewContractRuleField key value ->
            ( { model | newContractRuleFields = Dict.insert key value model.newContractRuleFields }, Cmd.none )

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
                            ( { model | contracts = Just newContracts, newContractRuleFields = Dict.empty }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

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
                            ( { model | contracts = Just newContracts }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        SaveContract ->
            case ( model.token, model.selectedProject, model.selectedComponentName ) of
                ( Just token, Just project, Just activeName ) ->
                    let
                        currentContracts =
                            model.contracts |> Maybe.withDefault []

                        activeContract =
                            List.filter (\c -> c.component == activeName) currentContracts |> List.head
                    in
                    case activeContract of
                        Just contract ->
                            let
                                jsonString =
                                    Encode.encode 2 (Contracts.encoder contract)

                                actionType =
                                    if List.member activeName model.existingContracts then
                                        "update"

                                    else
                                        "create"

                                payload =
                                    { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                                    , commitMessage = "Save contract for " ++ activeName
                                    , actions =
                                        [ { action = actionType
                                          , filePath = "components/" ++ activeName ++ ".contract.json"
                                          , content = Just jsonString
                                          }
                                        ]
                                    }
                            in
                            ( { model | commitStatus = Just ( Working, "Saving contract for " ++ activeName ++ "..." ) }
                            , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitContract activeName))
                            )

                        Nothing ->
                            -- No contract exists in the model yet, so there is nothing to
                            -- commit. Say so rather than letting the button look broken.
                            ( { model | commitStatus = Just ( Failed, "Add at least one rule before saving." ) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        DeleteContract name ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    let
                        payload =
                            { branch = Maybe.withDefault project.defaultBranch model.currentBranch
                            , commitMessage = "Delete contract for " ++ name
                            , actions =
                                [ { action = "delete"
                                  , filePath = "components/" ++ name ++ ".contract.json"
                                  , content = Nothing
                                  }
                                ]
                            }

                        currentContracts =
                            model.contracts |> Maybe.withDefault []
                    in
                    ( { model | contracts = Just (List.filter (\c -> c.component /= name) currentContracts), commitStatus = Just ( Working, "Deleting contract for " ++ name ++ "..." ) }
                    , GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitDeleteContract name))
                    )

                _ ->
                    ( model, Cmd.none )

        JumpToComponent name ->
            ( { model | activeTab = ComponentRegistry, selectedComponentName = Just name }, Cmd.none )

        GotBranches result ->
            case result of
                Ok branchList ->
                    ( { model | branches = Just branchList }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        SwitchBranch branchName ->
            case ( model.token, model.selectedProject ) of
                ( Just token, Just project ) ->
                    ( { model | currentBranch = Just branchName, repositoryTree = Nothing, originalComponents = Nothing, components = Nothing, originalTokens = Nothing, tokens = Nothing, themes = [], screens = Nothing, existingComponents = [], existingThemes = [], existingScreens = [], tokensFileExists = False, commitStatus = Just ( Done, "On branch " ++ branchName ), contracts = Nothing, existingContracts = [], newContractRuleType = "allowedTokenGroups", newContractRuleFields = Dict.empty }
                    , Cmd.batch
                        [ GitLab.Files.listTree token project.id branchName GotTree
                        , GitLab.Files.getFileRaw token project.id branchName "tokens/tokens.json" GotTokensFile
                        , GitLab.Files.listTreeAtPath token project.id branchName "themes" (GotThemesTree branchName)
                        , GitLab.Files.listTreeAtPath token project.id branchName "components" (GotComponentsTree branchName)
                        , GitLab.Files.listTreeAtPath token project.id branchName "layouts" (GotScreensTree branchName)
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateNewBranchName name ->
            ( { model | newBranchName = name, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

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
                            ( { model | commitStatus = Just ( Failed, Naming.describe "branch" "feature/new-colors" problem ) }, Cmd.none )

                        Ok branchName ->
                            ( { model | commitStatus = Just ( Working, "Creating branch..." ) }
                            , GitLab.Branches.createBranch token project.id branchName currentBranch GotCreateBranchResult
                            )

                _ ->
                    ( model, Cmd.none )

        GotCreateBranchResult result ->
            case result of
                Ok branch ->
                    let
                        currentBranches =
                            model.branches |> Maybe.withDefault []
                    in
                    ( { model | branches = Just (branch :: currentBranches), commitStatus = Just ( Done, "Branch created" ), newBranchName = "", currentBranch = Just branch.name }, Cmd.none )

                Err _ ->
                    ( { model | commitStatus = Just ( Failed, "Couldn't create the branch" ) }, Cmd.none )

        UpdateMRTitle title ->
            ( { model | mrTitle = title, commitStatus = Naming.clearFailure model.commitStatus }, Cmd.none )

        CreateMergeRequest ->
            case ( model.token, model.selectedProject, model.currentBranch ) of
                ( Just token, Just project, Just currentBranch ) ->
                    -- Two different refusals, and they need different remedies:
                    -- being on the default branch takes three steps to fix, so
                    -- report it first rather than collapsing both into one
                    -- "can't do that".
                    if currentBranch == project.defaultBranch then
                        ( { model | commitStatus = Just ( Failed, "You're on " ++ project.defaultBranch ++ " — create a branch, save your changes onto it, then open a merge request" ) }
                        , Cmd.none
                        )

                    else if String.trim model.mrTitle == "" then
                        ( { model | commitStatus = Just ( Failed, "Describe what you changed in the merge request title" ) }
                        , Cmd.none
                        )

                    else
                        ( { model | commitStatus = Just ( Working, "Opening merge request..." ) }
                        , GitLab.MergeRequests.createMergeRequest token project.id currentBranch project.defaultBranch model.mrTitle GotMRResult
                        )

                _ ->
                    ( model, Cmd.none )

        GotMRResult result ->
            case result of
                Ok mr ->
                    let
                        currentMRs =
                            model.mergeRequests |> Maybe.withDefault []
                    in
                    ( { model | mergeRequests = Just (mr :: currentMRs), commitStatus = Just ( Done, "Merge request opened" ), mrTitle = "" }, Cmd.none )

                Err _ ->
                    ( { model | commitStatus = Just ( Failed, "Couldn't open the merge request" ) }, Cmd.none )

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
                                ( { model | commitStatus = Just ( Failed, "Pick at least one export format" ) }, Cmd.none )

                            else
                                ( { model | commitStatus = Just ( Working, "Exporting..." ) }
                                , GitLab.Commits.createCommit token project.id payload (GotCommitResult CommitOther)
                                )

                        Nothing ->
                            ( { model | commitStatus = Just ( Failed, "Load tokens before exporting" ) }, Cmd.none )

                _ ->
                    ( { model | commitStatus = Just ( Failed, "Pick a repository and branch before exporting" ) }, Cmd.none )
