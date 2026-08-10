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


layer : Maybe String -> Maybe String -> List ( String, String ) -> Components.StyleLayer
layer variant state styles =
    { variant = variant, state = state, styles = Dict.fromList styles }
