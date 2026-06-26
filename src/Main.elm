module Main exposing (main)

import Auth
import Browser
import Browser.Navigation as Nav
import Html exposing (Html, a, button, div, h1, h2, h3, h4, img, li, span, text, ul)
import Html.Attributes exposing (href, src, style)
import Html.Events exposing (onClick)
import Http
import Ports
import Url exposing (Url)

import GitLab.Projects exposing (Project)
import GitLab.Files exposing (TreeItem)
import GitLab.Commits exposing (CommitPayload, Action)



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
                        Just t -> GitLab.Projects.listProjects t GotProjects
                        Nothing -> Cmd.none
                    )

                Err _ ->
                    -- On error (e.g., token expired), clear the token
                    ( { model | token = Nothing, user = Nothing, error = Just "Failed to fetch profile. Token may have expired." }
                    , Ports.clearToken ()
                    )

        Logout ->
            ( { model | token = Nothing, user = Nothing, error = Nothing, projects = Nothing, selectedProject = Nothing, repositoryTree = Nothing, commitStatus = Nothing }
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
                    ( { model | selectedProject = Just project, repositoryTree = Nothing, commitStatus = Nothing }
                    , GitLab.Files.listTree token project.id project.defaultBranch GotTree
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
                    ( { model | commitStatus = Just "Failed to commit. (Is test-commit.txt already created?)" }, Cmd.none )



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
                    span [ style "margin-left" "1rem", style "font-weight" "bold", style "color" (if status == "Success!" then "green" else if status == "Writing..." then "blue" else "red") ] [ text status ]

                Nothing ->
                    text ""
            ]
        , h4 [] [ text ("Files in " ++ project.defaultBranch) ]
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
