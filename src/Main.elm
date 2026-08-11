module Main exposing (main)

import Auth
import Browser
import Browser.Navigation as Nav
import Effect
import GitLab.Projects exposing (Project)
import Guard
import Help
import Html exposing (Html, a, button, div, h2, img, input, li, span, text, ul)
import Html.Attributes exposing (href, src)
import Html.Events exposing (onClick, onInput)
import Pages.ComponentRegistry exposing (viewComponentRegistry)
import Pages.ExportPipeline exposing (viewExportPipeline)
import Pages.GitWorkflows exposing (viewGitWorkflows)
import Pages.ScreenComposer exposing (viewScreenComposer)
import Pages.TokenStudio exposing (viewTokenStudio)
import Ports
import Route
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (hover)
import Tailwind.Theme exposing (s0, s0_dot_5, s1, s14, s2, s200, s3, s4, s50, s6, s700, s8, s900, slate, white)
import Types exposing (..)
import Ui
import Update exposing (update)
import Url exposing (Url)



-- MAIN


{-| The `Nav.Key` lives here rather than in `Types.Model`, and this wrapper is
what makes that possible.

A key cannot be constructed outside a running `Browser.application`, so while it
was a field of the `Model`, `Types.initial` could not be called from a test —
and neither could anything taking a `Model`, which is to say the whole of
`Update`. Holding it out here costs one indirection and buys back every state
transition in the app as something a test can run.

`Browser.application` fixes `update : msg -> model -> ( model, Cmd msg )`, so
there is nowhere else to put it: `main` is a value, and the update function is
built before `init` ever runs, so there is no scope in which the key exists and
`update` is in scope.

-}
type alias AppModel =
    { key : Nav.Key
    , app : Model
    }


main : Program Flags AppModel Msg
main =
    Browser.application
        { init = init
        , view = \model -> view model.app
        , update = updateWithEffects
        , subscriptions = \model -> subscriptions model.app
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- MODEL


init : Flags -> Url -> Nav.Key -> ( AppModel, Cmd Msg )
init flags url key =
    let
        -- The authorization code from the callback, but only if the `state`
        -- that came back with it is the one this session sent.
        urlCode =
            Auth.parseCallback flags.authConfig url

        initialModel =
            Types.initial url flags

        effects =
            case urlCode of
                Just code ->
                    [ Auth.exchangeToken flags.authConfig code flags.pkceVerifier GotTokenResult |> Effect.SendRequest ]

                Nothing ->
                    case flags.token of
                        Just t ->
                            [ Auth.fetchProfile t GotProfile |> Effect.SendRequest ]

                        Nothing ->
                            []

        -- `UrlChanged` only fires on later navigation, so without this a deep
        -- link or a refresh would land on an empty Tokens tab no matter what
        -- the URL said. The token comes from flags, so the repository can start
        -- loading right away.
        modelWithStatus =
            if urlCode == Nothing && flags.token == Nothing then
                { initialModel | startupStatus = Ready }

            else
                initialModel

        ( routedModel, routeEffect ) =
            case Route.parse url of
                Just route ->
                    Update.applyRoute route modelWithStatus

                Nothing ->
                    ( modelWithStatus, Effect.none )
    in
    ( { key = key, app = routedModel }
    , Effect.perform key (Effect.batch (routeEffect :: effects))
    )


{-| The one place an `Effect` becomes a `Cmd`. `Update.update` deals in effects
as data so that a test can read them; this is where they are actually run.
-}
updateWithEffects : Msg -> AppModel -> ( AppModel, Cmd Msg )
updateWithEffects msg model =
    let
        ( updated, effect ) =
            update msg model.app
    in
    ( { model | app = updated }, Effect.perform model.key effect )



-- UPDATE
-- SUBSCRIPTIONS


{-| Every save goes out as `Effect.ValidateSchema` and waits for the result
before it commits, so without this subscription nothing can be saved at all: the
status pill sticks on "Validating..." and the pending commit is never issued.
-}
subscriptions : Model -> Sub Msg
subscriptions _ =
    Ports.schemaValidationResult GotSchemaValidationResult



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Design Playground"
    , body =
        [ div
            [ classes [ Tw.min_h_screen, Tw.bg_color (slate s50), Tw.text_color (slate s900) ]

            -- scripts/smoke.sh looks for this attribute to decide whether the
            -- app booted. It is here rather than a class or a piece of copy
            -- because both of those churn and this does not.
            , Html.Attributes.attribute "data-smoke" "app"
            ]
            [ viewAppBar model
            , div [ Ui.page ]
                [ viewError model
                , viewLoadErrors model
                , viewReadOnlyBanner model
                , case model.startupStatus of
                    Booting ->
                        div [ classes [ Tw.py s14, Tw.flex, Tw.justify_center ] ]
                            [ Ui.throbber ]

                    Ready ->
                        viewWorkspace model
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


{-| Repository, branch, and whether you can edit here.

The branch belongs in the bar rather than only on the Branches tab because it
now decides whether the rest of the app is editable at all. Somewhere in the
chrome has to answer "why is this greyed out" without navigating away from the
thing that is greyed out.

Creating a branch is not here — it needs a text field, the bar has no room for
one, and the read-only banner is where someone is standing when they find out
they need it.

-}
viewRepoBadge : Model -> Html Msg
viewRepoBadge model =
    case model.selectedProject of
        Just project ->
            div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2 ] ]
                [ span [ classes [ Tw.text_sm, Tw.font_medium ] ] [ text project.pathWithNamespace ]
                , case model.branches of
                    Just branches ->
                        Ui.branchPicker
                            { label = "Branch", current = model.currentBranch, onSwitch = SwitchBranch }
                            branches

                    Nothing ->
                        text ""
                , case Guard.readOnly model of
                    Just _ ->
                        Ui.pill Ui.Neutral "read-only"

                    Nothing ->
                        text ""
                , button [ Ui.btnNeutral, onClick UnselectProject ] [ text "Change" ]
                ]

        Nothing ->
            text ""


{-| Why the editors are inert, and the way out, in the same box.

It sits above every tab rather than on the Branches tab, because the moment a
user needs it is the moment they tried to type somewhere else. The form is the
same `newBranchName` / `CreateBranch` pair the Branches tab uses, so there is no
new state and the two cannot disagree.

-}
viewReadOnlyBanner : Model -> Html Msg
viewReadOnlyBanner model =
    case ( model.selectedProject, Guard.readOnly model ) of
        ( Just _, Just reason ) ->
            Ui.notice Ui.Neutral
                [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.raw "flex-wrap" ] ]
                    [ span [] [ text (Guard.describe reason) ]
                    , Ui.contextHelp Help.readOnlyBranch
                    ]
                , div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mt s2, Tw.raw "flex-wrap" ] ]
                    [ input
                        [ Ui.textInput
                        , Html.Attributes.placeholder "New branch, e.g. feature/new-colors"
                        , Html.Attributes.attribute "aria-label" "New branch name"
                        , Html.Attributes.spellcheck False
                        , Html.Attributes.value model.newBranchName
                        , onInput UpdateNewBranchName
                        ]
                        []
                    , button [ Ui.btnPrimary, onClick CreateBranch ] [ text "Create branch" ]
                    ]
                ]

        _ ->
            text ""


viewAccount : Model -> Html Msg
viewAccount model =
    case model.token of
        Nothing ->
            a [ Ui.btnBrand, href (Auth.loginUrl model.authConfig model.pkceChallenge) ] [ text "Connect to GitLab" ]

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
            Ui.notice Ui.Negative [ text err ]

        Nothing ->
            text ""


{-| Files in the repository that the app read but could not use.

These used to be discarded silently, which made a malformed component
indistinguishable from a component that isn't there — and left the app willing
to `create` a file that already existed. It is deliberately a banner rather than
something on the affected tab: the file that failed to load is by definition not
in the list you would go looking for it in.

-}
viewLoadErrors : Model -> Html Msg
viewLoadErrors model =
    if List.isEmpty model.loadErrors then
        text ""

    else
        Ui.notice Ui.Negative
            [ div [ classes [ Tw.flex, Tw.items_center, Tw.justify_between, Tw.gap s2, Tw.mb s2 ] ]
                [ Html.strong []
                    [ text
                        (case model.loadErrors of
                            [ _ ] ->
                                "One file in this branch couldn't be read"

                            errors ->
                                String.fromInt (List.length errors) ++ " files in this branch couldn't be read"
                        )
                    ]
                , button [ Ui.btnNeutral, onClick DismissLoadErrors ] [ text "Dismiss" ]
                ]
            , Html.ul []
                (List.map
                    (\e ->
                        Html.li [ classes [ Tw.mb s1 ] ]
                            [ Html.code [] [ text e.path ]
                            , text (" — " ++ firstLine e.reason)
                            ]
                    )
                    (List.sortBy .path model.loadErrors)
                )
            ]


{-| A `Json.Decode` error runs to many lines and its first one says what went
wrong; the rest is the value it was looking at. The banner has room for the
first.
-}
firstLine : String -> String
firstLine reason =
    reason
        |> String.lines
        |> List.filter (not << String.isEmpty << String.trim)
        |> List.head
        |> Maybe.withDefault reason


{-| Signed out, there is nothing to show but the sign-in button in the bar.
Signed in without a repository, the user picks one. After that, the editor.
-}
viewWorkspace : Model -> Html Msg
viewWorkspace model =
    case ( model.token, model.user ) of
        ( Just _, Just _ ) ->
            case model.selectedProject of
                Just project ->
                    viewEditor model project

                Nothing ->
                    case model.projects of
                        Nothing ->
                            div [ classes [ Tw.text_center, Tw.py s8 ] ]
                                [ div [ Ui.muted, classes [ Tw.mb s3 ] ]
                                    [ text "Your design tokens, components and screens live in a GitLab repository." ]
                                , button [ Ui.btnPrimary, onClick FetchProjects ] [ text "Choose a repository" ]
                                , viewOrderOfOperations
                                ]

                        Just projects ->
                            viewProjectPicker model.projectSearch projects

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
the tabs go in, and that editing anything at all requires a branch of your own.
Neither fits in a tab's one-line lede.
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
            [ text "There's no backend and no draft state: every save is a commit. So the default branch is read-only here, and so is any protected one — you open a repository to read it. Create a branch first and the editors come alive; everything you then save is a commit on that branch, ready to open as a merge request from "
            , span [ classes [ Tw.font_medium ] ] [ text "Branches & Reviews" ]
            , text "."
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
                            [ href (Route.toString (Route.Repo { path = p.pathWithNamespace, branch = Nothing, tab = Route.TokensTab }))
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
                                -- Carrying the branch matters here more than
                                -- anywhere: without it every tab click would
                                -- navigate you off your branch and back onto
                                -- the read-only default one.
                                Route.toString
                                    (Route.forProject p
                                        model.currentBranch
                                        (Route.tabRouteFor tabId model.selectedComponentName model.selectedScreenName)
                                    )

                            Nothing ->
                                Route.toString Route.Home
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
            -- The branch you are on, not the project's default one: this
            -- listing is fetched at the current ref, and labelling it "main"
            -- after a switch described the wrong branch's files.
            [ text ("Files on " ++ Maybe.withDefault project.defaultBranch model.currentBranch) ]
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
