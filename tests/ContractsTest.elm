module ContractsTest exposing (..)

import Components exposing (Layout(..))
import Contracts exposing (..)
import Dict
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import Tokens exposing (TokenValue(..))

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
        , describe "validate"
            [ test "AllowedTokenGroups: passes when reference is inside an allowed group" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "color" "{interactive.primary}" } "content") }

                        contract =
                            { component = "Test", rules = [ AllowedTokenGroups [ [ "interactive" ] ] ] }
                    in
                    Expect.equal [] (Contracts.validate [] contract component)
            , test "AllowedTokenGroups: fails when reference is outside allowed groups" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "color" "{danger.primary}" } "content") }

                        contract =
                            { component = "Test", rules = [ AllowedTokenGroups [ [ "interactive" ] ] ] }
                    in
                    case Contracts.validate [] contract component of
                        [ violation ] ->
                            Expect.equal (Just "color") violation.property

                        _ ->
                            Expect.fail "Expected 1 violation"
            , test "NoHardcodedValues: fails with raw hex on listed property" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "color" "#ff0000" } "content") }

                        contract =
                            { component = "Test", rules = [ NoHardcodedValues [ "color" ] ] }
                    in
                    case Contracts.validate [] contract component of
                        [ _ ] ->
                            Expect.pass

                        _ ->
                            Expect.fail "Expected 1 violation"
            , test "NoHardcodedValues: passes with alias on listed property" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "color" "{core.red}" } "content") }

                        contract =
                            { component = "Test", rules = [ NoHardcodedValues [ "color" ] ] }
                    in
                    Expect.equal [] (Contracts.validate [] contract component)
            , test "NoHardcodedValues: passes with hex on unlisted property" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "background" "#ff0000" } "content") }

                        contract =
                            { component = "Test", rules = [ NoHardcodedValues [ "color" ] ] }
                    in
                    Expect.equal [] (Contracts.validate [] contract component)
            , test "SpacingOnScale: passes when resolved matches token in scale group" <|
                \_ ->
                    let
                        tokens =
                            [ ( [ "spacing", "sm" ], { value = StringValue "4px", type_ = "spacing", description = Nothing } ) ]

                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "padding" "4px" } "content") }

                        contract =
                            { component = "Test", rules = [ SpacingOnScale [ "padding" ] [ "spacing" ] ] }
                    in
                    Expect.equal [] (Contracts.validate tokens contract component)
            , test "SpacingOnScale: fails when resolved does not match token in scale group" <|
                \_ ->
                    let
                        tokens =
                            [ ( [ "spacing", "sm" ], { value = StringValue "4px", type_ = "spacing", description = Nothing } ) ]

                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "padding" "5px" } "content") }

                        contract =
                            { component = "Test", rules = [ SpacingOnScale [ "padding" ] [ "spacing" ] ] }
                    in
                    case Contracts.validate tokens contract component of
                        [ _ ] ->
                            Expect.pass

                        _ ->
                            Expect.fail "Expected 1 violation"
            , test "ContrastThreshold: passes with good contrast" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.fromList [ ( "color", "#000000" ), ( "background-color", "#ffffff" ) ] } "content") }

                        contract =
                            { component = "Test", rules = [ ContrastThreshold { foreground = "color", background = "background-color", minimumRatio = 4.5 } ] }
                    in
                    Expect.equal [] (Contracts.validate [] contract component)
            , test "ContrastThreshold: fails with bad contrast" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.fromList [ ( "color", "#888888" ), ( "background-color", "#777777" ) ] } "content") }

                        contract =
                            { component = "Test", rules = [ ContrastThreshold { foreground = "color", background = "background-color", minimumRatio = 4.5 } ] }
                    in
                    case Contracts.validate [] contract component of
                        [ _ ] ->
                            Expect.pass

                        _ ->
                            Expect.fail "Expected 1 violation"
            , test "ContrastThreshold: passes if only one is set" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "color" "#000000" } "content") }

                        contract =
                            { component = "Test", rules = [ ContrastThreshold { foreground = "color", background = "background-color", minimumRatio = 4.5 } ] }
                    in
                    Expect.equal [] (Contracts.validate [] contract component)
            , test "Combines multiple rules" <|
                \_ ->
                    let
                        component =
                            { name = "Test"
                            , description = Nothing
                            , variants = []
                            , slots = []
                            , states = []
                            , layout = Just (Element { isSlot = False, styles = Dict.fromList [ ( "color", "#888888" ), ( "background-color", "#777777" ), ( "padding", "5px" ) ] } "content")
                            }

                        contract =
                            { component = "Test"
                            , rules =
                                [ ContrastThreshold { foreground = "color", background = "background-color", minimumRatio = 4.5 }
                                , SpacingOnScale [ "padding" ] [ "spacing" ]
                                , NoHardcodedValues [ "color" ]
                                ]
                            }
                    in
                    Expect.equal 3 (List.length (Contracts.validate [] contract component))
            ]
        ]
