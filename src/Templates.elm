module Templates exposing (Entry, componentTemplates, emptyComponent, buttonComponent, cardComponent, inputComponent, badgeComponent, alertComponent)

import Components
import Dict


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
