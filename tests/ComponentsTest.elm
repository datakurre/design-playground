module ComponentsTest exposing (..)

import Components exposing (Layout(..))
import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (..)


suite : Test
suite =
    describe "Components Codec"
        [ test "encodes and decodes a component" <|
            \_ ->
                let
                    component =
                        { name = "button"
                        , description = Just "A simple button component"
                        , variants = [ "primary", "secondary" ]
                        , slots = [ "icon" ]
                        , states = [ "hover", "disabled" ]
                        , layout = Nothing
                        }

                    encoded =
                        Components.encoder component

                    decoded =
                        Decode.decodeValue Components.decoder encoded
                in
                Expect.equal (Ok component) decoded
        , test "decodes a component from JSON string" <|
            \_ ->
                let
                    jsonString =
                        """
                        {
                            "name": "card",
                            "description": null,
                            "variants": ["elevated"],
                            "slots": ["header", "content"],
                            "states": []
                        }
                        """

                    expected =
                        { name = "card"
                        , description = Nothing
                        , variants = [ "elevated" ]
                        , slots = [ "header", "content" ]
                        , states = []
                        , layout = Nothing
                        }

                    decoded =
                        Decode.decodeString Components.decoder jsonString
                in
                Expect.equal (Ok expected) decoded
        , describe "layouts round-trip"
            (List.map layoutRoundTrips
                [ ( "a conditional on a variant"
                  , When { variant = Just "primary", state = Nothing } [ text "Go" ]
                  )
                , ( "a conditional on a state"
                  , When { variant = Nothing, state = Just "disabled" } [ text "Wait" ]
                  )
                , ( "a conditional on both"
                  , When { variant = Just "primary", state = Just "hover" } [ text "Go" ]
                  )

                -- A `when` with neither is the encoder's awkward case: both
                -- fields are omitted, so it has to decode back to a condition
                -- that asks nothing rather than fail.
                , ( "a conditional on nothing"
                  , When { variant = Nothing, state = Nothing } [ text "Always" ]
                  )
                , ( "a conditional with no children"
                  , When { variant = Just "primary", state = Nothing } []
                  )
                , ( "conditionals nested inside a stack"
                  , Stack { direction = "row", styles = Dict.singleton "gap" "{spacing.sm}", overrides = [] }
                        [ When { variant = Just "primary", state = Nothing }
                            [ Element { isSlot = True, styles = Dict.empty, overrides = [] } "icon" ]
                        , When { variant = Just "secondary", state = Just "hover" }
                            [ Grid { columns = 2, styles = Dict.empty, overrides = [] } [ text "Cell" ] ]
                        ]
                  )
                , ( "a style layer on a variant"
                  , Element
                        { isSlot = False
                        , styles = Dict.singleton "padding" "{spacing.sm}"
                        , overrides = [ layer (Just "primary") Nothing [ ( "background-color", "{color.brand.500}" ) ] ]
                        }
                        "Go"
                  )
                , ( "a style layer on a state"
                  , Element
                        { isSlot = False
                        , styles = Dict.empty
                        , overrides = [ layer Nothing (Just "disabled") [ ( "opacity", "0.5" ) ] ]
                        }
                        "Go"
                  )
                , ( "a style layer on both"
                  , Element
                        { isSlot = False
                        , styles = Dict.empty
                        , overrides = [ layer (Just "primary") (Just "hover") [ ( "background-color", "{color.brand.600}" ) ] ]
                        }
                        "Go"
                  )
                , ( "several layers on one node"
                  , Stack
                        { direction = "row"
                        , styles = Dict.singleton "gap" "{spacing.sm}"
                        , overrides =
                            [ layer (Just "primary") Nothing [ ( "background-color", "{color.brand.500}" ) ]
                            , layer (Just "danger") Nothing [ ( "background-color", "{color.red.500}" ) ]
                            , layer Nothing (Just "hover") [ ( "cursor", "pointer" ) ]
                            ]
                        }
                        [ text "Go" ]
                  )
                , ( "layers on a nested grid"
                  , Stack { direction = "column", styles = Dict.empty, overrides = [] }
                        [ Grid
                            { columns = 2
                            , styles = Dict.empty
                            , overrides = [ layer (Just "wide") Nothing [ ( "gap", "{spacing.lg}" ) ] ]
                            }
                            []
                        ]
                  )
                ]
            )
        , describe "style layers are an addition, not a rewrite"
            [ test "a node written before layers existed decodes with none" <|
                \_ ->
                    """
                    { "type": "element", "isSlot": false
                    , "styles": { "padding": "1rem" }
                    , "content": "Go" }
                    """
                        |> Decode.decodeString Components.layoutDecoder
                        |> Expect.equal
                            (Ok (Element { isSlot = False, styles = Dict.singleton "padding" "1rem", overrides = [] } "Go"))
            , test "a node with no layers encodes without an overrides key" <|
                \_ ->
                    -- Persistence is Git. Saving an untouched component must
                    -- not add a key to every node and churn the whole file.
                    Element { isSlot = False, styles = Dict.singleton "padding" "1rem", overrides = [] } "Go"
                        |> Components.layoutEncoder
                        |> Encode.encode 0
                        |> String.contains "overrides"
                        |> Expect.equal False
            , test "a layer with no condition encodes without variant or state keys" <|
                \_ ->
                    Element { isSlot = False, styles = Dict.empty, overrides = [ layer Nothing Nothing [ ( "color", "red" ) ] ] } "Go"
                        |> Components.layoutEncoder
                        |> Encode.encode 0
                        |> Expect.equal
                            "{\"type\":\"element\",\"isSlot\":false,\"styles\":{},\"overrides\":[{\"styles\":{\"color\":\"red\"}}],\"content\":\"Go\"}"
            ]
        , describe "resolveStyles"
            [ test "with nothing selected, only the base styles apply" <|
                \_ ->
                    Components.resolveStyles Components.baseContext
                        { base = Dict.fromList [ ( "color", "black" ) ]
                        , overrides = [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        }
                        |> Expect.equal (Dict.fromList [ ( "color", "black" ) ])
            , test "a layer naming neither always applies" <|
                \_ ->
                    Components.resolveStyles Components.baseContext
                        { base = Dict.fromList [ ( "color", "black" ) ]
                        , overrides = [ layer Nothing Nothing [ ( "color", "grey" ) ] ]
                        }
                        |> Expect.equal (Dict.fromList [ ( "color", "grey" ) ])
            , test "a layer for another variant is ignored" <|
                \_ ->
                    Components.resolveStyles { variant = Just "secondary", state = Nothing }
                        { base = Dict.fromList [ ( "color", "black" ) ]
                        , overrides = [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        }
                        |> Expect.equal (Dict.fromList [ ( "color", "black" ) ])
            , test "a matching layer merges over the base and keeps what it doesn't mention" <|
                \_ ->
                    Components.resolveStyles { variant = Just "primary", state = Nothing }
                        { base = Dict.fromList [ ( "color", "black" ), ( "padding", "1rem" ) ]
                        , overrides = [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        }
                        |> Expect.equal (Dict.fromList [ ( "color", "white" ), ( "padding", "1rem" ) ])
            , test "a state layer beats a variant layer" <|
                \_ ->
                    Components.resolveStyles { variant = Just "primary", state = Just "hover" }
                        { base = Dict.empty
                        , overrides =
                            [ layer Nothing (Just "hover") [ ( "color", "state" ) ]
                            , layer (Just "primary") Nothing [ ( "color", "variant" ) ]
                            ]
                        }
                        |> Expect.equal (Dict.fromList [ ( "color", "state" ) ])
            , test "a layer naming both beats one naming either" <|
                \_ ->
                    Components.resolveStyles { variant = Just "primary", state = Just "hover" }
                        { base = Dict.fromList [ ( "color", "base" ) ]
                        , overrides =
                            [ layer (Just "primary") (Just "hover") [ ( "color", "both" ) ]
                            , layer Nothing (Just "hover") [ ( "color", "state" ) ]
                            , layer (Just "primary") Nothing [ ( "color", "variant" ) ]
                            ]
                        }
                        |> Expect.equal (Dict.fromList [ ( "color", "both" ) ])
            , test "between equally specific layers, the later one wins" <|
                \_ ->
                    Components.resolveStyles { variant = Just "primary", state = Nothing }
                        { base = Dict.empty
                        , overrides =
                            [ layer (Just "primary") Nothing [ ( "color", "first" ) ]
                            , layer (Just "primary") Nothing [ ( "color", "second" ) ]
                            ]
                        }
                        |> Expect.equal (Dict.fromList [ ( "color", "second" ) ])
            ]
        , describe "styleContexts"
            [ test "a tree with no layers is just the base context" <|
                \_ ->
                    Stack { direction = "row", styles = Dict.empty, overrides = [] } [ text "Go" ]
                        |> Components.styleContexts
                        |> Expect.equal [ Components.baseContext ]
            , test "collects each distinct context once, from anywhere in the tree" <|
                \_ ->
                    Stack
                        { direction = "row"
                        , styles = Dict.empty
                        , overrides = [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        }
                        [ Element
                            { isSlot = False
                            , styles = Dict.empty
                            , overrides =
                                [ layer (Just "primary") Nothing [ ( "color", "white" ) ]
                                , layer (Just "primary") (Just "hover") [ ( "color", "grey" ) ]
                                ]
                            }
                            "Go"
                        ]
                        |> Components.styleContexts
                        |> Expect.equal
                            [ Components.baseContext
                            , { variant = Just "primary", state = Nothing }
                            , { variant = Just "primary", state = Just "hover" }
                            ]
            ]
        , describe "mapContextStyles"
            [ test "in the base context it edits the base styles" <|
                \_ ->
                    Element { isSlot = False, styles = Dict.empty, overrides = [] } "Go"
                        |> Components.mapContextStyles Components.baseContext (Dict.insert "color" "black")
                        |> Expect.equal
                            (Element { isSlot = False, styles = Dict.singleton "color" "black", overrides = [] } "Go")
            , test "in another context it creates that context's layer and leaves the base alone" <|
                \_ ->
                    Element { isSlot = False, styles = Dict.singleton "color" "black", overrides = [] } "Go"
                        |> Components.mapContextStyles { variant = Just "primary", state = Nothing } (Dict.insert "color" "white")
                        |> Expect.equal
                            (Element
                                { isSlot = False
                                , styles = Dict.singleton "color" "black"
                                , overrides = [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                                }
                                "Go"
                            )
            , test "editing an existing layer updates it in place" <|
                \_ ->
                    Element
                        { isSlot = False
                        , styles = Dict.empty
                        , overrides =
                            [ layer (Just "primary") Nothing [ ( "color", "white" ) ]
                            , layer (Just "danger") Nothing [ ( "color", "red" ) ]
                            ]
                        }
                        "Go"
                        |> Components.mapContextStyles { variant = Just "primary", state = Nothing } (Dict.insert "padding" "1rem")
                        |> Expect.equal
                            (Element
                                { isSlot = False
                                , styles = Dict.empty
                                , overrides =
                                    [ layer (Just "primary") Nothing [ ( "color", "white" ), ( "padding", "1rem" ) ]
                                    , layer (Just "danger") Nothing [ ( "color", "red" ) ]
                                    ]
                                }
                                "Go"
                            )
            , test "emptying a layer removes it rather than leaving an empty one behind" <|
                \_ ->
                    Element
                        { isSlot = False
                        , styles = Dict.empty
                        , overrides = [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        }
                        "Go"
                        |> Components.mapContextStyles { variant = Just "primary", state = Nothing } (Dict.remove "color")
                        |> Expect.equal
                            (Element { isSlot = False, styles = Dict.empty, overrides = [] } "Go")
            , test "a When has no styles of its own and is left untouched" <|
                \_ ->
                    When { variant = Just "primary", state = Nothing } [ text "Go" ]
                        |> Components.mapContextStyles Components.baseContext (Dict.insert "color" "black")
                        |> Expect.equal (When { variant = Just "primary", state = Nothing } [ text "Go" ])
            ]
        , describe "updateLayoutNode" <|
            let
                tree =
                    Stack (stack "vertical")
                        [ text "first"
                        , Grid (grid 2) [ text "a", text "b" ]
                        ]

                shout =
                    Components.mapLayout
                        (\node ->
                            case node of
                                Element props content ->
                                    Element props (String.toUpper content)

                                _ ->
                                    node
                        )
            in
            [ test "the empty path rewrites the root itself" <|
                \_ ->
                    text "hi"
                        |> Components.updateLayoutNode [] (always (text "bye"))
                        |> Expect.equal (text "bye")
            , test "descends an index path to one node and leaves its siblings alone" <|
                \_ ->
                    tree
                        |> Components.updateLayoutNode [ 1, 0 ] (always (text "replaced"))
                        |> Expect.equal
                            (Stack (stack "vertical")
                                [ text "first"
                                , Grid (grid 2) [ text "replaced", text "b" ]
                                ]
                            )
            , test "an index past the end of the children changes nothing" <|
                \_ ->
                    tree
                        |> Components.updateLayoutNode [ 7 ] (always (text "replaced"))
                        |> Expect.equal tree
            , test "a negative index changes nothing" <|
                \_ ->
                    tree
                        |> Components.updateLayoutNode [ -1 ] (always (text "replaced"))
                        |> Expect.equal tree
            , test "descending into an Element stops rather than rewriting it" <|
                \_ ->
                    -- The editor addresses nodes by position, so a path can go
                    -- stale between render and click. Going nowhere is the
                    -- right answer; rewriting the wrong node is not.
                    tree
                        |> Components.updateLayoutNode [ 0, 0 ] (always (text "replaced"))
                        |> Expect.equal tree
            , test "mapLayout rewrites every node, at every depth" <|
                \_ ->
                    shout tree
                        |> Expect.equal
                            (Stack (stack "vertical")
                                [ text "FIRST"
                                , Grid (grid 2) [ text "A", text "B" ]
                                ]
                            )
            ]
        , describe "forgetting a name the layout still points at"
            [ test "forgetVariant drops the condition, not the subtree" <|
                \_ ->
                    When { variant = Just "primary", state = Nothing } [ text "Go" ]
                        |> Components.forgetVariant "primary"
                        |> Expect.equal
                            (When { variant = Nothing, state = Nothing } [ text "Go" ])
            , test "forgetVariant leaves a When about a different variant alone" <|
                \_ ->
                    When { variant = Just "secondary", state = Nothing } [ text "Go" ]
                        |> Components.forgetVariant "primary"
                        |> Expect.equal
                            (When { variant = Just "secondary", state = Nothing } [ text "Go" ])
            , test "forgetVariant drops that variant's style layer too" <|
                \_ ->
                    -- A layer left behind is invisible in the editor and comes
                    -- back to life the moment someone re-adds the name.
                    Element
                        { isSlot = False
                        , styles = Dict.empty
                        , overrides =
                            [ layer (Just "primary") Nothing [ ( "color", "white" ) ]
                            , layer (Just "secondary") Nothing [ ( "color", "black" ) ]
                            ]
                        }
                        "Go"
                        |> Components.forgetVariant "primary"
                        |> Expect.equal
                            (Element
                                { isSlot = False
                                , styles = Dict.empty
                                , overrides = [ layer (Just "secondary") Nothing [ ( "color", "black" ) ] ]
                                }
                                "Go"
                            )
            , test "forgetState drops the other half of the condition" <|
                \_ ->
                    When { variant = Just "primary", state = Just "hover" } [ text "Go" ]
                        |> Components.forgetState "hover"
                        |> Expect.equal
                            (When { variant = Just "primary", state = Nothing } [ text "Go" ])
            , test "forgetState drops that state's style layer" <|
                \_ ->
                    Element
                        { isSlot = False
                        , styles = Dict.empty
                        , overrides = [ layer Nothing (Just "hover") [ ( "color", "white" ) ] ]
                        }
                        "Go"
                        |> Components.forgetState "hover"
                        |> Expect.equal
                            (Element { isSlot = False, styles = Dict.empty, overrides = [] } "Go")
            , test "forgetSlot turns the placeholder back into an empty element" <|
                \_ ->
                    Element { isSlot = True, styles = Dict.empty, overrides = [] } "icon"
                        |> Components.forgetSlot "icon"
                        |> Expect.equal
                            (Element { isSlot = False, styles = Dict.empty, overrides = [] } "")
            , test "forgetSlot leaves a placeholder for a different slot alone" <|
                \_ ->
                    Element { isSlot = True, styles = Dict.empty, overrides = [] } "header"
                        |> Components.forgetSlot "icon"
                        |> Expect.equal
                            (Element { isSlot = True, styles = Dict.empty, overrides = [] } "header")
            , test "forgetSlot leaves ordinary text that happens to match alone" <|
                \_ ->
                    text "icon"
                        |> Components.forgetSlot "icon"
                        |> Expect.equal (text "icon")
            , test "through mapLayout it reaches a nested When" <|
                \_ ->
                    -- How Update actually calls it: the name can be pointed at
                    -- from anywhere in the tree, not just the root.
                    Stack (stack "vertical")
                        [ When { variant = Just "primary", state = Nothing } [ text "Go" ] ]
                        |> Components.mapLayout (Components.forgetVariant "primary")
                        |> Expect.equal
                            (Stack (stack "vertical")
                                [ When { variant = Nothing, state = Nothing } [ text "Go" ] ]
                            )
            ]
        ]


layoutRoundTrips : ( String, Layout ) -> Test
layoutRoundTrips ( description, layout ) =
    test description <|
        \_ ->
            Components.layoutEncoder layout
                |> Decode.decodeValue Components.layoutDecoder
                |> Expect.equal (Ok layout)


text : String -> Layout
text content =
    Element { isSlot = False, styles = Dict.empty, overrides = [] } content


stack : String -> Components.StackProps
stack direction =
    { direction = direction, styles = Dict.empty, overrides = [] }


grid : Int -> Components.GridProps
grid columns =
    { columns = columns, styles = Dict.empty, overrides = [] }


layer : Maybe String -> Maybe String -> List ( String, String ) -> Components.StyleLayer
layer variant state styles =
    { variant = variant, state = state, styles = Dict.fromList styles }
