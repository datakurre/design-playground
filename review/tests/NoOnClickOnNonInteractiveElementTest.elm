module NoOnClickOnNonInteractiveElementTest exposing (all)

import NoOnClickOnNonInteractiveElement exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "NoOnClickOnNonInteractiveElement"
        [ test "reports onClick on a div" <|
            \() ->
                """module A exposing (..)
import Html exposing (div, text)
import Html.Events exposing (onClick)

view = div [ onClick Clicked ] [ text "Go" ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "onClick on a non-interactive <div>"
                            , details =
                                [ "Every click handler elsewhere in this app sits on a Html.button or Html.a, which is what makes it keyboard-reachable and gives assistive tech a native role. Use a button or a link here instead of onClick on a div."
                                ]
                            , under = "div [ onClick Clicked ] [ text \"Go\" ]"
                            }
                        ]
        , test "reports onClick on a span, li and ul too" <|
            \() ->
                """module A exposing (..)
import Html exposing (li, span, text, ul)
import Html.Events exposing (onClick)

view =
    [ span [ onClick Clicked ] [ text "a" ]
    , li [ onClick Clicked ] [ text "b" ]
    , ul [ onClick Clicked ] [ text "c" ]
    ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "onClick on a non-interactive <span>"
                            , details =
                                [ "Every click handler elsewhere in this app sits on a Html.button or Html.a, which is what makes it keyboard-reachable and gives assistive tech a native role. Use a button or a link here instead of onClick on a span."
                                ]
                            , under = "span [ onClick Clicked ] [ text \"a\" ]"
                            }
                        , Review.Test.error
                            { message = "onClick on a non-interactive <li>"
                            , details =
                                [ "Every click handler elsewhere in this app sits on a Html.button or Html.a, which is what makes it keyboard-reachable and gives assistive tech a native role. Use a button or a link here instead of onClick on a li."
                                ]
                            , under = "li [ onClick Clicked ] [ text \"b\" ]"
                            }
                        , Review.Test.error
                            { message = "onClick on a non-interactive <ul>"
                            , details =
                                [ "Every click handler elsewhere in this app sits on a Html.button or Html.a, which is what makes it keyboard-reachable and gives assistive tech a native role. Use a button or a link here instead of onClick on a ul."
                                ]
                            , under = "ul [ onClick Clicked ] [ text \"c\" ]"
                            }
                        ]
        , test "does not report onClick on a button" <|
            \() ->
                """module A exposing (..)
import Html exposing (button, text)
import Html.Events exposing (onClick)

view = button [ onClick Clicked ] [ text "Go" ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "does not report a div with no onClick" <|
            \() ->
                """module A exposing (..)
import Html exposing (div, text)

view = div [] [ text "Go" ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        ]
