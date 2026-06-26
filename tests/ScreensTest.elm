module ScreensTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
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
                                , padding = Just "1rem"
                                , gap = Nothing
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
