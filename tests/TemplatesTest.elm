module TemplatesTest exposing (..)

import Components
import Dict
import Expect
import Json.Decode as Decode
import Templates
import Test exposing (..)


suite : Test
suite =
    describe "Templates"
        [ test "componentTemplates ids are exactly in order" <|
            \_ ->
                let
                    ids =
                        List.map .id Templates.componentTemplates
                in
                Expect.equal [ "empty", "button", "card", "input", "badge", "alert" ] ids
        , test "Every template threads the given name through" <|
            \_ ->
                let
                    allNamesMatch =
                        List.all (\t -> (t.build "Widget").name == "Widget") Templates.componentTemplates
                in
                Expect.equal True allNamesMatch
        , test "emptyComponent has no layout, others have layout" <|
            \_ ->
                let
                    emptyHasNoLayout =
                        (Templates.emptyComponent "X").layout == Nothing

                    othersHaveLayout =
                        Templates.componentTemplates
                            |> List.filter (\t -> t.id /= "empty")
                            |> List.all (\t -> (t.build "X").layout /= Nothing)
                in
                Expect.all
                    [ \_ -> Expect.equal True emptyHasNoLayout
                    , \_ -> Expect.equal True othersHaveLayout
                    ]
                    ()
        , test "Regression lock: buttonComponent is exactly the old inline literal" <|
            \_ ->
                let
                    expected =
                        { name = "Btn"
                        , description = Just "A basic button component"
                        , variants = [ "primary", "secondary", "success", "danger" ]
                        , slots = [ "default" ]
                        , states = [ "hover", "active", "disabled" ]
                        , layout = Just (Components.Element { isSlot = True, styles = Dict.fromList [ ( "padding", "0.5rem 1rem" ), ( "border-radius", "0.25rem" ), ( "cursor", "pointer" ) ] } "Button text")
                        }
                in
                Expect.equal expected (Templates.buttonComponent "Btn")
        , test "Regression lock: cardComponent is exactly the old inline literal" <|
            \_ ->
                let
                    expected =
                        { name = "Card"
                        , description = Just "A basic card component"
                        , variants = []
                        , slots = [ "header", "body", "footer" ]
                        , states = []
                        , layout =
                            Just
                                (Components.Stack { direction = "column", styles = Dict.fromList [ ( "border", "1px solid #ccc" ), ( "border-radius", "0.25rem" ), ( "overflow", "hidden" ) ] }
                                    [ Components.Element { isSlot = True, styles = Dict.fromList [ ( "padding", "1rem" ), ( "background-color", "#f8f9fa" ), ( "border-bottom", "1px solid #ccc" ) ] } "Header Slot"
                                    , Components.Element { isSlot = True, styles = Dict.fromList [ ( "padding", "1rem" ) ] } "Body Slot"
                                    , Components.Element { isSlot = True, styles = Dict.fromList [ ( "padding", "1rem" ), ( "background-color", "#f8f9fa" ), ( "border-top", "1px solid #ccc" ) ] } "Footer Slot"
                                    ]
                                )
                        }
                in
                Expect.equal expected (Templates.cardComponent "Card")
        , test "Shape assertions for new templates" <|
            \_ ->
                let
                    input =
                        Templates.inputComponent "Input"

                    badge =
                        Templates.badgeComponent "Badge"

                    alert =
                        Templates.alertComponent "Alert"

                    inputShape =
                        input.variants == [ "default", "error" ] && input.states == [ "focus", "disabled" ]

                    badgeShape =
                        badge.variants == [ "neutral", "positive", "negative" ] && badge.states == []

                    alertShape =
                        case alert.layout of
                            Just (Components.Stack _ [ _ ]) ->
                                True

                            _ ->
                                False
                in
                Expect.all
                    [ \_ -> Expect.equal True inputShape
                    , \_ -> Expect.equal True badgeShape
                    , \_ -> Expect.equal True alertShape
                    ]
                    ()
        , test "Codec round-trip for every catalog entry" <|
            \_ ->
                let
                    roundTrips =
                        List.all
                            (\t ->
                                let
                                    comp =
                                        t.build "X"

                                    encoded =
                                        Components.encoder comp

                                    decoded =
                                        Decode.decodeValue Components.decoder encoded
                                in
                                decoded == Ok comp
                            )
                            Templates.componentTemplates
                in
                Expect.equal True roundTrips
        ]
