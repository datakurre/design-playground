module TemplatesTest exposing (..)

import Components
import Dict
import Expect
import Json.Decode as Decode
import Screens
import Templates
import Test exposing (..)
import Tokens
import TokenScale
import Themes


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
        , test "themeTemplates ids are empty and dark" <|
            \_ ->
                Expect.equal [ "empty", "dark" ] (List.map .id Templates.themeTemplates)
        , test "empty theme template builds empty overrides" <|
            \_ ->
                let
                    emptyTemplate =
                        Templates.themeTemplates |> List.filter (\t -> t.id == "empty") |> List.head
                in
                case emptyTemplate of
                    Just t ->
                        Expect.equal [] (t.build "Foo").overrides
                    Nothing ->
                        Expect.fail "Missing empty template"
        , test "dark theme overrides contain expected endpoints" <|
            \_ ->
                let
                    darkTemplate =
                        Templates.themeTemplates |> List.filter (\t -> t.id == "dark") |> List.head
                    overrides =
                        case darkTemplate of
                            Just t -> (t.build "Dark").overrides
                            Nothing -> []
                in
                Expect.all
                    [ \_ -> Expect.equal True (List.member ( ["color","gray","50"], { value = Tokens.StringValue "#111827", type_ = "color", description = Nothing } ) overrides)
                    , \_ -> Expect.equal True (List.member ( ["color","gray","900"], { value = Tokens.StringValue "#f9fafb", type_ = "color", description = Nothing } ) overrides)
                    , \_ -> Expect.equal True (List.member ( ["color","brand","500"], { value = Tokens.StringValue "#60a5fa", type_ = "color", description = Nothing } ) overrides)
                    ]
                    ()
        , test "End-to-end pure pipeline check for dark theme composition" <|
            \_ ->
                let
                    darkEntry =
                        Templates.themeTemplates |> List.filter (\t -> t.id == "dark") |> List.head |> Maybe.withDefault { id = "dark", label = "Dark", build = \n -> Themes.fromTokens n [] }
                    applied =
                        Themes.applyTheme TokenScale.seed (darkEntry.build "Dark")
                            |> List.filter (\( p, _ ) -> p == [ "color", "gray", "50" ])
                in
                Expect.equal [ ( ["color", "gray", "50"], { value = Tokens.StringValue "#111827", type_ = "color", description = Nothing } ) ] applied
        , test "Codec round-trip for dark theme" <|
            \_ ->
                let
                    darkTheme =
                        (Templates.themeTemplates |> List.filter (\t -> t.id == "dark") |> List.head |> Maybe.map (\t -> t.build "Dark") |> Maybe.withDefault (Themes.fromTokens "Dark" []))
                    encoded =
                        Tokens.encoder darkTheme.overrides
                    decoded =
                        Decode.decodeValue Tokens.decoder encoded
                    sortByPath =
                        List.sortBy (\( p, _ ) -> String.join "." p)
                in
                Expect.equal (Ok (sortByPath darkTheme.overrides)) (Result.map sortByPath decoded)
        , test "screenTemplates ids are correct" <|
            \_ ->
                Expect.equal [ "empty", "login", "dashboard", "landing" ] (List.map .id Templates.screenTemplates)
        , test "screenTemplates thread name and derive path" <|
            \_ ->
                let
                    checks =
                        List.map
                            (\t ->
                                let
                                    s = t.build "My Screen"
                                in
                                s.name == "My Screen" && s.path == "/my-screen"
                            )
                            Templates.screenTemplates
                in
                Expect.equal True (List.all identity checks)
        , test "catalog consistency: template components exist in componentTemplates" <|
            \_ ->
                let
                    validNames =
                        Templates.componentTemplates |> List.map .label

                    collectComponentNames : Screens.ScreenNode -> List String
                    collectComponentNames node =
                        case node of
                            Screens.ComponentInstance props ->
                                [ props.componentName ] ++ List.concatMap (\( _, children ) -> List.concatMap collectComponentNames children) props.slots

                            Screens.ScreenInstance _ ->
                                []

                            Screens.Container _ children ->
                                List.concatMap collectComponentNames children

                            Screens.TextNode _ ->
                                []

                    allScreenRoots =
                        [ (Templates.loginScreen "x").root
                        , (Templates.dashboardScreen "x").root
                        , (Templates.landingScreen "x").root
                        ]

                    usedNames =
                        List.concatMap collectComponentNames allScreenRoots

                    allUsedAreValid =
                        List.all (\name -> List.member name validNames) usedNames
                in
                Expect.equal True allUsedAreValid
        , test "loginScreen has exactly one Button and at least two Inputs" <|
            \_ ->
                let
                    collectComponentNames : Screens.ScreenNode -> List String
                    collectComponentNames node =
                        case node of
                            Screens.ComponentInstance props ->
                                [ props.componentName ] ++ List.concatMap (\( _, children ) -> List.concatMap collectComponentNames children) props.slots

                            Screens.ScreenInstance _ ->
                                []

                            Screens.Container _ children ->
                                List.concatMap collectComponentNames children

                            Screens.TextNode _ ->
                                []

                    names =
                        collectComponentNames (Templates.loginScreen "x").root
                    
                    buttonCount =
                        List.length (List.filter (\n -> n == "Button") names)
                    
                    inputCount =
                        List.length (List.filter (\n -> n == "Input") names)
                in
                Expect.all
                    [ \_ -> Expect.equal 1 buttonCount
                    , \_ -> Expect.atLeast 2 inputCount
                    ]
                    ()
        , test "dashboardScreen has 3 Cards and 1 Badge" <|
            \_ ->
                let
                    collectComponentNames : Screens.ScreenNode -> List String
                    collectComponentNames node =
                        case node of
                            Screens.ComponentInstance props ->
                                [ props.componentName ] ++ List.concatMap (\( _, children ) -> List.concatMap collectComponentNames children) props.slots

                            Screens.ScreenInstance _ ->
                                []

                            Screens.Container _ children ->
                                List.concatMap collectComponentNames children

                            Screens.TextNode _ ->
                                []

                    names =
                        collectComponentNames (Templates.dashboardScreen "x").root
                    
                    cardCount =
                        List.length (List.filter (\n -> n == "Card") names)
                    
                    badgeCount =
                        List.length (List.filter (\n -> n == "Badge") names)
                in
                Expect.all
                    [ \_ -> Expect.equal 3 cardCount
                    , \_ -> Expect.equal 1 badgeCount
                    ]
                    ()
        , test "landingScreen has 1 Alert and 1 Button" <|
            \_ ->
                let
                    collectComponentNames : Screens.ScreenNode -> List String
                    collectComponentNames node =
                        case node of
                            Screens.ComponentInstance props ->
                                [ props.componentName ] ++ List.concatMap (\( _, children ) -> List.concatMap collectComponentNames children) props.slots

                            Screens.ScreenInstance _ ->
                                []

                            Screens.Container _ children ->
                                List.concatMap collectComponentNames children

                            Screens.TextNode _ ->
                                []

                    names =
                        collectComponentNames (Templates.landingScreen "x").root
                    
                    alertCount =
                        List.length (List.filter (\n -> n == "Alert") names)
                    
                    buttonCount =
                        List.length (List.filter (\n -> n == "Button") names)
                in
                Expect.all
                    [ \_ -> Expect.equal 1 alertCount
                    , \_ -> Expect.equal 1 buttonCount
                    ]
                    ()
        , test "Codec round-trip for all screen templates" <|
            \_ ->
                let
                    roundTrips =
                        List.all
                            (\t ->
                                let
                                    screen =
                                        t.build "X"

                                    encoded =
                                        Screens.encoder screen

                                    decoded =
                                        Decode.decodeValue Screens.decoder encoded
                                in
                                decoded == Ok screen
                            )
                            Templates.screenTemplates
                in
                Expect.equal True roundTrips
        ]
