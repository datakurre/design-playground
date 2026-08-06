module Pages.ComponentRegistry exposing (viewComponentRegistry)

import Components
import CssProperties
import Dict
import Html exposing (Html, button, div, h4, h5, h6, li, text, ul)
import Html.Attributes exposing (style, value)
import Html.Events exposing (onClick, onInput)
import Renderer
import Themes
import Types exposing (..)


viewLayoutEditorNode : Model -> List Int -> Components.Layout -> Html Msg
viewLayoutEditorNode model path layout =
    let
        (nodeType, styles, childrenNodes) =
            case layout of
                Components.Stack props children ->
                    ("Stack", props.styles, children)
                Components.Grid props children ->
                    ("Grid", props.styles, children)
                Components.Element props content ->
                    ("Element (" ++ content ++ ")", props.styles, [])
    in
    div [ style "margin-bottom" "1rem", style "border" "1px solid #ddd", style "padding" "0.5rem", style "border-radius" "4px" ]
        [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "center", style "margin-bottom" "0.5rem", style "background" "#f0f0f0", style "padding" "0.2rem 0.5rem" ]
            [ Html.strong [] [ text nodeType ]
            , button [ onClick (DeleteLayoutNode path), style "padding" "0.2rem 0.5rem", style "background" "#ffdddd", style "border" "none", style "cursor" "pointer" ] [ text "Delete Node" ]
            ]
        , div [ style "margin-bottom" "0.5rem", style "padding-left" "1rem" ]
            [ h6 [ style "margin" "0 0 0.5rem 0" ] [ text "Styles" ]
            , ul [ style "list-style" "none", style "padding" "0", style "margin" "0 0 0.5rem 0" ]
                (List.map (\(key, val) -> 
                    li [ style "display" "flex", style "gap" "0.5rem", style "margin-bottom" "0.2rem" ] 
                        [ text (key ++ ": ")
                        , Html.input [ value val, onInput (UpdateLayoutProperty path key), style "padding" "0.2rem", style "flex" "1", Html.Attributes.attribute "list" "tokensList" ] []
                        , button [ onClick (RemoveLayoutProperty path key), style "padding" "0.2rem", style "background" "#ffdddd", style "border" "none" ] [ text "X" ] 
                        ]
                ) (Dict.toList styles))
            , div [ style "display" "flex", style "gap" "0.5rem", style "align-items" "center" ]
                [ Html.input [ value model.newLayoutPropertyName, onInput UpdateNewLayoutPropertyName, Html.Attributes.placeholder "CSS Property", style "padding" "0.2rem", style "width" "100px", Html.Attributes.attribute "list" "css-properties-list" ] []
                , Html.input [ value model.newLayoutPropertyValue, onInput UpdateNewLayoutPropertyValue, Html.Attributes.placeholder "Token", style "padding" "0.2rem", style "flex" "1", Html.Attributes.attribute "list" "tokensList" ] []
                , button [ onClick (UpdateLayoutProperty path model.newLayoutPropertyName model.newLayoutPropertyValue), style "padding" "0.2rem" ] [ text "Add Style" ]
                ]
            ]
        , case layout of
            Components.Element _ content ->
                div [ style "padding-left" "1rem" ]
                    [ h6 [ style "margin" "0 0 0.5rem 0" ] [ text "Content" ]
                    , Html.input 
                        [ value content
                        , onInput (UpdateLayoutText path)
                        , style "padding" "0.2rem"
                        , style "width" "100%" 
                        ] []
                    ]
            _ ->
                div [ style "padding-left" "1rem", style "border-left" "2px solid #eee" ]
                    [ h6 [ style "margin" "0 0 0.5rem 0" ] [ text "Children" ]
                    , div []
                        (List.indexedMap (\i child -> viewLayoutEditorNode model (path ++ [i]) child) childrenNodes)
                    , div [ style "display" "flex", style "gap" "0.5rem", style "margin-top" "0.5rem" ]
                        [ button [ onClick (AddLayoutStack path), style "padding" "0.2rem" ] [ text "+ Stack" ]
                        , button [ onClick (AddLayoutGrid path), style "padding" "0.2rem" ] [ text "+ Grid" ]
                        , button [ onClick (AddLayoutText path "New Text"), style "padding" "0.2rem" ] [ text "+ Text" ]
                        ]
                    ]
        ]


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
                        , Html.select
                            [ Html.Events.onInput UpdateNewComponentTemplate
                            , value model.newComponentTemplate
                            , style "padding" "0.5rem"
                            ]
                            [ Html.option [ value "Empty" ] [ text "Empty" ]
                            , Html.option [ value "Button" ] [ text "Button" ]
                            , Html.option [ value "Card" ] [ text "Card" ]
                            ]
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
                                                , div [ style "display" "flex", style "gap" "0.5rem" ]
                                                    [ button [ onClick SaveComponent, style "padding" "0.5rem 1rem", style "background" "#28a745", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ] [ text "Save Component" ]
                                                    , button [ onClick (DeleteComponent comp.name), style "padding" "0.5rem 1rem", style "background" "#dc3545", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ] [ text "Delete Component" ]
                                                    ]
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
                                                , Html.datalist [ Html.Attributes.id "tokensList" ]
                                                    (List.map (\( p, _ ) -> Html.option [ value ("{" ++ String.join "." p ++ "}") ] []) displayTokens)
                                                , Html.datalist [ Html.Attributes.id "css-properties-list" ]
                                                    (List.map (\prop -> Html.option [ value prop ] []) CssProperties.allProperties)
                                                , case comp.layout of
                                                    Nothing ->
                                                        button [ onClick InitComponentLayout, style "padding" "0.5rem" ] [ text "Initialize Layout (Stack)" ]

                                                    Just layoutRoot ->
                                                        viewLayoutEditorNode model [] layoutRoot
                                                ]
                                            ]
                                        , div [ style "flex" "1", style "background" "#f9f9f9", style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px", style "display" "flex", style "flex-direction" "column" ]
                                            [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "center", style "margin-bottom" "1rem" ]
                                                [ h4 [ style "margin" "0" ] [ text "Live Preview" ]
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
