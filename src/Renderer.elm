module Renderer exposing (render, renderScreenNode)

import Components exposing (Component, Layout(..))
import Dict exposing (Dict)
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (style)
import Screens exposing (ScreenNode(..))
import Tokens exposing (FlatToken)


camelToKebab : String -> String
camelToKebab str =
    String.toList str
        |> List.concatMap
            (\c ->
                if Char.isUpper c then
                    [ '-', Char.toLower c ]
                else
                    [ c ]
            )
        |> String.fromList


resolveToken : String -> List FlatToken -> Tokens.TokenValue
resolveToken path tokens =
    let
        parsedPath =
            String.split "." path |> List.map String.trim |> List.filter (\s -> s /= "")

        tokenValue =
            List.filter (\( p, _ ) -> p == parsedPath) tokens
                |> List.head
                |> Maybe.map (\( _, t ) -> Tokens.resolveAliasValue tokens t.value)
    in
    case tokenValue of
        Just v ->
            v

        Nothing ->
            Tokens.StringValue path -- fallback to raw value if token not found (could be a valid css value like "16px")

renderStyles : List FlatToken -> Dict String String -> List (Html.Attribute msg)
renderStyles tokens stylesDict =
    Dict.toList stylesDict
        |> List.concatMap (\( prop, tokenPath ) -> 
            case resolveToken tokenPath tokens of
                Tokens.StringValue s ->
                    [ style (camelToKebab prop) s ]
                Tokens.CompositeValue dict ->
                    Dict.toList dict
                        |> List.map (\( subProp, subVal ) -> style (camelToKebab subProp) subVal)
        )

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
                ( [ style "display" "flex"
                  , style "flex-direction" props.direction
                  ] ++ renderStyles tokens props.styles
                )
                (List.map (renderScreenNode components tokens) children)

        TextNode content ->
            text content


renderLayoutWithSlots : Dict String Component -> List FlatToken -> Dict String (List ScreenNode) -> Layout -> Html msg
renderLayoutWithSlots components tokens slots layout =
    case layout of
        Stack props children ->
            div
                ( [ style "display" "flex"
                  , style "flex-direction" props.direction
                  ] ++ renderStyles tokens props.styles
                )
                (List.map (renderLayoutWithSlots components tokens slots) children)

        Grid props children ->
            div
                ( [ style "display" "grid"
                  , style "grid-template-columns" ("repeat(" ++ String.fromInt props.columns ++ ", 1fr)")
                  ] ++ renderStyles tokens props.styles
                )
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
                            ( [ style "border" "1px dashed #ccc"
                              , style "padding" "0.5rem"
                              ] ++ renderStyles tokens props.styles
                            )
                            [ text ("Slot: " ++ content) ]

            else
                span
                    (renderStyles tokens props.styles)
                    [ text content ]

render : List FlatToken -> Layout -> Html msg
render tokens layout =
    renderLayoutWithSlots Dict.empty tokens Dict.empty layout
