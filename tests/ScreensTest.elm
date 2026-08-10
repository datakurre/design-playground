module ScreensTest exposing (suite)

import Dict
import Expect
import Json.Decode as Decode
import Screens exposing (Screen, ScreenNode(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Screens Codecs"
        [ test "decodes and encodes a Screen accurately" <|
            \_ ->
                let
                    screen : Screen
                    screen =
                        { name = "Home Page"
                        , path = "/"
                        , root =
                            Container
                                { direction = "column"
                                , styles = Dict.fromList [ ( "padding", "1rem" ) ]
                                }
                                [ ComponentInstance
                                    { componentName = "Header"
                                    , variant = Just "primary"
                                    , state = Nothing
                                    , slots =
                                        [ ( "title", [ TextNode "Welcome" ] ) ]
                                    }
                                ]
                        }

                    encoded =
                        Screens.encoder screen

                    decoded =
                        Decode.decodeValue Screens.decoder encoded
                in
                Expect.equal (Ok screen) decoded
        , describe "formsCycle"
            [ test "a screen that includes itself is a loop" <|
                \_ ->
                    Expect.equal True
                        (Screens.formsCycle library [ "Shell" ] (screenInstance "Shell"))
            , test "a loop through a screen in between is still a loop" <|
                \_ ->
                    -- Shell contains Page, so putting Shell inside Page closes
                    -- the ring one screen further out.
                    Expect.equal True
                        (Screens.formsCycle library [ "Page" ] (screenInstance "Shell"))
            , test "including a screen that doesn't come back is not a loop" <|
                \_ ->
                    Expect.equal False
                        (Screens.formsCycle library [ "Shell" ] (screenInstance "Footer"))
            , test "a screen that isn't in the library can't be followed, so it isn't a loop" <|
                \_ ->
                    Expect.equal False
                        (Screens.formsCycle library [ "Shell" ] (screenInstance "Missing"))
            , test "a component is never a loop" <|
                \_ ->
                    Expect.equal False
                        (Screens.formsCycle library
                            [ "Shell" ]
                            (ComponentInstance { componentName = "Button", variant = Nothing, state = Nothing, slots = [] })
                        )
            ]
        ]


{-| Shell contains Page, Page contains Footer, Footer contains nothing.
-}
library : Dict.Dict String Screen
library =
    [ ( "Shell", screenInstance "Page" )
    , ( "Page", screenInstance "Footer" )
    , ( "Footer", TextNode "fin" )
    ]
        |> List.map
            (\( name, child ) ->
                ( name
                , { name = name
                  , path = "/" ++ name
                  , root = Container { direction = "column", styles = Dict.empty } [ child ]
                  }
                )
            )
        |> Dict.fromList


screenInstance : String -> ScreenNode
screenInstance name =
    ScreenInstance { screenName = name }
