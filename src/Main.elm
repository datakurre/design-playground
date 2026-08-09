module Main exposing (main)

import Auth
import Browser
import Browser.Navigation as Nav
import Dict
import GitLab.Projects exposing (Project)
import Help
import Html exposing (Html, a, button, div, h2, img, input, li, span, text, ul)
import Html.Attributes exposing (href, src)
import Html.Events exposing (onClick, onInput)
import Pages.ComponentRegistry exposing (viewComponentRegistry)
import Pages.ExportPipeline exposing (viewExportPipeline)
import Pages.GitWorkflows exposing (viewGitWorkflows)
import Pages.ScreenComposer exposing (viewScreenComposer)
import Pages.TokenStudio exposing (viewTokenStudio)
import Route
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (hover)
import Tailwind.Theme exposing (red, s0, s0_dot_5, s14, s2, s200, s3, s4, s50, s6, s700, s8, s900, slate, white)
import Types exposing (..)
import Ui
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
            , projectSearch = ""
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
            , newThemeTemplate = "empty"
            , newTokenPath = ""
            , newTokenType = "color"
            , newTokenValue = ""
            , tokenSearch = ""
            , tokenTypeFilter = ""
            , tokenOverriddenOnly = False
            , tokenChangedOnly = False
            , newCompositePropertyName = ""
            , newCompositePropertyValue = ""
            , activeTab = TokenStudio
            , originalComponents = Nothing
            , components = Nothing
            , selectedComponentName = Nothing
            , newComponentName = ""
            , newComponentTemplate = "empty"
            , newComponentVariant = ""
            , newComponentSlot = ""
            , newComponentState = ""
            , previewComponentVariant = Nothing
            , previewComponentState = Nothing
            , newLayoutPropertyName = ""
            , newLayoutPropertyValue = ""
            , screens = Nothing
            , selectedScreenName = Nothing
            , newScreenName = ""
            , newScreenTemplate = "empty"
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
            , contracts = Nothing
            , existingContracts = []
            , newContractRuleType = "allowedTokenGroups"
            , newContractRuleFields = Dict.empty
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
        [ div [ classes [ Tw.min_h_screen, Tw.bg_color (slate s50), Tw.text_color (slate s900) ] ]
            [ viewAppBar model
            , div [ Ui.page ]
                [ viewError model
                , viewWorkspace model
                ]
            ]
        ]
    }


{-| One slim bar carries identity, the current repository, and account
controls. Everything the old header showed above the fold — a "Design
Playground SPA" hero, the raw current URL, and Home/About links that went
nowhere — is gone.
-}
viewAppBar : Model -> Html Msg
viewAppBar model =
    div
        [ classes
            [ Tw.bg_simple white
            , Tw.border_b
            , Tw.border_color (slate s200)
            , Tw.px s4
            ]
        ]
        [ div
            [ classes
                [ Tw.mx_auto
                , Tw.raw "max-w-6xl"
                , Tw.flex
                , Tw.items_center
                , Tw.justify_between
                , Tw.gap s4
                , Tw.h s14
                ]
            ]
            [ div [ classes [ Tw.font_semibold, Tw.text_sm ] ] [ text "Design Playground" ]
            , div [ classes [ Tw.flex, Tw.items_center, Tw.gap s3 ] ]
                [ -- The status pill is how the create forms report a refusal,
                  -- and it sits a long way from the form that caused it.
                  -- Announcing it at least keeps that from being silent twice.
                  div [ Html.Attributes.attribute "aria-live" "polite" ]
                    [ viewStatus model.commitStatus ]
                , viewRepoBadge model
                , viewAccount model
                ]
            ]
        ]


viewStatus : Maybe Status -> Html Msg
viewStatus status =
    case status of
        Just ( level, message ) ->
            Ui.pill
                (case level of
                    Working ->
                        Ui.Neutral

                    Done ->
                        Ui.Positive

                    Failed ->
                        Ui.Negative
                )
                message

        Nothing ->
            text ""


viewRepoBadge : Model -> Html Msg
viewRepoBadge model =
    case model.selectedProject of
        Just project ->
            div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2 ] ]
                [ span [ classes [ Tw.text_sm, Tw.font_medium ] ] [ text project.pathWithNamespace ]
                , button [ Ui.btnNeutral, onClick UnselectProject ] [ text "Change" ]
                ]

        Nothing ->
            text ""


viewAccount : Model -> Html Msg
viewAccount model =
    case model.token of
        Nothing ->
            a [ Ui.btnBrand, href (Auth.loginUrl model.pkceChallenge) ] [ text "Connect to GitLab" ]

        Just _ ->
            case model.user of
                Nothing ->
                    span [ Ui.muted ] [ text "Signing in..." ]

                Just user ->
                    div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2 ] ]
                        [ img
                            [ src user.avatarUrl
                            , Html.Attributes.alt (user.name ++ " (@" ++ user.username ++ ")")
                            , Html.Attributes.title (user.name ++ " (@" ++ user.username ++ ")")
                            , classes [ Tw.w s6, Tw.h s6, Tw.rounded_full ]
                            ]
                            []
                        , button [ Ui.btnNeutral, onClick Logout ] [ text "Sign out" ]
                        ]


viewError : Model -> Html Msg
viewError model =
    case model.error of
        Just err ->
            div
                [ classes
                    [ Tw.mb s4
                    , Tw.p s3
                    , Tw.rounded_md
                    , Tw.border
                    , Tw.border_color (red s200)
                    , Tw.bg_color (red s50)
                    , Tw.text_sm
                    , Tw.text_color (red s700)
                    ]
                ]
                [ text err ]

        Nothing ->
            text ""


{-| Signed out, there is nothing to show but the sign-in button in the bar.
Signed in without a repository, the user picks one. After that, the editor.
-}
viewWorkspace : Model -> Html Msg
viewWorkspace model =
    case ( model.token, model.user ) of
        ( Just _, Just _ ) ->
            case model.projects of
                Nothing ->
                    div [ classes [ Tw.text_center, Tw.py s8 ] ]
                        [ div [ Ui.muted, classes [ Tw.mb s3 ] ]
                            [ text "Your design tokens, components and screens live in a GitLab repository." ]
                        , button [ Ui.btnPrimary, onClick FetchProjects ] [ text "Choose a repository" ]
                        , viewOrderOfOperations
                        ]

                Just projects ->
                    case model.selectedProject of
                        Nothing ->
                            viewProjectPicker model.projectSearch projects

                        Just project ->
                            viewEditor model project

        _ ->
            div [ classes [ Tw.text_center, Tw.py s8 ] ]
                [ h2 [ Ui.pageTitle, classes [ Tw.mb s2 ] ] [ text "Design tokens, kept in Git" ]
                , div [ Ui.muted ]
                    [ text "Connect your GitLab account to edit the tokens, components and screens in one of your repositories." ]
                , viewOrderOfOperations
                ]


{-| The signed-out and no-repository screens are the only surfaces a user
passes through exactly once, which makes them the right place for the two
things that are true of the whole app and fit nowhere inside it: what order
the tabs go in, and that editing without branching first commits to the
default branch. Neither fits in a tab's one-line lede.
-}
viewOrderOfOperations : Html Msg
viewOrderOfOperations =
    div [ Ui.muted, classes [ Tw.mt s6, Tw.mx_auto, Tw.raw "max-w-xl", Tw.text_left ] ]
        [ div [ classes [ Tw.mb s2 ] ]
            [ text "The tabs run in the order you'd work in them: "
            , span [ classes [ Tw.font_medium ] ] [ text "Tokens" ]
            , text " define the values, "
            , span [ classes [ Tw.font_medium ] ] [ text "Components" ]
            , text " bundle them into reusable pieces, "
            , span [ classes [ Tw.font_medium ] ] [ text "Screens" ]
            , text " compose those into pages, and "
            , span [ classes [ Tw.font_medium ] ] [ text "Export" ]
            , text " writes the tokens out for other projects."
            ]
        , div []
            [ text "There's no backend and no draft state: every save is a commit. Start on "
            , span [ classes [ Tw.font_medium ] ] [ text "Branches & Reviews" ]
            , text " and create a branch first, or your first save lands on the default branch."
            ]
        ]


{-| Filters client-side over whatever pages of projects are already loaded —
it doesn't query GitLab. "Load more" still fetches additional pages
separately, so a repository that hasn't been paged in yet won't show up
until it has.
-}
viewProjectPicker : String -> List Project -> Html Msg
viewProjectPicker search projects =
    let
        visibleProjects =
            if String.trim search == "" then
                projects

            else
                List.filter
                    (\p -> String.contains (String.toLower search) (String.toLower p.pathWithNamespace))
                    projects
    in
    div [ classes [ Tw.mx_auto, Tw.raw "max-w-xl" ] ]
        [ h2 [ Ui.pageTitle, classes [ Tw.mb s3 ] ] [ text "Choose a repository" ]
        , input
            [ Ui.textInput
            , Html.Attributes.type_ "search"
            , Html.Attributes.value search
            , onInput UpdateProjectSearch
            , Html.Attributes.placeholder "Filter repositories"
            , Html.Attributes.attribute "aria-label" "Filter repositories"
            , Html.Attributes.spellcheck False
            , classes [ Tw.w_full, Tw.mb s3 ]
            ]
            []
        , ul [ Ui.panel, classes [ Tw.list_none, Tw.p s0 ] ]
            (List.map
                (\p ->
                    li []
                        [ a
                            [ href (Route.toString (Route.Repo p.pathWithNamespace Route.TokensTab))
                            , classes
                                [ Tw.w_full
                                , Tw.block
                                , Tw.text_left
                                , Tw.px s4
                                , Tw.py s3
                                , Tw.text_sm
                                , Tw.border_none
                                , Tw.raw "bg-transparent"
                                , Tw.cursor_pointer
                                , Tw.border_b
                                , Tw.border_color (slate s200)
                                , Tw.no_underline
                                , hover [ Tw.bg_color (slate s50) ]
                                ]
                            ]
                            [ text p.pathWithNamespace ]
                        ]
                )
                visibleProjects
            )
        , div [ classes [ Tw.mt s3, Tw.text_center ] ]
            [ button [ Ui.btnNeutral, onClick LoadMoreProjects ] [ text "Load more" ] ]
        ]


viewEditor : Model -> Project -> Html Msg
viewEditor model project =
    div []
        [ viewTabs model

        -- One line saying what this tab is for, in the one place every tab
        -- passes through. The pages used to each carry their own "?" beside
        -- their title; collapsed, that told a new user nothing.
        , Ui.tabLede (Help.forTab model.activeTab)
        , div [ classes [ Tw.py s4 ] ] [ viewActiveTab model ]
        , viewRepositoryFiles model project
        ]


{-| The five tabs used to be five near-identical twenty-line button blocks.
Their labels were internal vocabulary; these are what the user is editing.
-}
viewTabs : Model -> Html Msg
viewTabs model =
    div
        [ classes
            [ Tw.flex
            , Tw.gap s6
            , Tw.border_b
            , Tw.border_color (slate s200)
            ]
        ]
        (List.map
            (\( tabId, label ) ->
                let
                    tabUrl =
                        case model.selectedProject of
                            Just p ->
                                Route.toString
                                    (Route.Repo p.pathWithNamespace
                                        (case tabId of
                                            TokenStudio ->
                                                Route.TokensTab

                                            ComponentRegistry ->
                                                Route.ComponentsTab model.selectedComponentName

                                            ScreenComposer ->
                                                Route.ScreensTab model.selectedScreenName

                                            GitWorkflows ->
                                                Route.GitWorkflowsTab

                                            ExportPipeline ->
                                                Route.ExportPipelineTab
                                        )
                                    )

                            Nothing ->
                                "#"
                in
                Ui.tabLink (model.activeTab == tabId) tabUrl label
            )
            [ ( TokenStudio, "Tokens" )
            , ( ComponentRegistry, "Components" )
            , ( ScreenComposer, "Screens" )
            , ( GitWorkflows, "Branches & Reviews" )
            , ( ExportPipeline, "Export" )
            ]
        )


viewActiveTab : Model -> Html Msg
viewActiveTab model =
    case model.activeTab of
        TokenStudio ->
            viewTokenStudio model

        ComponentRegistry ->
            viewComponentRegistry model

        ScreenComposer ->
            viewScreenComposer model

        GitWorkflows ->
            viewGitWorkflows model

        ExportPipeline ->
            viewExportPipeline model


{-| This listing used to sit expanded under every tab, showing raw git mode
bits ("100644 blob tokens/tokens.json"). It is reference material, so it is
collapsed and shows paths only.
-}
viewRepositoryFiles : Model -> Project -> Html Msg
viewRepositoryFiles model project =
    Html.details [ classes [ Tw.mt s4, Tw.text_sm ] ]
        [ Html.summary [ Ui.muted, classes [ Tw.cursor_pointer ] ]
            [ text ("Files on " ++ project.defaultBranch) ]
        , case model.repositoryTree of
            Nothing ->
                div [ Ui.muted, classes [ Tw.mt s2 ] ] [ text "Loading..." ]

            Just tree ->
                if List.isEmpty tree then
                    div [ Ui.muted, classes [ Tw.mt s2 ] ] [ text "This repository is empty." ]

                else
                    ul
                        [ Ui.panelSunken
                        , classes [ Tw.mt s2, Tw.list_none, Tw.font_mono, Tw.text_xs, Tw.text_color (slate s700) ]
                        ]
                        (List.map (\item -> li [ classes [ Tw.py s0_dot_5 ] ] [ text item.path ]) tree)
        ]
