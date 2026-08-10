module ContractsTest exposing (..)

import Components exposing (Layout(..))
import Contracts exposing (..)
import Dict
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import Tokens exposing (TokenValue(..))


{-| Encoding a single-rule contract and decoding it back must give the original.
-}
expectRoundTrip : Rule -> Expect.Expectation
expectRoundTrip rule =
    let
        contract =
            { component = "Button", rules = [ rule ] }
    in
    Decode.decodeValue Contracts.decoder (Contracts.encoder contract)
        |> Expect.equal (Ok contract)


suite : Test
suite =
    describe "Contracts Codec"
        [ describe "round-trips each rule variant"
            [ test "AllowedTokenGroups" <|
                \_ ->
                    expectRoundTrip (AllowedTokenGroups [ [ "interactive" ], [ "spacing" ] ])
            , test "NoHardcodedValues" <|
                \_ ->
                    expectRoundTrip (NoHardcodedValues [ "color", "background-color", "border-color" ])
            , test "SpacingOnScale" <|
                \_ ->
                    expectRoundTrip (SpacingOnScale [ "padding", "margin", "gap" ] [ "spacing" ])
            , test "ContrastThreshold" <|
                \_ ->
                    expectRoundTrip (ContrastThreshold { foreground = "color", background = "background-color", minimumRatio = 4.5 })
            , test "all four rule kinds at once" <|
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
                    in
                    Decode.decodeValue Contracts.decoder (Contracts.encoder contract)
                        |> Expect.equal (Ok contract)
            ]
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
            , test "NoHardcodedValues: fails with hardcoded string on listed property" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "padding" "10px" } "content") }

                        contract =
                            { component = "Test", rules = [ NoHardcodedValues [ "padding" ] ] }
                    in
                    case Contracts.validate [] contract component of
                        [ _ ] ->
                            Expect.pass

                        _ ->
                            Expect.fail "Expected 1 violation"
            , test "NoHardcodedValues: fails with a raw hex colour on listed property" <|
                \_ ->
                    -- The rule used to look only for hex literals. It now looks
                    -- for anything that isn't a token reference, which has to
                    -- still catch what it originally caught.
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
            , test "NoHardcodedValues: names the part of a mixed value that is hardcoded" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "border" "1px solid {core.border}" } "content") }

                        contract =
                            { component = "Test", rules = [ NoHardcodedValues [ "border" ] ] }
                    in
                    case Contracts.validate [] contract component of
                        [ violation ] ->
                            -- Saying which part to replace is the difference
                            -- between a report and an instruction.
                            Expect.equal "Hardcoded value: 1px solid" violation.message

                        _ ->
                            Expect.fail "Expected 1 violation"
            , test "NoHardcodedValues: reads through a conditional node" <|
                \_ ->
                    -- `when` nodes hold no styles of their own, so the rule has
                    -- to look past them at what they contain.
                    let
                        component =
                            { name = "Test"
                            , description = Nothing
                            , variants = [ "primary" ]
                            , slots = []
                            , states = []
                            , layout =
                                Just
                                    (When { variant = Just "primary", state = Nothing }
                                        [ Element { isSlot = False, styles = Dict.singleton "color" "#ff0000" } "content" ]
                                    )
                            }

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
            , test "NoHardcodedValues: passes with multiple aliases on listed property" <|
                \_ ->
                    let
                        component =
                            { name = "Test", description = Nothing, variants = [], slots = [], states = [], layout = Just (Element { isSlot = False, styles = Dict.singleton "padding" "{spacing.sm} {spacing.md}" } "content") }

                        contract =
                            { component = "Test", rules = [ NoHardcodedValues [ "padding" ] ] }
                    in
                    Expect.equal [] (Contracts.validate [] contract component)
            , test "NoHardcodedValues: passes with hardcoded string on unlisted property" <|
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
