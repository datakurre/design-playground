module Renderer exposing (render, renderScreenNode)

import Components exposing (Component, Layout(..))
import Dict exposing (Dict)
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (style)
import Screens exposing (ScreenNode(..))
import Tokens exposing (FlatToken)


resolveToken : String -> List FlatToken -> String
resolveToken path tokens =
    let
        parsedPath =
            String.split "." path |> List.map String.trim |> List.filter (\s -> s /= "")

        tokenValue =
            List.filter (\( p, _ ) -> p == parsedPath) tokens
                |> List.head
                |> Maybe.map (\( _, t ) -> Tokens.resolveAlias tokens t.value)
    in
    case tokenValue of
        Just v ->
            v

        Nothing ->
            path -- fallback to raw value if token not found (could be a valid css value like "16px")


renderScreenNode : Dict String Component -> List FlatToken -> ScreenNode -> Html msg
renderScreenNode components tokens node =
    case node of
        ComponentInstance props ->
            case Dict.get props.componentName components of
                Just comp ->
                    case comp.layout of
                        Just layout ->
                            let
                                slotDict =
                                    Dict.fromList props.slots
                            in
                            renderLayoutWithSlots components tokens slotDict layout

                        Nothing ->
                            div [ style "color" "red", style "border" "1px solid red", style "padding" "0.5rem" ]
                                [ text ("Component " ++ props.componentName ++ " has no layout defined.") ]

                Nothing ->
                    div [ style "color" "red", style "border" "1px solid red", style "padding" "0.5rem" ]
                        [ text ("Component not found: " ++ props.componentName) ]

        Container props children ->
            div
                [ style "display" "flex"
                , style "flex-direction" props.direction
                , style "padding" (Maybe.withDefault "0" (Maybe.map (\p -> resolveToken p tokens) props.padding))
                , style "gap" (Maybe.withDefault "0" (Maybe.map (\g -> resolveToken g tokens) props.gap))
                ]
                (List.map (renderScreenNode components tokens) children)

        TextNode content ->
            text content


renderLayoutWithSlots : Dict String Component -> List FlatToken -> Dict String (List ScreenNode) -> Layout -> Html msg
renderLayoutWithSlots components tokens slots layout =
    case layout of
        Stack props children ->
            div
                [ style "display" "flex"
                , style "flex-direction" props.direction
                , style "padding" (Maybe.withDefault "0" (Maybe.map (\p -> resolveToken p tokens) props.padding))
                , style "gap" (Maybe.withDefault "0" (Maybe.map (\g -> resolveToken g tokens) props.gap))
                , style "background-color" (Maybe.withDefault "transparent" (Maybe.map (\bg -> resolveToken bg tokens) props.backgroundColor))
                ]
                (List.map (renderLayoutWithSlots components tokens slots) children)

        Grid props children ->
            div
                [ style "display" "grid"
                , style "grid-template-columns" ("repeat(" ++ String.fromInt props.columns ++ ", 1fr)")
                , style "gap" (Maybe.withDefault "0" (Maybe.map (\g -> resolveToken g tokens) props.gap))
                , style "background-color" (Maybe.withDefault "transparent" (Maybe.map (\bg -> resolveToken bg tokens) props.backgroundColor))
                ]
                (List.map (renderLayoutWithSlots components tokens slots) children)

        Element props content ->
            if props.isSlot then
                case Dict.get content slots of
                    Just slotChildren ->
                        div
                            [ style "display" "contents" ]
                            (List.map (renderScreenNode components tokens) slotChildren)

                    Nothing ->
                        div
                            [ style "border" "1px dashed #ccc"
                            , style "padding" "0.5rem"
                            , style "color" (Maybe.withDefault "inherit" (Maybe.map (\c -> resolveToken c tokens) props.color))
                            , style "font-family" (Maybe.withDefault "inherit" (Maybe.map (\t -> resolveToken t tokens) props.typography))
                            ]
                            [ text ("{ " ++ content ++ " }") ]
            else
                span
                    [ style "color" (Maybe.withDefault "inherit" (Maybe.map (\c -> resolveToken c tokens) props.color))
                    , style "font-family" (Maybe.withDefault "inherit" (Maybe.map (\t -> resolveToken t tokens) props.typography))
                    ]
                    [ text content ]


render : List FlatToken -> Layout -> Html msg
render tokens layout =
    renderLayoutWithSlots Dict.empty tokens Dict.empty layout
