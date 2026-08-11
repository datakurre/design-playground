module Renderer exposing (renderScreenNode, renderWithConditions)

import Components exposing (Component, Layout(..), StyleContext)
import CssProperties
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


{-| Turns a node's styles into inline style attributes, dropping anything the
preview shouldn't be allowed to do.

Elm escapes text content and `elm/virtual-dom` blocks `javascript:` in `href`
and `src`, but neither of those reaches a style _value_ — and every value here
comes out of a repository, which in this app is routinely someone else's. Left
unfiltered, a token value of `url(https://…)` on `background-image` makes the
preview fetch from an arbitrary host the moment it renders, and
`position: fixed` with a large `z-index` puts repository-controlled content over
the app's own chrome.

The property name is checked too. It costs nothing — `CssProperties` was
already in the build for the editor's datalist — and an unknown property is a
typo worth not rendering silently.

-}
renderStyles : List FlatToken -> Dict String String -> List (Html.Attribute msg)
renderStyles tokens stylesDict =
    Dict.toList stylesDict
        |> List.concatMap
            (\( prop, tokenPath ) ->
                case resolveToken tokenPath tokens of
                    Tokens.StringValue s ->
                        safeStyle prop s

                    Tokens.CompositeValue dict ->
                        Dict.toList dict
                            |> List.concatMap (\( subProp, subVal ) -> safeStyle subProp subVal)
            )


safeStyle : String -> String -> List (Html.Attribute msg)
safeStyle prop value =
    let
        property =
            camelToKebab prop
    in
    if CssProperties.isKnown property && isSafeStyleValue value then
        [ style property value ]

    else
        []


{-| A style value the preview may apply.

`url(` is the network reach; `expression(` is legacy IE script execution;
`@import` pulls in a whole stylesheet; and a `;` means the value is trying to be
more than one declaration. `position: fixed` is not blocked here — it is a
legitimate thing for a component to want — the value filter is about reach and
smuggling, not layout.

-}
isSafeStyleValue : String -> Bool
isSafeStyleValue value =
    let
        lowered =
            String.toLower value
    in
    not (String.contains "url(" lowered)
        && not (String.contains "expression(" lowered)
        && not (String.contains "@import" lowered)
        && not (String.contains ";" lowered)


renderScreenNode : Dict String Component -> Dict String Screen -> List String -> List FlatToken -> ScreenNode -> Html msg
renderScreenNode components screens visited tokens node =
    case node of
        ComponentInstance props ->
            case Dict.get props.componentName components of
                Just comp ->
                    case comp.layout of
                        Just layout ->
                            renderLayout
                                { components = components
                                , screens = screens
                                , visited = visited
                                , tokens = tokens
                                , slots = Dict.fromList props.slots
                                , activeVariant = props.variant
                                , activeState = props.state
                                }
                                layout

                        Nothing ->
                            previewProblem (props.componentName ++ " has no layout yet — add one on the Components tab.")

                Nothing ->
                    previewProblem ("There is no component called " ++ props.componentName ++ " — create one with that name on the Components tab.")

        ScreenInstance props ->
            if List.member props.screenName visited then
                previewProblem (props.screenName ++ " ends up including itself — remove the loop to preview it.")

            else
                case Dict.get props.screenName screens of
                    Just screen ->
                        renderScreenNode components screens (props.screenName :: visited) tokens screen.root

                    Nothing ->
                        previewProblem ("There is no screen called " ++ props.screenName ++ ".")

        Container props children ->
            div
                ([ style "display" "flex"
                 , style "flex-direction" props.direction
                 ]
                    ++ renderStyles tokens props.styles
                )
                (List.map (renderScreenNode components screens visited tokens) children)

        TextNode content ->
            text content


{-| Everything a layout node needs beyond itself: the libraries to look
components and screens up in, which screens are already being drawn further up
(so a cycle gets caught rather than hanging), the tokens to resolve values
against, what fills each slot, and which variant and state are being shown.

It's a record because all seven travel together, unchanged, down every branch of
the tree — as arguments they were seven things to keep in the right order at
each of six recursive calls.

-}
type alias Env =
    { components : Dict String Component
    , screens : Dict String Screen
    , visited : List String
    , tokens : List FlatToken
    , slots : Dict String (List ScreenNode)
    , activeVariant : Maybe String
    , activeState : Maybe String
    }


{-| Which variant and state are being shown, in the form both the conditional
nodes and the style layers ask about.
-}
context : Env -> StyleContext
context env =
    { variant = env.activeVariant, state = env.activeState }


{-| A node's styles as they stand in the context being drawn — its own styles
with any matching variant or state layer merged over them.
-}
nodeStyles : Env -> { r | styles : Dict String String, overrides : List Components.StyleLayer } -> List (Html.Attribute msg)
nodeStyles env props =
    renderStyles env.tokens
        (Components.resolveStyles (context env) { base = props.styles, overrides = props.overrides })


renderLayout : Env -> Layout -> Html msg
renderLayout env layout =
    case layout of
        Stack props children ->
            div
                ([ style "display" "flex"
                 , style "flex-direction" props.direction
                 ]
                    ++ nodeStyles env props
                )
                (List.map (renderLayout env) children)

        Grid props children ->
            div
                ([ style "display" "grid"
                 , style "grid-template-columns" ("repeat(" ++ String.fromInt props.columns ++ ", 1fr)")
                 ]
                    ++ nodeStyles env props
                )
                (List.map (renderLayout env) children)

        When props children ->
            if Components.matchesContext (context env) props then
                -- `display: contents` keeps the wrapper out of the layout, so
                -- conditional children sit in the parent flex or grid exactly
                -- where they would if the condition weren't there.
                div [ style "display" "contents" ]
                    (List.map (renderLayout env) children)

            else
                text ""

        Element props content ->
            if props.isSlot then
                case Dict.get content env.slots of
                    Just slotChildren ->
                        div
                            [ style "display" "contents" ]
                            (List.map (renderScreenNode env.components env.screens env.visited env.tokens) slotChildren)

                    Nothing ->
                        div
                            ([ style "border" "1px dashed #ccc"
                             , style "padding" "0.5rem"
                             ]
                                ++ nodeStyles env props
                            )
                            [ text ("Slot: " ++ content) ]

            else
                span
                    (nodeStyles env props)
                    [ text content ]


{-| A layout as it looks under one variant and state — what the Components tab
previews while you flip between them.
-}
renderWithConditions : List FlatToken -> Maybe String -> Maybe String -> Layout -> Html msg
renderWithConditions tokens activeVariant activeState layout =
    renderLayout
        { components = Dict.empty
        , screens = Dict.empty
        , visited = []
        , tokens = tokens
        , slots = Dict.empty
        , activeVariant = activeVariant
        , activeState = activeState
        }
        layout


{-| Something in the design can't be drawn. This renders inside the preview
surface, among the user's own token-driven styles, so it is styled inline like
everything else in this module rather than with the app's Tailwind classes.
-}
previewProblem : String -> Html msg
previewProblem message =
    div
        [ style "color" "#b91c1c"
        , style "background" "#fef2f2"
        , style "border" "1px solid #fecaca"
        , style "border-radius" "6px"
        , style "padding" "0.5rem 0.75rem"
        , style "font" "13px/1.4 system-ui, sans-serif"
        ]
        [ text message ]
