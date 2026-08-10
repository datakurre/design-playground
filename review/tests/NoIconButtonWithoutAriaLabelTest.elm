module NoIconButtonWithoutAriaLabelTest exposing (all)

import NoIconButtonWithoutAriaLabel exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "NoIconButtonWithoutAriaLabel"
        [ test "reports an icon button with no aria-label" <|
            \() ->
                """module A exposing (..)
import Html exposing (button, text)
import Ui

view = button [ Ui.iconButton ] [ text "×" ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Icon-only button is missing an aria-label"
                            , details =
                                [ "This button uses Ui.iconButton, a bare glyph with no visible text. Its doc comment requires callers to pass an aria-label, because the glyph alone says nothing to a screen reader. Add Html.Attributes.attribute \"aria-label\" \"...\" to this button's attributes."
                                ]
                            , under = "button [ Ui.iconButton ] [ text \"×\" ]"
                            }
                        ]
        , test "does not report an icon button with an aria-label" <|
            \() ->
                """module A exposing (..)
import Html exposing (button, text)
import Html.Attributes
import Ui

view = button [ Ui.iconButton, Html.Attributes.attribute "aria-label" "Remove" ] [ text "×" ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "does not report a button with no icon at all" <|
            \() ->
                """module A exposing (..)
import Html exposing (button, text)

view = button [] [ text "Save" ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "matches the real ComponentRegistry.elm call-site shape" <|
            \() ->
                """module A exposing (..)
import Html exposing (button, text)
import Html.Attributes
import Html.Events exposing (onClick)
import Ui

view nodeType =
    button
        [ Ui.iconButton
        , onClick DeleteLayoutNode
        , Html.Attributes.attribute "aria-label" ("Remove this " ++ nodeType)
        , Html.Attributes.title ("Remove this " ++ nodeType)
        ]
        [ text "×" ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        ]
