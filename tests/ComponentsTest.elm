module ComponentsTest exposing (..)

import Components
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
        ]
