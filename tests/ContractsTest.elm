module ContractsTest exposing (..)

import Contracts exposing (..)
import Expect
import Json.Decode as Decode
import Test exposing (..)

suite : Test
suite =
    describe "Contracts Codec"
        [ test "encodes and decodes a full contract" <|
            \_ ->
                let
                    contract =
                        { component = "Button"
                        , rules =
                            [ AllowedTokenGroups [ [ "interactive" ], [ "spacing" ] ]
                            , NoHardcodedValues [ "color", "background-color", "border-color" ]
                            , SpacingOnScale [ "padding", "margin", "gap" ] [ "spacing" ]
                            , ContrastThreshold { foreground = "color", background = "background-color", minimumRatio = 4.5 }
                            ]
                        }

                    encoded =
                        Contracts.encoder contract

                    decoded =
                        Decode.decodeValue Contracts.decoder encoded
                in
                Expect.equal (Ok contract) decoded
        , test "decodes a contract from JSON string" <|
            \_ ->
                let
                    jsonString =
                        """
                        {
                          "component": "Button",
                          "rules": [
                            { "type": "allowedTokenGroups", "groups": ["interactive", "spacing"] },
                            { "type": "noHardcodedValues", "properties": ["color", "background-color", "border-color"] },
                            { "type": "spacingOnScale", "properties": ["padding", "margin", "gap"], "scale": "spacing" },
                            { "type": "contrastThreshold", "foreground": "color", "background": "background-color", "minimumRatio": 4.5 }
                          ]
                        }
                        """

                    expected =
                        { component = "Button"
                        , rules =
                            [ AllowedTokenGroups [ [ "interactive" ], [ "spacing" ] ]
                            , NoHardcodedValues [ "color", "background-color", "border-color" ]
                            , SpacingOnScale [ "padding", "margin", "gap" ] [ "spacing" ]
                            , ContrastThreshold { foreground = "color", background = "background-color", minimumRatio = 4.5 }
                            ]
                        }

                    decoded =
                        Decode.decodeString Contracts.decoder jsonString
                in
                Expect.equal (Ok expected) decoded
        , test "fails on unknown rule type" <|
            \_ ->
                let
                    jsonString =
                        """
                        {
                          "component": "Button",
                          "rules": [
                            { "type": "unknownRuleType" }
                          ]
                        }
                        """
                in
                case Decode.decodeString Contracts.decoder jsonString of
                    Err _ ->
                        Expect.pass

                    Ok _ ->
                        Expect.fail "Should have failed to decode unknown rule type"
        ]
