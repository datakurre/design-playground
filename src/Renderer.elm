module Renderer exposing (render)

import Components exposing (Layout(..))
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (style)
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


render : List FlatToken -> Layout -> Html msg
render tokens layout =
    case layout of
        Stack props children ->
            div
                [ style "display" "flex"
                , style "flex-direction" props.direction
                , style "padding" (Maybe.withDefault "0" (Maybe.map (\p -> resolveToken p tokens) props.padding))
                , style "gap" (Maybe.withDefault "0" (Maybe.map (\g -> resolveToken g tokens) props.gap))
                , style "background-color" (Maybe.withDefault "transparent" (Maybe.map (\bg -> resolveToken bg tokens) props.backgroundColor))
                ]
                (List.map (render tokens) children)

        Grid props children ->
            div
                [ style "display" "grid"
                , style "grid-template-columns" ("repeat(" ++ String.fromInt props.columns ++ ", 1fr)")
                , style "gap" (Maybe.withDefault "0" (Maybe.map (\g -> resolveToken g tokens) props.gap))
                , style "background-color" (Maybe.withDefault "transparent" (Maybe.map (\bg -> resolveToken bg tokens) props.backgroundColor))
                ]
                (List.map (render tokens) children)

        Element props content ->
            if props.isSlot then
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
