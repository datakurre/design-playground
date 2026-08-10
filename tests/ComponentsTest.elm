module ComponentsTest exposing (..)

import Components exposing (Layout(..))
import Dict
import Expect
import Json.Decode as Decode
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
                  , Stack { direction = "row", styles = Dict.singleton "gap" "{spacing.sm}" }
                        [ When { variant = Just "primary", state = Nothing }
                            [ Element { isSlot = True, styles = Dict.empty } "icon" ]
                        , When { variant = Just "secondary", state = Just "hover" }
                            [ Grid { columns = 2, styles = Dict.empty } [ text "Cell" ] ]
                        ]
                  )
                ]
            )
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
    Element { isSlot = False, styles = Dict.empty } content
