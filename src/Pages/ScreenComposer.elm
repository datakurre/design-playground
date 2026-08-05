module Pages.ScreenComposer exposing (viewScreenComposer)

import Dict
import Html exposing (Html, button, div, h4, h5, li, text, ul)
import Html.Attributes exposing (style, value)
import Html.Events exposing (onClick, onInput)
import Renderer
import Themes
import Types exposing (..)


viewScreenComposer : Model -> Html Msg
viewScreenComposer model =
    case model.screens of
        Nothing ->
            text "Loading screens..."

        Just screens ->
            div [ style "display" "flex", style "gap" "2rem" ]
                [ div [ style "flex" "1" ]
                    [ h4 [] [ text "Screens / Layouts" ]
                    , ul [ style "list-style" "none", style "padding" "0" ]
                        (List.map
                            (\s ->
                                li
                                    [ style "padding" "0.5rem"
                                    , style "cursor" "pointer"
                                    , style "border-bottom" "1px solid #eee"
                                    , style "background"
                                        (if model.selectedScreenName == Just s.name then
                                            "#e0f7fa"

                                         else
                                            "transparent"
                                        )
                                    , onClick (SelectScreen (Just s.name))
                                    ]
                                    [ text s.name ]
                            )
                            screens
                        )
                    , div [ style "margin-top" "1rem", style "display" "flex", style "gap" "0.5rem" ]
                        [ Html.input
                            [ value model.newScreenName
                            , onInput UpdateNewScreenName
                            , Html.Attributes.placeholder "New Screen Name"
                            , style "padding" "0.5rem"
                            , style "width" "150px"
                            ]
                            []
                        , button [ onClick CreateScreen, style "padding" "0.5rem" ] [ text "Create" ]
                        ]
                    ]
                , div [ style "flex" "2" ]
                    [ case model.selectedScreenName of
                        Nothing ->
                            text "Select a screen to edit."

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
                            in
                            case activeScreen of
                                Just screen ->
                                    div [ style "display" "flex", style "gap" "1rem", style "flex-direction" "column" ]
                                        [ div [ style "background" "#fff", style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px" ]
                                            [ div [ style "display" "flex", style "justify-content" "space-between", style "margin-bottom" "1rem" ]
                                                [ h4 [ style "margin" "0" ] [ text ("Screen: " ++ screen.name ++ " (" ++ screen.path ++ ")") ]
                                                , div [ style "display" "flex", style "gap" "0.5rem" ]
                                                    [ button [ onClick SaveScreen, style "padding" "0.5rem 1rem", style "background" "#28a745", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ] [ text "Save Screen" ]
                                                    , button [ onClick (DeleteScreen screen.name), style "padding" "0.5rem 1rem", style "background" "#dc3545", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ] [ text "Delete Screen" ]
                                                    ]
                                                ]
                                            , div [ style "margin-bottom" "1rem", style "border-top" "1px solid #eee", style "padding-top" "1rem" ]
                                                [ h5 [] [ text "Insert Component into Root" ]
                                                , ul [ style "list-style" "none", style "padding" "0", style "display" "flex", style "flex-wrap" "wrap", style "gap" "0.5rem" ]
                                                    (List.map
                                                        (\c ->
                                                            li []
                                                                [ button [ onClick (AddComponentToScreen c.name), style "padding" "0.5rem" ] [ text ("+ " ++ c.name) ]
                                                                ]
                                                        )
                                                        (model.components |> Maybe.withDefault [])
                                                    )
                                                ]
                                            ]
                                        , div [ style "background" "#f9f9f9", style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px" ]
                                            [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "center", style "margin-bottom" "1rem" ]
                                                [ h4 [ style "margin" "0" ] [ text "Live Screen Preview" ]
                                                , Html.select
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
                                                ]
                                            , div [ style "border" "1px dashed #aaa", style "padding" "1rem", style "min-height" "200px", style "background" "#fff" ]
                                                [ Renderer.renderScreenNode componentsDict displayTokens screen.root ]
                                            ]
                                        ]

                                Nothing ->
                                    text "Screen not found."
                    ]
                ]
