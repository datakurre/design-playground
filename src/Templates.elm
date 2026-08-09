module Templates exposing (Entry, componentTemplates, emptyComponent, buttonComponent, cardComponent, inputComponent, badgeComponent, alertComponent, themeTemplates, screenTemplates, emptyScreen, loginScreen, dashboardScreen, landingScreen)

import Components
import Dict
import Screens
import Themes
import Tokens
import TokenScale


type alias Entry a =
    { id : String
    , label : String
    , build : String -> a
    }


componentTemplates : List (Entry Components.Component)
componentTemplates =
    [ { id = "empty", label = "Empty", build = emptyComponent }
    , { id = "button", label = "Button", build = buttonComponent }
    , { id = "card", label = "Card", build = cardComponent }
    , { id = "input", label = "Input", build = inputComponent }
    , { id = "badge", label = "Badge", build = badgeComponent }
    , { id = "alert", label = "Alert", build = alertComponent }
    ]


emptyComponent : String -> Components.Component
emptyComponent name =
    { name = name, description = Nothing, variants = [], slots = [], states = [], layout = Nothing }


buttonComponent : String -> Components.Component
buttonComponent name =
    -- Moved verbatim from the old Update.elm "Button" branch. Do not
    -- change any value here — TemplatesTest.elm locks this exact shape
    -- as a regression test against the pre-extraction behavior.
    { name = name
    , description = Just "A basic button component"
    , variants = [ "primary", "secondary", "success", "danger" ]
    , slots = [ "default" ]
    , states = [ "hover", "active", "disabled" ]
    , layout = Just (Components.Element { isSlot = True, styles = Dict.fromList [ ( "padding", "0.5rem 1rem" ), ( "border-radius", "0.25rem" ), ( "cursor", "pointer" ) ] } "Button text")
    }


cardComponent : String -> Components.Component
cardComponent name =
    -- Moved verbatim from the old Update.elm "Card" branch. Same
    -- regression-test note as buttonComponent above.
    { name = name
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


inputComponent : String -> Components.Component
inputComponent name =
    { name = name
    , description = Just "A single-line text input"
    , variants = [ "default", "error" ]
    , slots = [ "default" ]
    , states = [ "focus", "disabled" ]
    , layout =
        Just
            (Components.Element
                { isSlot = True
                , styles =
                    Dict.fromList
                        [ ( "padding", "0.5rem 0.75rem" )
                        , ( "border", "1px solid #d1d5db" )
                        , ( "border-radius", "0.25rem" )
                        , ( "background-color", "#ffffff" )
                        ]
                }
                "Input value"
            )
    }


badgeComponent : String -> Components.Component
badgeComponent name =
    { name = name
    , description = Just "A small status label"
    , variants = [ "neutral", "positive", "negative" ]
    , slots = [ "default" ]
    , states = []
    , layout =
        Just
            (Components.Element
                { isSlot = True
                , styles = Dict.fromList [ ( "padding", "0.125rem 0.5rem" ), ( "border-radius", "9999px" ), ( "font-size", "0.75rem" ), ( "background-color", "#f3f4f6" ) ]
                }
                "Badge label"
            )
    }


alertComponent : String -> Components.Component
alertComponent name =
    { name = name
    , description = Just "A dismissible banner message"
    , variants = [ "info", "success", "warning", "danger" ]
    , slots = [ "default" ]
    , states = []
    , layout =
        Just
            (Components.Stack
                { direction = "row", styles = Dict.fromList [ ( "padding", "0.75rem 1rem" ), ( "border-radius", "0.25rem" ), ( "border-left", "4px solid #6b7280" ), ( "background-color", "#f9fafb" ), ( "gap", "0.5rem" ), ( "align-items", "center" ) ] }
                [ Components.Element { isSlot = True, styles = Dict.empty } "Alert message" ]
            )
    }


themeTemplates : List (Entry Themes.Theme)
themeTemplates =
    [ { id = "empty", label = "Empty", build = \name -> Themes.fromTokens name [] }
    , { id = "dark", label = "Dark", build = \name -> Themes.fromTokens name darkOverrides }
    ]


{-| Inverts the gray ramp (light backgrounds become dark, dark text
becomes light) and lightens the brand accent one step so it stays
legible against the new dark backgrounds. Deliberately does not touch
every brand step — hover/active shades are left to the base ramp; a
starter theme only needs to flip the two things a dark mode fundamentally
requires: surfaces and one readable accent.
-}
darkOverrides : List Tokens.FlatToken
darkOverrides =
    List.map2
        (\( step, _ ) ( _, invertedHex ) ->
            ( [ "color", "gray", step ], { value = Tokens.StringValue invertedHex, type_ = "color", description = Nothing } )
        )
        TokenScale.grayRamp
        (List.reverse TokenScale.grayRamp)
        ++ [ ( [ "color", "brand", "500" ], { value = Tokens.StringValue (brandStep "400"), type_ = "color", description = Nothing } ) ]


brandStep : String -> String
brandStep step =
    TokenScale.brandRamp
        |> List.filter (\( s, _ ) -> s == step)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault ""


slugPath : String -> String
slugPath name =
    "/" ++ String.replace " " "-" (String.toLower name)


screenTemplates : List (Entry Screens.Screen)
screenTemplates =
    [ { id = "empty", label = "Empty", build = emptyScreen }
    , { id = "login", label = "Login", build = loginScreen }
    , { id = "dashboard", label = "Dashboard", build = dashboardScreen }
    , { id = "landing", label = "Landing", build = landingScreen }
    ]


emptyScreen : String -> Screens.Screen
emptyScreen name =
    -- Moved verbatim from the old Update.elm default (Update.elm:1185
    -- pre-extraction). TemplatesTest.elm locks this as byte-identical
    -- to the previous hardcoded behavior.
    { name = name, path = slugPath name, root = Screens.Container { direction = "column", styles = Dict.fromList [ ( "padding", "2rem" ), ( "gap", "1rem" ) ] } [] }


instance : String -> Maybe String -> Screens.ScreenNode
instance componentName variant =
    Screens.ComponentInstance { componentName = componentName, variant = variant, state = Nothing, slots = [] }


loginScreen : String -> Screens.Screen
loginScreen name =
    { name = name
    , path = slugPath name
    , root =
        Screens.Container { direction = "column", styles = Dict.fromList [ ( "padding", "2rem" ), ( "gap", "1rem" ), ( "max-width", "24rem" ) ] }
            [ Screens.TextNode "Sign in"
            , instance "Input" Nothing
            , instance "Input" Nothing
            , instance "Button" (Just "primary")
            ]
    }


dashboardScreen : String -> Screens.Screen
dashboardScreen name =
    { name = name
    , path = slugPath name
    , root =
        Screens.Container { direction = "column", styles = Dict.fromList [ ( "padding", "2rem" ), ( "gap", "1.5rem" ) ] }
            [ Screens.TextNode "Dashboard"
            , Screens.Container { direction = "row", styles = Dict.fromList [ ( "gap", "1rem" ) ] }
                [ instance "Card" Nothing, instance "Card" Nothing, instance "Card" Nothing ]
            , instance "Badge" (Just "positive")
            ]
    }


landingScreen : String -> Screens.Screen
landingScreen name =
    { name = name
    , path = slugPath name
    , root =
        Screens.Container { direction = "column", styles = Dict.fromList [ ( "padding", "2rem" ), ( "gap", "1.5rem" ) ] }
            [ instance "Alert" (Just "info")
            , Screens.TextNode "Welcome"
            , instance "Button" (Just "primary")
            , Screens.Container { direction = "row", styles = Dict.fromList [ ( "gap", "1rem" ) ] }
                [ instance "Card" Nothing, instance "Card" Nothing ]
            ]
    }

