module Main exposing (main)

import Auth
import Browser
import Browser.Navigation as Nav
import GitLab.Projects exposing (Project)
import Html exposing (Html, a, button, div, h1, h2, h3, h4, img, li, span, text, ul)
import Html.Attributes exposing (href, src, style)
import Html.Events exposing (onClick)
import Pages.ComponentRegistry exposing (viewComponentRegistry)
import Pages.ExportPipeline exposing (viewExportPipeline)
import Pages.GitWorkflows exposing (viewGitWorkflows)
import Pages.ScreenComposer exposing (viewScreenComposer)
import Pages.TokenStudio exposing (viewTokenStudio)
import Types exposing (..)
import Update exposing (update)
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


init : Flags -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        -- Check if the URL has an authorization code
        urlCode =
            Auth.parseCode url

        -- Determine the final token
        finalToken =
            flags.token

        initialModel =
            { key = key
            , url = url
            , token = finalToken
            , user = Nothing
            , error = Nothing
            , projects = Nothing
            , projectsPage = 1
            , selectedProject = Nothing
            , repositoryTree = Nothing
            , commitStatus = Nothing
            , originalTokens = Nothing
            , tokensFileExists = False
            , tokens = Nothing
            , themes = []
            , existingThemes = []
            , existingComponents = []
            , existingScreens = []
            , activeThemeName = Nothing
            , newThemeName = ""
            , newTokenPath = ""
            , newTokenType = "color"
            , newTokenValue = ""
            , activeTab = TokenStudio
            , originalComponents = Nothing
            , components = Nothing
            , selectedComponentName = Nothing
            , newComponentName = ""
            , newComponentVariant = ""
            , newComponentSlot = ""
            , newComponentState = ""
            , screens = Nothing
            , selectedScreenName = Nothing
            , newScreenName = ""
            , branches = Nothing
            , currentBranch = Nothing
            , newBranchName = ""
            , commitMessage = ""
            , stagedActions = []
            , mrTitle = ""
            , mergeRequests = Nothing
            , exportTargets = [ "css", "tailwind" ]
            , pkceChallenge = flags.pkceChallenge
            , pkceVerifier = flags.pkceVerifier
            }

        cmds =
            case urlCode of
                Just code ->
                    [ Auth.exchangeToken code flags.pkceVerifier GotTokenResult ]

                Nothing ->
                    case finalToken of
                        Just t ->
                            [ Auth.fetchProfile t GotProfile ]

                        Nothing ->
                            []
    in
    ( initialModel, Cmd.batch cmds )



-- UPDATE
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
                    [ href (Auth.loginUrl model.pkceChallenge)
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
                                , button
                                    [ onClick LoadMoreProjects
                                    , style "margin-top" "1rem"
                                    , style "padding" "0.5rem 1rem"
                                    , style "cursor" "pointer"
                                    ]
                                    [ text "Load More" ]
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
        , div [ style "display" "flex", style "gap" "1rem", style "margin-bottom" "1rem", style "border-bottom" "1px solid #ccc", style "padding-bottom" "0.5rem" ]
            [ button
                [ onClick (SwitchTab TokenStudio)
                , style "padding" "0.5rem 1rem"
                , style "background"
                    (if model.activeTab == TokenStudio then
                        "#e0f7fa"

                     else
                        "transparent"
                    )
                , style "border" "none"
                , style "cursor" "pointer"
                , style "font-weight"
                    (if model.activeTab == TokenStudio then
                        "bold"

                     else
                        "normal"
                    )
                ]
                [ text "Token Studio" ]
            , button
                [ onClick (SwitchTab ComponentRegistry)
                , style "padding" "0.5rem 1rem"
                , style "background"
                    (if model.activeTab == ComponentRegistry then
                        "#e0f7fa"

                     else
                        "transparent"
                    )
                , style "border" "none"
                , style "cursor" "pointer"
                , style "font-weight"
                    (if model.activeTab == ComponentRegistry then
                        "bold"

                     else
                        "normal"
                    )
                ]
                [ text "Component Registry" ]
            , button
                [ onClick (SwitchTab ScreenComposer)
                , style "padding" "0.5rem 1rem"
                , style "background"
                    (if model.activeTab == ScreenComposer then
                        "#e0f7fa"

                     else
                        "transparent"
                    )
                , style "border" "none"
                , style "cursor" "pointer"
                , style "font-weight"
                    (if model.activeTab == ScreenComposer then
                        "bold"

                     else
                        "normal"
                    )
                ]
                [ text "Screen Composer" ]
            , button
                [ onClick (SwitchTab GitWorkflows)
                , style "padding" "0.5rem 1rem"
                , style "background"
                    (if model.activeTab == GitWorkflows then
                        "#e0f7fa"

                     else
                        "transparent"
                    )
                , style "border" "none"
                , style "cursor" "pointer"
                , style "font-weight"
                    (if model.activeTab == GitWorkflows then
                        "bold"

                     else
                        "normal"
                    )
                ]
                [ text "Git Workflows" ]
            , button
                [ onClick (SwitchTab ExportPipeline)
                , style "padding" "0.5rem 1rem"
                , style "background"
                    (if model.activeTab == ExportPipeline then
                        "#e0f7fa"

                     else
                        "transparent"
                    )
                , style "border" "none"
                , style "cursor" "pointer"
                , style "font-weight"
                    (if model.activeTab == ExportPipeline then
                        "bold"

                     else
                        "normal"
                    )
                ]
                [ text "Export Pipeline" ]
            ]
        , if model.activeTab == TokenStudio then
            viewTokenStudio model

          else if model.activeTab == ComponentRegistry then
            viewComponentRegistry model

          else if model.activeTab == ScreenComposer then
            viewScreenComposer model

          else if model.activeTab == GitWorkflows then
            viewGitWorkflows model

          else
            viewExportPipeline model
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
