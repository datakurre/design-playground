module Pages.ScreenComposer exposing (viewScreenComposer)

import Components
import Dict
import Html exposing (Html, button, div, h3, h4, li, text, ul)
import Html.Attributes exposing (value)
import Html.Events exposing (onClick, onInput)
import Renderer
import Screens exposing (Screen)
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (hover)
import Tailwind.Theme exposing (s0, s100, s2, s24, s3, s4, s48, s50, s6, s64, s700, s900, slate)
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
                        [ button
                            [ onClick (SelectScreen (Just s.name))
                            , classes
                                [ Tw.w_full
                                , Tw.text_left
                                , Tw.px s2
                                , Tw.py s2
                                , Tw.text_sm
                                , Tw.border_none
                                , Tw.rounded_md
                                , Tw.cursor_pointer
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
                [ Ui.textInput
                , value model.newScreenName
                , onInput UpdateNewScreenName
                , Html.Attributes.placeholder "New screen"
                , Html.Attributes.attribute "aria-label" "New screen name"
                , classes [ Tw.flex_1, Tw.min_w s24 ]
                ]
                []
            , button [ Ui.btnNeutral, onClick CreateScreen ] [ text "Add" ]
            ]
        ]


viewSelectedScreen : Model -> List Screen -> Html Msg
viewSelectedScreen model screens =
    case model.selectedScreenName of
        Nothing ->
            div [ Ui.panel, Ui.muted, classes [ Tw.text_center, Tw.py s6 ] ]
                [ text "Pick a screen to edit it." ]

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
                        [ viewScreenEditor model screen screens
                        , viewScreenPreview model screen componentsDict screensDict displayTokens
                        ]

                Nothing ->
                    div [ Ui.panel, Ui.muted ] [ text "That screen no longer exists." ]


viewScreenEditor : Model -> Screen -> List Screen -> Html Msg
viewScreenEditor model screen screens =
    div [ Ui.panel ]
        [ div [ classes [ Tw.flex, Tw.justify_between, Tw.items_start, Tw.gap s2, Tw.mb s3, Tw.flex_wrap ] ]
            [ div []
                [ h3 [ Ui.pageTitle ] [ text screen.name ]
                , div [ Ui.mutedSmall, classes [ Tw.font_mono ] ] [ text screen.path ]
                ]
            , div [ classes [ Tw.flex, Tw.gap s2 ] ]
                [ button [ Ui.btnPrimary, onClick SaveScreen ] [ text "Save" ]
                , button [ Ui.btnDanger, onClick (DeleteScreen screen.name) ] [ text "Delete" ]
                ]
            ]
        , viewAdders "Add a component"
            (model.components |> Maybe.withDefault [] |> List.map .name)
            AddComponentToScreen
            "No components yet — create one on the Components tab."
        , viewAdders "Add another screen"
            (screens |> List.filter (\s -> s.name /= screen.name) |> List.map .name)
            AddScreenToScreen
            "This is your only screen so far."
        ]


{-| Both adders append to the top level of the screen. The old labels said
"Insert Component into Root", which named an implementation detail of the tree.
-}
viewAdders : String -> List String -> (String -> Msg) -> String -> Html Msg
viewAdders label names toMsg emptyHint =
    div [ classes [ Tw.mt s3, Tw.pt s3 ], Ui.divider ]
        [ h4 [ Ui.sectionTitle, classes [ Tw.mb s2 ] ] [ text label ]
        , if List.isEmpty names then
            div [ Ui.mutedSmall ] [ text emptyHint ]

          else
            div [ classes [ Tw.flex, Tw.flex_wrap, Tw.gap s2 ] ]
                (List.map
                    (\name -> button [ Ui.btnSmall, onClick (toMsg name) ] [ text ("+ " ++ name) ])
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
