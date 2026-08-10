module Pages.ScreenComposer exposing (viewScreenComposer)

import Components
import Dict
import Guard
import Help
import Html exposing (Html, div, h3, h4, li, text, ul)
import Html.Attributes exposing (value)
import Html.Events exposing (onInput)
import Renderer
import Route
import Screens exposing (Screen)
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (hover)
import Tailwind.Theme exposing (red, s0, s0_dot_5, s100, s2, s200, s24, s3, s4, s48, s50, s6, s600, s64, s700, s900, slate)
import Templates
import Themes
import Tokens
import Types exposing (..)
import Ui


viewScreenComposer : Model -> Html Msg
viewScreenComposer model =
    case model.screens of
        Nothing ->
            div [ Ui.muted ] [ text "Loading screens..." ]

        Just screens ->
            div [ classes [ Tw.flex, Tw.gap s4, Tw.items_start ] ]
                [ viewScreenList model screens
                , div [ classes [ Tw.flex_1 ] ] [ viewSelectedScreen model screens ]
                ]


viewScreenList : Model -> List Screen -> Html Msg
viewScreenList model screens =
    div [ Ui.panel, classes [ Tw.w s64 ] ]
        [ h3 [ Ui.pageTitle, classes [ Tw.mb s2 ] ] [ text "Screens" ]
        , ul [ classes [ Tw.list_none, Tw.p s0 ] ]
            (List.map
                (\s ->
                    li []
                        [ Html.a
                            [ Html.Attributes.href
                                (case model.selectedProject of
                                    Just p ->
                                        Route.toString (Route.forProject p model.currentBranch (Route.ScreensTab (Just s.name)))

                                    Nothing ->
                                        "#"
                                )
                            , classes
                                [ Tw.w_full
                                , Tw.block
                                , Tw.text_left
                                , Tw.px s2
                                , Tw.py s2
                                , Tw.text_sm
                                , Tw.border_none
                                , Tw.rounded_md
                                , Tw.cursor_pointer
                                , Tw.no_underline
                                , if model.selectedScreenName == Just s.name then
                                    Tw.batch
                                        [ Tw.bg_color (slate s100)
                                        , Tw.font_medium
                                        , Tw.text_color (slate s900)
                                        ]

                                  else
                                    Tw.batch
                                        [ Tw.raw "bg-transparent"
                                        , Tw.text_color (slate s700)
                                        , hover [ Tw.bg_color (slate s50) ]
                                        ]
                                ]
                            ]
                            [ text s.name ]
                        ]
                )
                screens
            )
        , div [ classes [ Tw.mt s3, Tw.pt s3, Tw.flex, Tw.gap s2 ], Ui.divider ]
            [ Html.input
                [ if Guard.writable model then
                    Ui.textInput

                  else
                    Ui.textInputReadOnly
                , Html.Attributes.readonly (not (Guard.writable model))
                , value model.newScreenName
                , onInput UpdateNewScreenName
                , Html.Attributes.placeholder "New screen"
                , Html.Attributes.attribute "aria-label" "New screen name"
                , classes [ Tw.flex_1, Tw.min_w s24 ]
                ]
                []
            , Html.select
                [ Ui.selectInput
                , Html.Attributes.disabled (not (Guard.writable model))
                , onInput UpdateNewScreenTemplate
                , value model.newScreenTemplate
                , Html.Attributes.attribute "aria-label" "Start from"
                ]
                (List.map (\t -> Html.option [ value t.id ] [ text t.label ]) Templates.screenTemplates)
            , Ui.actionButton Ui.btnNeutral (Guard.action model CreateScreen) [ text "Add" ]
            ]
        ]


viewSelectedScreen : Model -> List Screen -> Html Msg
viewSelectedScreen model screens =
    case model.selectedScreenName of
        Nothing ->
            div [ Ui.panel, Ui.muted, classes [ Tw.text_center, Tw.py s6 ] ]
                [ text
                    (if List.isEmpty screens then
                        "No screens yet. Name one on the left and pick a starting shape — Login, Dashboard or Landing."

                     else
                        "Pick a screen to edit it."
                    )
                ]

        Just activeName ->
            let
                activeScreen =
                    List.filter (\s -> s.name == activeName) screens |> List.head

                baseTokens =
                    model.tokens |> Maybe.withDefault []

                displayTokens =
                    case model.activeThemeName of
                        Nothing ->
                            baseTokens

                        Just activeThemeNameStr ->
                            let
                                activeTheme =
                                    List.filter (\t -> t.name == activeThemeNameStr) model.themes |> List.head
                            in
                            case activeTheme of
                                Just theme ->
                                    Themes.applyTheme baseTokens theme

                                Nothing ->
                                    baseTokens

                componentsDict =
                    model.components
                        |> Maybe.withDefault []
                        |> List.map (\c -> ( c.name, c ))
                        |> Dict.fromList

                screensDict =
                    screens
                        |> List.map (\s -> ( s.name, s ))
                        |> Dict.fromList
            in
            case activeScreen of
                Just screen ->
                    div [ classes [ Tw.flex, Tw.flex_col, Tw.gap s4 ] ]
                        [ viewScreenEditor model screen screens screensDict
                        , viewScreenPreview model screen componentsDict screensDict displayTokens
                        ]

                Nothing ->
                    div [ Ui.panel, Ui.muted ] [ text "That screen no longer exists." ]


viewScreenEditor : Model -> Screen -> List Screen -> Dict.Dict String Screen -> Html Msg
viewScreenEditor model screen screens screensDict =
    div [ Ui.panel ]
        [ div [ classes [ Tw.flex, Tw.justify_between, Tw.items_start, Tw.gap s2, Tw.mb s3, Tw.flex_wrap ] ]
            [ div []
                [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2 ] ]
                    [ h3 [ Ui.pageTitle ] [ text screen.name ]
                    , Ui.contextHelp Help.screenEditor
                    ]
                , div [ Ui.mutedSmall, classes [ Tw.font_mono ] ] [ text screen.path ]
                ]
            , div [ classes [ Tw.flex, Tw.gap s2 ] ]
                [ Ui.actionButton Ui.btnPrimary (Guard.action model SaveScreen) [ text "Save" ]
                , Ui.actionButton Ui.btnDanger (Guard.action model (DeleteScreen screen.name)) [ text "Delete" ]
                ]
            ]
        , div [ classes [ Tw.mb s3 ] ]
            [ h4 [ Ui.sectionTitle, classes [ Tw.mb s2 ] ] [ text "Contents" ]
            , case screen.root of
                Screens.Container _ [] ->
                    div [ Ui.mutedSmall ] [ text "Nothing added yet." ]

                Screens.Container _ children ->
                    ul [ classes [ Tw.list_none, Tw.p s0, Tw.m s0 ] ]
                        (List.indexedMap (viewAddedNode (Guard.writable model) screensDict screen.name) children)

                _ ->
                    div [ Ui.mutedSmall ] [ text "Invalid root node." ]
            ]
        , viewAdders (Guard.writable model)
            "Add a component"
            Help.addComponentToScreen
            (model.components |> Maybe.withDefault [] |> List.map .name)
            AddComponentToScreen
            "No components yet — create one on the Components tab."
        , viewAdders (Guard.writable model)
            "Add another screen"
            Help.addScreenToScreen
            (screens |> List.filter (\s -> s.name /= screen.name) |> List.map .name)
            AddScreenToScreen
            "This is your only screen so far."
        ]


viewAddedNode : Bool -> Dict.Dict String Screen -> String -> Int -> Screens.ScreenNode -> Html Msg
viewAddedNode writable screensDict parentName index node =
    let
        ( nodeName, nodeType ) =
            case node of
                Screens.ComponentInstance props ->
                    ( props.componentName, "Component" )

                Screens.ScreenInstance props ->
                    ( props.screenName, "Screen" )

                Screens.Container _ _ ->
                    ( "Group", "Group" )

                Screens.TextNode content ->
                    ( content, "Text" )
    in
    li [ classes [ Tw.flex, Tw.justify_between, Tw.items_center, Tw.p s2, Tw.border_b, Tw.border_color (slate s200) ] ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2 ] ]
            [ div [ classes [ Tw.font_medium ] ] [ text nodeName ]
            , div [ Ui.mutedSmall, classes [ Tw.px s2, Tw.py s0_dot_5, Tw.bg_color (slate s100), Tw.rounded_full ] ] [ text nodeType ]
            , if Screens.formsCycle screensDict [ parentName ] node then
                div
                    [ classes
                        [ Tw.text_color (red s600)
                        , Tw.text_xs
                        , Tw.font_medium
                        , Tw.bg_color (red s50)
                        , Tw.px s2
                        , Tw.py s0_dot_5
                        , Tw.border
                        , Tw.border_color (red s200)
                        , Tw.rounded_md
                        ]
                    ]
                    [ text "Loop detected" ]

              else
                text ""
            ]
        , Ui.actionButton Ui.btnDanger
            (if writable then
                Ui.Do (RemoveScreenNode index)

             else
                Ui.Blocked "Create a branch before removing from this screen"
            )
            [ text "Remove" ]
        ]


{-| Both adders append to the top level of the screen. The old labels said
"Insert Component into Root", which named an implementation detail of the tree.
-}
viewAdders : Bool -> String -> Help.Topic -> List String -> (String -> Msg) -> String -> Html Msg
viewAdders writable label topic names toMsg emptyHint =
    div [ classes [ Tw.mt s3, Tw.pt s3 ], Ui.divider ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
            [ h4 [ Ui.sectionTitle ] [ text label ]
            , Ui.contextHelp topic
            ]
        , if List.isEmpty names then
            div [ Ui.mutedSmall ] [ text emptyHint ]

          else
            div [ classes [ Tw.flex, Tw.flex_wrap, Tw.gap s2 ] ]
                (List.map
                    (\name ->
                        Ui.actionButton Ui.btnSmall
                            (if writable then
                                Ui.Do (toMsg name)

                             else
                                Ui.Blocked "Create a branch before adding to this screen"
                            )
                            [ text ("+ " ++ name) ]
                    )
                    names
                )
        ]


viewScreenPreview : Model -> Screen -> Dict.Dict String Components.Component -> Dict.Dict String Screen -> List Tokens.FlatToken -> Html Msg
viewScreenPreview model screen componentsDict screensDict displayTokens =
    div [ Ui.panelSunken ]
        [ div [ classes [ Tw.flex, Tw.justify_between, Tw.items_center, Tw.gap s2, Tw.mb s3 ] ]
            [ h3 [ Ui.sectionTitle ] [ text "Preview" ]
            , Ui.themePicker (List.map .name model.themes) model.activeThemeName SelectTheme
            ]
        , div [ Ui.previewSurface, classes [ Tw.min_h s48 ] ]
            [ Renderer.renderScreenNode componentsDict screensDict [ screen.name ] displayTokens screen.root ]
        ]
