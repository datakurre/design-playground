module Main exposing (main)

import Auth
import Browser
import Browser.Navigation as Nav
import GitLab.Commits
import GitLab.Files exposing (TreeItem)
import GitLab.Projects exposing (Project)
import Html exposing (Html, a, button, div, h1, h2, h3, h4, img, li, span, text, ul)
import Html.Attributes exposing (href, src, style, value)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Themes exposing (Theme)
import Tokens
import Url exposing (Url)



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- MODEL


type alias Flags =
    Maybe String


type alias Model =
    { key : Nav.Key
    , url : Url
    , token : Maybe String
    , user : Maybe Auth.User
    , error : Maybe String
    , projects : Maybe (List Project)
    , selectedProject : Maybe Project
    , repositoryTree : Maybe (List TreeItem)
    , commitStatus : Maybe String
    , tokens : Maybe (List Tokens.FlatToken)
    , themes : List Theme
    , activeThemeName : Maybe String
    , newThemeName : String
    }


init : Flags -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        -- Check if the URL has an access token
        urlToken =
            Auth.parseToken url

        -- Determine the final token
        finalToken =
            case urlToken of
                Just t ->
                    Just t

                Nothing ->
                    flags

        initialModel =
            { key = key
            , url = url
            , token = finalToken
            , user = Nothing
            , error = Nothing
            , projects = Nothing
            , selectedProject = Nothing
            , repositoryTree = Nothing
            , commitStatus = Nothing
            , tokens = Nothing
            , themes = []
            , activeThemeName = Nothing
            , newThemeName = ""
            }

        cmds =
            case urlToken of
                Just t ->
                    -- If we got the token from the URL, clear the hash and cache it
                    [ Nav.replaceUrl key (Url.toString { url | fragment = Nothing })
                    , Ports.cacheToken t
                    , Auth.fetchProfile t GotProfile
                    ]

                Nothing ->
                    case finalToken of
                        Just t ->
                            [ Auth.fetchProfile t GotProfile ]

                        Nothing ->
                            []
    in
    ( initialModel, Cmd.batch cmds )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | GotProfile (Result Http.Error Auth.User)
    | Logout
    | FetchProjects
    | GotProjects (Result Http.Error (List Project))
    | SelectProject Project
    | GotTree (Result Http.Error (List TreeItem))
    | WriteTestFile
    | GotCommitResult (Result Http.Error ())
    | FetchTokens
    | GotTokensFile (Result Http.Error String)
    | GotThemesTree (Result Http.Error (List TreeItem))
    | GotThemeFile String (Result Http.Error String)
    | SelectTheme (Maybe String)
    | UpdateNewThemeName String
    | CreateTheme
    | UpdateToken Tokens.TokenPath String
    | SaveTokens


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
            let
                urlToken =
                    Auth.parseToken url
            in
            case urlToken of
                Just t ->
                    ( { model | url = url, token = Just t }
                    , Cmd.batch
                        [ Nav.replaceUrl model.key (Url.toString { url | fragment = Nothing })
                        , Ports.cacheToken t
                        , Auth.fetchProfile t GotProfile
                        ]
                    )

                Nothing ->
                    ( { model | url = url }, Cmd.none )

        GotProfile result ->
            case result of
                Ok user ->
                    ( { model | user = Just user, error = Nothing }
                    , case model.token of
                        Just t ->
                            GitLab.Projects.listProjects t GotProjects

                        Nothing ->
                            Cmd.none
                    )

                Err _ ->
                    -- On error (e.g., token expired), clear the token
                    ( { model | token = Nothing, user = Nothing, error = Just "Failed to fetch profile. Token may have expired." }
                    , Ports.clearToken ()
                    )

        Logout ->
            ( { model | token = Nothing, user = Nothing, error = Nothing, projects = Nothing, selectedProject = Nothing, repositoryTree = Nothing, commitStatus = Nothing, tokens = Nothing, themes = [], activeThemeName = Nothing, newThemeName = "" }
            , Ports.clearToken ()
            )

        FetchProjects ->
            case model.token of
                Just token ->
                    ( model, GitLab.Projects.listProjects token GotProjects )

                Nothing ->
                    ( model, Cmd.none )

        GotProjects result ->
            case result of
                Ok projects ->
                    ( { model | projects = Just projects }, Cmd.none )

                Err _ ->
                    ( { model | error = Just "Failed to fetch projects." }, Cmd.none )

        SelectProject project ->
            case model.token of
                Just token ->
                    ( { model | selectedProject = Just project, repositoryTree = Nothing, commitStatus = Nothing, tokens = Nothing, themes = [], activeThemeName = Nothing }
                    , Cmd.batch
                        [ GitLab.Files.listTree token project.id project.defaultBranch GotTree
                        , GitLab.Files.getFileRaw token project.id project.defaultBranch "tokens/tokens.json" GotTokensFile
                        , GitLab.Files.listTreeAtPath token project.id project.defaultBranch "themes" GotThemesTree
                        ]
                    )

                Nothing ->
                    ( model, Cmd.none )

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
                        payload =
                            { branch = project.defaultBranch
                            , commitMessage = "Test commit from Design Playground"
                            , actions =
                                [ { action = "create"
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
                            ( { model | tokens = Just tokensList, error = Nothing }, Cmd.none )

                        Err err ->
                            ( { model | error = Just ("Failed to parse tokens: " ++ Decode.errorToString err) }, Cmd.none )

                Err _ ->
                    ( { model | tokens = Just [], error = Just "No tokens found or failed to fetch. Start fresh!" }, Cmd.none )

        GotThemesTree result ->
            case result of
                Ok tree ->
                    let
                        jsonFiles =
                            List.filter (\item -> String.endsWith ".json" item.name) tree

                        cmds =
                            case ( model.token, model.selectedProject ) of
                                ( Just token, Just project ) ->
                                    List.map
                                        (\file -> GitLab.Files.getFileRaw token project.id project.defaultBranch file.path (GotThemeFile file.name))
                                        jsonFiles

                                _ ->
                                    []
                    in
                    ( model, Cmd.batch cmds )

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
                                            { branch = project.defaultBranch
                                            , commitMessage = "Update base design tokens"
                                            , actions =
                                                [ { action = "update"
                                                  , filePath = "tokens/tokens.json"
                                                  , content = Just jsonString
                                                  }
                                                ]
                                            }
                                    in
                                    ( { model | commitStatus = Just "Saving base tokens..." }
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
                                            { branch = project.defaultBranch
                                            , commitMessage = "Update " ++ activeName ++ " theme"
                                            , actions =
                                                [ { action = "update"
                                                  , filePath = "themes/" ++ activeName ++ ".json"
                                                  , content = Just jsonString
                                                  }
                                                ]
                                            }
                                    in
                                    ( { model | commitStatus = Just "Saving theme..." }
                                    , GitLab.Commits.createCommit token project.id payload GotCommitResult
                                    )

                                Nothing ->
                                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Design Playground"
    , body =
        [ div [ style "font-family" "sans-serif", style "padding" "2rem" ]
            [ h1 [] [ text "Design Playground SPA" ]
            , viewAuth model
            , div [ style "margin-top" "2rem" ] [ text ("Current URL: " ++ Url.toString model.url) ]
            , div [ style "margin-top" "1rem" ]
                [ a [ href "/" ] [ text "Home" ]
                , text " | "
                , a [ href "/about" ] [ text "About" ]
                ]
            , viewProjects model
            ]
        ]
    }


viewAuth : Model -> Html Msg
viewAuth model =
    div [ style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px", style "display" "inline-block" ]
        [ case model.error of
            Just err ->
                div [ style "color" "red", style "margin-bottom" "1rem" ] [ text err ]

            Nothing ->
                text ""
        , case model.token of
            Nothing ->
                a
                    [ href Auth.loginUrl
                    , style "display" "inline-block"
                    , style "padding" "0.5rem 1rem"
                    , style "background" "#fc6d26"
                    , style "color" "white"
                    , style "text-decoration" "none"
                    , style "border-radius" "4px"
                    , style "font-weight" "bold"
                    ]
                    [ text "Connect to GitLab" ]

            Just _ ->
                case model.user of
                    Nothing ->
                        text "Loading profile..."

                    Just user ->
                        div [ style "display" "flex", style "align-items" "center", style "gap" "1rem" ]
                            [ img [ src user.avatarUrl, style "width" "48px", style "border-radius" "50%" ] []
                            , div []
                                [ div [ style "font-weight" "bold" ] [ text user.name ]
                                , div [ style "color" "#666" ] [ text ("@" ++ user.username) ]
                                ]
                            , button
                                [ onClick Logout
                                , style "margin-left" "1rem"
                                , style "padding" "0.5rem 1rem"
                                , style "cursor" "pointer"
                                , style "background" "#f4f4f4"
                                , style "border" "1px solid #ccc"
                                , style "border-radius" "4px"
                                ]
                                [ text "Logout" ]
                            ]
        ]


viewProjects : Model -> Html Msg
viewProjects model =
    case ( model.token, model.user ) of
        ( Just _, Just _ ) ->
            div [ style "margin-top" "2rem", style "border-top" "1px solid #ccc", style "padding-top" "1rem" ]
                [ h2 [] [ text "GitLab Persistence Layer" ]
                , case model.projects of
                    Nothing ->
                        button [ onClick FetchProjects ] [ text "Load My Projects" ]

                    Just projects ->
                        div [ style "display" "flex", style "gap" "2rem" ]
                            [ div [ style "flex" "1" ]
                                [ h3 [] [ text "Select a Repository" ]
                                , ul [ style "list-style" "none", style "padding" "0" ]
                                    (List.map
                                        (\p ->
                                            li
                                                [ style "padding" "0.5rem"
                                                , style "cursor" "pointer"
                                                , style "border-bottom" "1px solid #eee"
                                                , style "background"
                                                    (if model.selectedProject == Just p then
                                                        "#e0f7fa"

                                                     else
                                                        "transparent"
                                                    )
                                                , onClick (SelectProject p)
                                                ]
                                                [ text p.pathWithNamespace ]
                                        )
                                        projects
                                    )
                                ]
                            , div [ style "flex" "2" ]
                                [ case model.selectedProject of
                                    Nothing ->
                                        text "Select a project to view its repository."

                                    Just project ->
                                        viewProjectDetails model project
                                ]
                            ]
                ]

        _ ->
            text ""


viewProjectDetails : Model -> Project -> Html Msg
viewProjectDetails model project =
    div []
        [ h3 [] [ text ("Repository: " ++ project.name) ]
        , div [ style "margin-bottom" "1rem" ]
            [ button [ onClick WriteTestFile ] [ text "Test Write Operation" ]
            , case model.commitStatus of
                Just status ->
                    span
                        [ style "margin-left" "1rem"
                        , style "font-weight" "bold"
                        , style "color"
                            (if status == "Success!" then
                                "green"

                             else if status == "Writing..." then
                                "blue"

                             else
                                "red"
                            )
                        ]
                        [ text status ]

                Nothing ->
                    text ""
            ]
        , h4 [] [ text "Design Tokens" ]
        , case model.tokens of
            Nothing ->
                text "Loading tokens..."

            Just baseTokens ->
                let
                    -- Determine which tokens to show based on active theme
                    displayTokens =
                        case model.activeThemeName of
                            Nothing ->
                                baseTokens

                            Just activeName ->
                                let
                                    activeTheme =
                                        List.filter (\t -> t.name == activeName) model.themes |> List.head
                                in
                                case activeTheme of
                                    Just theme ->
                                        Themes.applyTheme baseTokens theme

                                    Nothing ->
                                        baseTokens

                    activeThemeObj =
                        model.activeThemeName |> Maybe.andThen (\name -> List.filter (\t -> t.name == name) model.themes |> List.head)
                in
                div [ style "background" "#fff", style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px" ]
                    [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "center", style "margin-bottom" "1rem" ]
                        [ div []
                            [ h4 [ style "margin" "0 0 0.5rem 0" ] [ text "Token Studio" ]
                            , div [ style "display" "flex", style "gap" "0.5rem", style "align-items" "center" ]
                                [ Html.select
                                    [ onInput
                                        (\val ->
                                            SelectTheme
                                                (if val == "" then
                                                    Nothing

                                                 else
                                                    Just val
                                                )
                                        )
                                    , style "padding" "0.5rem"
                                    ]
                                    (Html.option [ value "" ] [ text "Base Theme" ]
                                        :: List.map (\t -> Html.option [ value t.name, Html.Attributes.selected (model.activeThemeName == Just t.name) ] [ text t.name ]) model.themes
                                    )
                                , Html.input
                                    [ value model.newThemeName
                                    , onInput UpdateNewThemeName
                                    , Html.Attributes.placeholder "New theme name"
                                    , style "padding" "0.5rem"
                                    ]
                                    []
                                , button [ onClick CreateTheme, style "padding" "0.5rem" ] [ text "Create Theme" ]
                                ]
                            ]
                        , button [ onClick SaveTokens, style "padding" "0.5rem 1rem", style "background" "#28a745", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ]
                            [ text
                                (if model.activeThemeName == Nothing then
                                    "Save Base Tokens"

                                 else
                                    "Save Theme"
                                )
                            ]
                        ]
                    , if List.isEmpty displayTokens then
                        text "No tokens found."

                      else
                        ul [ style "list-style" "none", style "padding" "0" ]
                            (List.map (\( path, token ) -> viewTokenEditor path token activeThemeObj) displayTokens)
                    ]
        , h4 [ style "margin-top" "2rem" ] [ text ("Files in " ++ project.defaultBranch) ]
        , case model.repositoryTree of
            Nothing ->
                text "Loading files..."

            Just tree ->
                if List.isEmpty tree then
                    text "Repository is empty."

                else
                    ul [ style "font-family" "monospace", style "background" "#f4f4f4", style "padding" "1rem", style "border-radius" "4px" ]
                        (List.map (\item -> li [] [ text (item.mode ++ " " ++ item.type_ ++ " " ++ item.path) ]) tree)
        ]


viewTokenEditor : Tokens.TokenPath -> Tokens.DesignToken -> Maybe Theme -> Html Msg
viewTokenEditor path token activeThemeObj =
    let
        pathString =
            String.join "." path

        isOverridden =
            case activeThemeObj of
                Just theme ->
                    List.any (\( p, _ ) -> p == path) theme.overrides

                Nothing ->
                    False
    in
    li [ style "display" "flex", style "align-items" "center", style "padding" "0.5rem 0", style "border-bottom" "1px solid #eee" ]
        [ div [ style "width" "200px", style "font-family" "monospace", style "font-weight" "bold" ] [ text pathString ]
        , if token.type_ == "color" then
            div [ style "width" "24px", style "height" "24px", style "background" token.value, style "margin-right" "1rem", style "border" "1px solid #ccc", style "border-radius" "4px" ] []

          else
            text ""
        , Html.input
            [ value token.value
            , onInput (UpdateToken path)
            , style "flex" "1"
            , style "padding" "0.5rem"
            , style "border" "1px solid #ccc"
            , style "border-radius" "4px"
            ]
            []
        , div [ style "width" "100px", style "margin-left" "1rem", style "color" "#666", style "font-size" "0.9em" ] [ text token.type_ ]
        , if isOverridden then
            span [ style "margin-left" "1rem", style "background" "#ffeeba", style "padding" "0.2rem 0.5rem", style "border-radius" "4px", style "font-size" "0.8em" ] [ text "Overridden" ]

          else
            text ""
        ]
