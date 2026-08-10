module Components exposing
    ( Component, Layout(..)
    , StackProps, GridProps, ElementProps, WhenProps
    , StyleContext, StyleLayer, Styling, baseContext
    , matchesContext, resolveStyles, styleContexts
    , styling, mapContextStyles, mapOverrides
    , updateLayoutNode, mapLayout
    , forgetVariant, forgetState, forgetSlot
    , decoder, encoder, layoutDecoder, layoutEncoder
    )

{-| A component definition: the layout tree it renders, and the variants,
states and slots it declares.


# The tree

@docs Component, Layout
@docs StackProps, GridProps, ElementProps, WhenProps


# Styling per variant and state

A node's `styles` are what it looks like with nothing selected. `overrides`
layer on top of that for a particular variant, state, or both — which is how a
component says "in `primary` the background is `{color.brand.500}`" without
duplicating the subtree under a `When`.

`When` is still how a variant changes the _structure_; these layers are how it
changes the _look_.

@docs StyleContext, StyleLayer, Styling, baseContext
@docs matchesContext, resolveStyles, styleContexts
@docs styling, mapContextStyles, mapOverrides


# Editing the tree

Tree surgery, addressed either by index path or across every node. These lived
in `Update.elm` until it became clear that nothing in them needs a `Model` — and
that being unreachable from a test was the only reason they had never had one.

@docs updateLayoutNode, mapLayout
@docs forgetVariant, forgetState, forgetSlot


# Codecs

@docs decoder, encoder, layoutDecoder, layoutEncoder

-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


{-| -}
type Layout
    = Stack StackProps (List Layout)
    | Grid GridProps (List Layout)
    | Element ElementProps String
    | When WhenProps (List Layout)


{-| -}
type alias WhenProps =
    { variant : Maybe String
    , state : Maybe String
    }


{-| -}
type alias StackProps =
    { direction : String
    , styles : Dict String String
    , overrides : List StyleLayer
    }


{-| -}
type alias GridProps =
    { columns : Int
    , styles : Dict String String
    , overrides : List StyleLayer
    }


{-| -}
type alias ElementProps =
    { isSlot : Bool
    , styles : Dict String String
    , overrides : List StyleLayer
    }


{-| Which variant and state a component is being looked at in. `Nothing` in
either position means "whatever is being shown" — `baseContext` is both.
-}
type alias StyleContext =
    { variant : Maybe String
    , state : Maybe String
    }


{-| Styles that apply only in some context. Same two fields as `WhenProps`, and
they mean the same thing, so `matchesContext` reads both.
-}
type alias StyleLayer =
    { variant : Maybe String
    , state : Maybe String
    , styles : Dict String String
    }


{-| Everything a node says about how it looks: the base styles, plus the layers
over them. Carried together because nothing wants one without the other.
-}
type alias Styling =
    { base : Dict String String
    , overrides : List StyleLayer
    }


{-| -}
type alias Component =
    { name : String
    , description : Maybe String
    , variants : List String
    , slots : List String
    , states : List String
    , layout : Maybe Layout
    }


{-| The component with nothing selected.
-}
baseContext : StyleContext
baseContext =
    { variant = Nothing, state = Nothing }


{-| Does this condition hold in this context? A condition that doesn't name a
variant (or a state) doesn't care about it, so it holds whatever is being shown.

Written over an extensible record because `StyleLayer` and `WhenProps` ask the
same question and used to answer it in two places — the renderer's conditional
nodes and the style layers here.

-}
matchesContext : StyleContext -> { r | variant : Maybe String, state : Maybe String } -> Bool
matchesContext context condition =
    let
        matches wanted active =
            case wanted of
                Just w ->
                    Just w == active

                Nothing ->
                    True
    in
    matches condition.variant context.variant && matches condition.state context.state


{-| How specific a condition is, so that a layer naming both a variant and a
state beats one naming only a variant.
-}
specificity : { r | variant : Maybe String, state : Maybe String } -> Int
specificity condition =
    case ( condition.variant, condition.state ) of
        ( Nothing, Nothing ) ->
            0

        ( Just _, Nothing ) ->
            1

        ( Nothing, Just _ ) ->
            2

        ( Just _, Just _ ) ->
            3


{-| What a node actually looks like in one context: the base styles with every
matching layer merged over them, least specific first, and document order
breaking ties within a level.

The levels are walked explicitly rather than sorted, because `List.sortBy` makes
no promise about equal keys and the answer here has to be the same every time —
it ends up in a file that gets committed and diffed.

-}
resolveStyles : StyleContext -> Styling -> Dict String String
resolveStyles context node =
    let
        applicable =
            List.filter (matchesContext context) node.overrides
    in
    List.range 0 3
        |> List.concatMap (\level -> List.filter (\layer -> specificity layer == level) applicable)
        |> List.foldl (\layer acc -> Dict.union layer.styles acc) node.base


{-| Every context some layer in this tree actually names, `baseContext` first.

Derived from the layers rather than from the component's variant and state lists
on purpose: a component with four variants and five states has twenty
combinations and almost never styles more than a handful of them.

-}
styleContexts : Layout -> List StyleContext
styleContexts layout =
    let
        collect node acc =
            let
                fromNode =
                    styling node
                        |> Maybe.map (\s -> List.map (\l -> { variant = l.variant, state = l.state }) s.overrides)
                        |> Maybe.withDefault []
            in
            List.foldl collect (acc ++ fromNode) (children node)
    in
    collect layout [ baseContext ]
        |> List.foldl
            (\context acc ->
                if List.member context acc then
                    acc

                else
                    acc ++ [ context ]
            )
            []


children : Layout -> List Layout
children layout =
    case layout of
        Stack _ nodes ->
            nodes

        Grid _ nodes ->
            nodes

        When _ nodes ->
            nodes

        Element _ _ ->
            []


{-| A node's styling, whatever kind of node it is. `When` carries no styles of
its own, so it has none.

This is the reason the rest of the app can stop re-deriving the node type every
time it wants to read a style. Writing goes through `mapContextStyles` or
`mapOverrides` rather than a public setter, so a caller can't put a node's base
and its layers back inconsistently.

-}
styling : Layout -> Maybe Styling
styling layout =
    case layout of
        Stack props _ ->
            Just { base = props.styles, overrides = props.overrides }

        Grid props _ ->
            Just { base = props.styles, overrides = props.overrides }

        Element props _ ->
            Just { base = props.styles, overrides = props.overrides }

        When _ _ ->
            Nothing


{-| The counterpart of `styling`. A `When` is returned untouched.
-}
setStyling : Styling -> Layout -> Layout
setStyling node layout =
    case layout of
        Stack props nodes ->
            Stack { props | styles = node.base, overrides = node.overrides } nodes

        Grid props nodes ->
            Grid { props | styles = node.base, overrides = node.overrides } nodes

        Element props content ->
            Element { props | styles = node.base, overrides = node.overrides } content

        When _ _ ->
            layout


{-| Edit the styles that belong to one context, and only that one. In
`baseContext` that is the base dict; anywhere else it is that context's layer,
created on demand.

A layer left empty is dropped rather than kept as an empty object, so resetting
the last override on a node leaves no trace of it in the committed file.

-}
mapContextStyles : StyleContext -> (Dict String String -> Dict String String) -> Layout -> Layout
mapContextStyles context f layout =
    case styling layout of
        Nothing ->
            layout

        Just node ->
            if context == baseContext then
                setStyling { node | base = f node.base } layout

            else
                let
                    isTarget layer =
                        layer.variant == context.variant && layer.state == context.state

                    updated =
                        node.overrides
                            |> List.filter isTarget
                            |> List.head
                            |> Maybe.map .styles
                            |> Maybe.withDefault Dict.empty
                            |> f
                in
                setStyling
                    { node
                        | overrides =
                            if Dict.isEmpty updated then
                                List.filter (not << isTarget) node.overrides

                            else if List.any isTarget node.overrides then
                                List.map
                                    (\layer ->
                                        if isTarget layer then
                                            { layer | styles = updated }

                                        else
                                            layer
                                    )
                                    node.overrides

                            else
                                node.overrides ++ [ { variant = context.variant, state = context.state, styles = updated } ]
                    }
                    layout


{-| Rewrite a node's layers wholesale — what dropping a deleted variant's
styling needs.
-}
mapOverrides : (List StyleLayer -> List StyleLayer) -> Layout -> Layout
mapOverrides f layout =
    case styling layout of
        Nothing ->
            layout

        Just node ->
            setStyling { node | overrides = f node.overrides } layout


{-| Apply a function to the one node at `path`, an index path from the root.

An index that doesn't exist, or a path that descends into an `Element`, leaves
the tree alone rather than failing — the editor addresses nodes by position, so
a path can go stale between render and click.

-}
updateLayoutNode : List Int -> (Layout -> Layout) -> Layout -> Layout
updateLayoutNode path updateFn layout =
    case path of
        [] ->
            updateFn layout

        index :: rest ->
            let
                descend =
                    List.indexedMap
                        (\i c ->
                            if i == index then
                                updateLayoutNode rest updateFn c

                            else
                                c
                        )
            in
            case layout of
                Stack props children_ ->
                    Stack props (descend children_)

                Grid props children_ ->
                    Grid props (descend children_)

                When props children_ ->
                    When props (descend children_)

                Element _ _ ->
                    layout


{-| Rewrites every node in the tree. `updateLayoutNode` addresses one node by
path; this is for the edits that have to touch all of them, like forgetting a
variant that no longer exists.
-}
mapLayout : (Layout -> Layout) -> Layout -> Layout
mapLayout f layout =
    case f layout of
        Stack props children_ ->
            Stack props (List.map (mapLayout f) children_)

        Grid props children_ ->
            Grid props (List.map (mapLayout f) children_)

        When props children_ ->
            When props (List.map (mapLayout f) children_)

        (Element _ _) as element ->
            element


{-| A `When` that named the removed variant becomes one that doesn't ask about
variants at all, rather than one that can never be true — and the styles written
for that variant go with it. A layer left behind would be invisible in the
editor and would come back to life the moment someone added the name again.

Apply it to every node with `mapLayout`; on its own it only rewrites the node it
is given.

-}
forgetVariant : String -> Layout -> Layout
forgetVariant name layout =
    (case layout of
        When props children_ ->
            if props.variant == Just name then
                When { props | variant = Nothing } children_

            else
                layout

        _ ->
            layout
    )
        |> mapOverrides (List.filter (\layer -> layer.variant /= Just name))


{-| As `forgetVariant`, for the other half of a condition.
-}
forgetState : String -> Layout -> Layout
forgetState name layout =
    (case layout of
        When props children_ ->
            if props.state == Just name then
                When { props | state = Nothing } children_

            else
                layout

        _ ->
            layout
    )
        |> mapOverrides (List.filter (\layer -> layer.state /= Just name))


{-| A placeholder for a slot that no longer exists goes back to being an ordinary
empty text element — visible, and something you can type into.
-}
forgetSlot : String -> Layout -> Layout
forgetSlot name layout =
    case layout of
        Element props content ->
            if props.isSlot && content == name then
                Element { props | isSlot = False } ""

            else
                layout

        _ ->
            layout


{-| -}
layoutDecoder : Decoder Layout
layoutDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "stack" ->
                        Decode.map2 Stack
                            (Decode.map3 StackProps
                                (Decode.field "direction" Decode.string)
                                stylesField
                                overridesField
                            )
                            childrenField

                    "grid" ->
                        Decode.map2 Grid
                            (Decode.map3 GridProps
                                (Decode.field "columns" Decode.int)
                                stylesField
                                overridesField
                            )
                            childrenField

                    "element" ->
                        Decode.map2 Element
                            (Decode.map3 ElementProps
                                (Decode.field "isSlot" Decode.bool)
                                stylesField
                                overridesField
                            )
                            (Decode.field "content" Decode.string)

                    "when" ->
                        Decode.map2 When
                            (Decode.map2 WhenProps
                                (Decode.maybe (Decode.field "variant" Decode.string))
                                (Decode.maybe (Decode.field "state" Decode.string))
                            )
                            childrenField

                    _ ->
                        Decode.fail ("Unknown layout type: " ++ type_)
            )


childrenField : Decoder (List Layout)
childrenField =
    Decode.field "children" (Decode.list (Decode.lazy (\_ -> layoutDecoder)))


stylesField : Decoder (Dict String String)
stylesField =
    Decode.field "styles" (Decode.dict Decode.string)
        |> orElse (Decode.succeed Dict.empty)


{-| Absent means none. Every component file written before style layers existed
has no `overrides` key at all, and has to keep loading.
-}
overridesField : Decoder (List StyleLayer)
overridesField =
    Decode.field "overrides" (Decode.list styleLayerDecoder)
        |> orElse (Decode.succeed [])


styleLayerDecoder : Decoder StyleLayer
styleLayerDecoder =
    Decode.map3 StyleLayer
        (Decode.maybe (Decode.field "variant" Decode.string))
        (Decode.maybe (Decode.field "state" Decode.string))
        stylesField


orElse : Decoder a -> Decoder a -> Decoder a
orElse fallback decoder2 =
    Decode.oneOf [ decoder2, fallback ]


{-| A field that is left out entirely when there is nothing to say, so that
saving a component doesn't add keys to a file that didn't have them.
-}
optionalField : String -> (a -> Value) -> Maybe a -> List ( String, Value )
optionalField key encode value =
    case value of
        Just v ->
            [ ( key, encode v ) ]

        Nothing ->
            []


{-| -}
layoutEncoder : Layout -> Value
layoutEncoder layout =
    let
        stylingFields node =
            ( "styles", Encode.dict identity Encode.string node.base )
                :: optionalField "overrides"
                    (Encode.list styleLayerEncoder)
                    (if List.isEmpty node.overrides then
                        Nothing

                     else
                        Just node.overrides
                    )
    in
    case layout of
        Stack props nodes ->
            Encode.object
                ([ ( "type", Encode.string "stack" )
                 , ( "direction", Encode.string props.direction )
                 ]
                    ++ stylingFields { base = props.styles, overrides = props.overrides }
                    ++ [ ( "children", Encode.list layoutEncoder nodes ) ]
                )

        Grid props nodes ->
            Encode.object
                ([ ( "type", Encode.string "grid" )
                 , ( "columns", Encode.int props.columns )
                 ]
                    ++ stylingFields { base = props.styles, overrides = props.overrides }
                    ++ [ ( "children", Encode.list layoutEncoder nodes ) ]
                )

        Element props content ->
            Encode.object
                ([ ( "type", Encode.string "element" )
                 , ( "isSlot", Encode.bool props.isSlot )
                 ]
                    ++ stylingFields { base = props.styles, overrides = props.overrides }
                    ++ [ ( "content", Encode.string content ) ]
                )

        When props nodes ->
            -- Field order is load-bearing: these files are committed and
            -- diffed, so reordering keys would churn every component in the
            -- repository the next time it was saved.
            Encode.object
                ([ ( "type", Encode.string "when" )
                 , ( "children", Encode.list layoutEncoder nodes )
                 ]
                    ++ optionalField "variant" Encode.string props.variant
                    ++ optionalField "state" Encode.string props.state
                )


styleLayerEncoder : StyleLayer -> Value
styleLayerEncoder layer =
    Encode.object
        (optionalField "variant" Encode.string layer.variant
            ++ optionalField "state" Encode.string layer.state
            ++ [ ( "styles", Encode.dict identity Encode.string layer.styles ) ]
        )


{-| -}
decoder : Decoder Component
decoder =
    Decode.map6 Component
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "description" Decode.string))
        (Decode.field "variants" (Decode.list Decode.string))
        (Decode.field "slots" (Decode.list Decode.string))
        (Decode.field "states" (Decode.list Decode.string))
        (Decode.maybe (Decode.field "layout" layoutDecoder))


{-| -}
encoder : Component -> Value
encoder component =
    Encode.object
        ([ ( "name", Encode.string component.name )
         , ( "variants", Encode.list Encode.string component.variants )
         , ( "slots", Encode.list Encode.string component.slots )
         , ( "states", Encode.list Encode.string component.states )
         ]
            ++ optionalField "description" Encode.string component.description
            ++ optionalField "layout" layoutEncoder component.layout
        )
