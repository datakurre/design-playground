module ScreensTest exposing (suite)

import Expect
import Dict
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
        ]
