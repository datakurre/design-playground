module Renderer exposing (render, renderScreenNode)

import Components exposing (Component, Layout(..))
import Dict exposing (Dict)
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (style)
import Screens exposing (Screen, ScreenNode(..))
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
        cleanPath =
            String.trim path

        aliasPath =
            if String.startsWith "{" cleanPath && String.endsWith "}" cleanPath then
                String.slice 1 -1 cleanPath |> String.trim
            else
                cleanPath

        parsedPath =
            String.split "." aliasPath |> List.map String.trim |> List.filter (\s -> s /= "")

        tokenValue =
            List.filter (\( p, _ ) -> p == parsedPath) tokens
                |> List.head
                |> Maybe.map (\( _, t ) -> Tokens.resolveAliasValue tokens t.value)
    in
    case tokenValue of
        Just v ->
            v

        Nothing ->
            -- If it's not a single direct token match, resolve any embedded aliases
            -- e.g., "1px solid {color.primary}" -> "1px solid #ff0000"
            Tokens.StringValue (Tokens.resolveAlias tokens path)

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

renderScreenNode : Dict String Component -> Dict String Screen -> List String -> List FlatToken -> ScreenNode -> Html msg
renderScreenNode components screens visited tokens node =
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
                            renderLayoutWithSlots components screens visited tokens slotDict layout

                        Nothing ->
                            div [ style "color" "red", style "border" "1px solid red", style "padding" "0.5rem" ]
                                [ text ("Component " ++ props.componentName ++ " has no layout defined.") ]

                Nothing ->
                    div [ style "color" "red", style "border" "1px solid red", style "padding" "0.5rem" ]
                        [ text ("Component not found: " ++ props.componentName) ]

        ScreenInstance props ->
            if List.member props.screenName visited then
                div [ style "color" "red", style "border" "1px solid red", style "padding" "0.5rem" ]
                    [ text ("Infinite recursion detected for screen: " ++ props.screenName) ]
            else
                case Dict.get props.screenName screens of
                    Just screen ->
                        renderScreenNode components screens (props.screenName :: visited) tokens screen.root
                    Nothing ->
                        div [ style "color" "red", style "border" "1px solid red", style "padding" "0.5rem" ]
                            [ text ("Screen not found: " ++ props.screenName) ]

        Container props children ->
            div
                ( [ style "display" "flex"
                  , style "flex-direction" props.direction
                  ] ++ renderStyles tokens props.styles
                )
                (List.map (renderScreenNode components screens visited tokens) children)

        TextNode content ->
            text content


renderLayoutWithSlots : Dict String Component -> Dict String Screen -> List String -> List FlatToken -> Dict String (List ScreenNode) -> Layout -> Html msg
renderLayoutWithSlots components screens visited tokens slots layout =
    case layout of
        Stack props children ->
            div
                ( [ style "display" "flex"
                  , style "flex-direction" props.direction
                  ] ++ renderStyles tokens props.styles
                )
                (List.map (renderLayoutWithSlots components screens visited tokens slots) children)

        Grid props children ->
            div
                ( [ style "display" "grid"
                  , style "grid-template-columns" ("repeat(" ++ String.fromInt props.columns ++ ", 1fr)")
                  ] ++ renderStyles tokens props.styles
                )
                (List.map (renderLayoutWithSlots components screens visited tokens slots) children)

        Element props content ->
            if props.isSlot then
                case Dict.get content slots of
                    Just slotChildren ->
                        div
                            [ style "display" "contents" ]
                            (List.map (renderScreenNode components screens visited tokens) slotChildren)

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
    renderLayoutWithSlots Dict.empty Dict.empty [] tokens Dict.empty layout
