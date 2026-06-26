module Pages.ComponentRegistry exposing (viewComponentRegistry)

import Components
import Html exposing (Html, button, div, h4, h5, li, text, ul)
import Html.Attributes exposing (style, value)
import Html.Events exposing (onClick, onInput)
import Renderer
import Themes
import Types exposing (..)


viewComponentRegistry : Model -> Html Msg
viewComponentRegistry model =
    case model.components of
        Nothing ->
            text "Loading components..."

        Just components ->
            div [ style "display" "flex", style "gap" "2rem" ]
                [ div [ style "flex" "1" ]
                    [ h4 [] [ text "Components" ]
                    , ul [ style "list-style" "none", style "padding" "0" ]
                        (List.map
                            (\c ->
                                li
                                    [ style "padding" "0.5rem"
                                    , style "cursor" "pointer"
                                    , style "border-bottom" "1px solid #eee"
                                    , style "background"
                                        (if model.selectedComponentName == Just c.name then
                                            "#e0f7fa"

                                         else
                                            "transparent"
                                        )
                                    , onClick (SelectComponent (Just c.name))
                                    ]
                                    [ text c.name ]
                            )
                            components
                        )
                    , div [ style "margin-top" "1rem", style "display" "flex", style "gap" "0.5rem" ]
                        [ Html.input
                            [ value model.newComponentName
                            , onInput UpdateNewComponentName
                            , Html.Attributes.placeholder "New Component Name"
                            , style "padding" "0.5rem"
                            , style "width" "150px"
                            ]
                            []
                        , button [ onClick CreateComponent, style "padding" "0.5rem" ] [ text "Create" ]
                        ]
                    ]
                , div [ style "flex" "2" ]
                    [ case model.selectedComponentName of
                        Nothing ->
                            text "Select a component to edit."

                        Just activeName ->
                            let
                                activeComponent =
                                    List.filter (\c -> c.name == activeName) components |> List.head

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
                            in
                            case activeComponent of
                                Just comp ->
                                    div [ style "display" "flex", style "gap" "1rem" ]
                                        [ div [ style "flex" "1", style "background" "#fff", style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px" ]
                                            [ div [ style "display" "flex", style "justify-content" "space-between", style "margin-bottom" "1rem" ]
                                                [ h4 [ style "margin" "0" ] [ text ("Component: " ++ comp.name) ]
                                                , button [ onClick SaveComponent, style "padding" "0.5rem 1rem", style "background" "#28a745", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ] [ text "Save Component" ]
                                                ]
                                            , div [ style "margin-bottom" "1rem" ]
                                                [ h5 [] [ text "Variants" ]
                                                , ul [] (List.map (\v -> li [] [ text v ]) comp.variants)
                                                , div [ style "display" "flex", style "gap" "0.5rem" ]
                                                    [ Html.input [ value model.newComponentVariant, onInput UpdateNewComponentVariant, Html.Attributes.placeholder "New Variant", style "padding" "0.5rem" ] []
                                                    , button [ onClick AddComponentVariant, style "padding" "0.5rem" ] [ text "Add Variant" ]
                                                    ]
                                                ]
                                            , div [ style "margin-bottom" "1rem" ]
                                                [ h5 [] [ text "States" ]
                                                , ul [] (List.map (\s -> li [] [ text s ]) comp.states)
                                                , div [ style "display" "flex", style "gap" "0.5rem" ]
                                                    [ Html.input [ value model.newComponentState, onInput UpdateNewComponentState, Html.Attributes.placeholder "New State", style "padding" "0.5rem" ] []
                                                    , button [ onClick AddComponentState, style "padding" "0.5rem" ] [ text "Add State" ]
                                                    ]
                                                ]
                                            , div [ style "margin-bottom" "1rem" ]
                                                [ h5 [] [ text "Slots" ]
                                                , ul [] (List.map (\s -> li [] [ text s ]) comp.slots)
                                                , div [ style "display" "flex", style "gap" "0.5rem" ]
                                                    [ Html.input [ value model.newComponentSlot, onInput UpdateNewComponentSlot, Html.Attributes.placeholder "New Slot", style "padding" "0.5rem" ] []
                                                    , button [ onClick AddComponentSlot, style "padding" "0.5rem" ] [ text "Add Slot" ]
                                                    ]
                                                ]
                                            , div [ style "margin-bottom" "1rem", style "border-top" "1px solid #eee", style "padding-top" "1rem" ]
                                                [ h5 [] [ text "Visual Layout Editor" ]
                                                , case comp.layout of
                                                    Nothing ->
                                                        button [ onClick InitComponentLayout, style "padding" "0.5rem" ] [ text "Initialize Layout (Stack)" ]

                                                    Just (Components.Stack props _) ->
                                                        div []
                                                            [ div [ style "display" "flex", style "flex-direction" "column", style "gap" "0.5rem", style "margin-bottom" "1rem" ]
                                                                [ Html.input [ value (Maybe.withDefault "" props.padding), onInput UpdateLayoutPadding, Html.Attributes.placeholder "Padding (e.g. spacing.md)", style "padding" "0.5rem" ] []
                                                                , Html.input [ value (Maybe.withDefault "" props.backgroundColor), onInput UpdateLayoutBackgroundColor, Html.Attributes.placeholder "Background (e.g. color.primary)", style "padding" "0.5rem" ] []
                                                                ]
                                                            , div [ style "display" "flex", style "gap" "0.5rem" ]
                                                                [ button [ onClick (AddLayoutText "New Text Node"), style "padding" "0.5rem" ] [ text "Add Text Node" ]
                                                                ]
                                                            ]

                                                    Just _ ->
                                                        text "Advanced layout editing not supported yet."
                                                ]
                                            ]
                                        , div [ style "flex" "1", style "background" "#f9f9f9", style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px", style "display" "flex", style "flex-direction" "column" ]
                                            [ h4 [ style "margin" "0 0 1rem 0" ] [ text "Live Preview" ]
                                            , case comp.layout of
                                                Just l ->
                                                    div [ style "border" "1px dashed #aaa", style "padding" "1rem", style "min-height" "100px", style "background" "#fff" ]
                                                        [ Renderer.render displayTokens l ]

                                                Nothing ->
                                                    text "No layout defined."
                                            ]
                                        ]

                                Nothing ->
                                    text "Component not found."
                    ]
                ]
