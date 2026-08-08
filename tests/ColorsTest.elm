module ColorsTest exposing (suite)

import Colors exposing (contrastRatio, parseHex)
import Expect
import Test exposing (..)


suite : Test
suite =
    describe "Colors module"
        [ describe "parseHex"
            [ test "parses 3-digit hex #fff" <|
                \_ ->
                    parseHex "#fff"
                        |> Expect.equal (Just { r = 255, g = 255, b = 255 })
            , test "parses 6-digit hex #ffffff" <|
                \_ ->
                    parseHex "#ffffff"
                        |> Expect.equal (Just { r = 255, g = 255, b = 255 })
            , test "parses #000" <|
                \_ ->
                    parseHex "#000"
                        |> Expect.equal (Just { r = 0, g = 0, b = 0 })
            , test "parses #3366CC (case-insensitive)" <|
                \_ ->
                    parseHex "#3366CC"
                        |> Expect.equal (Just { r = 51, g = 102, b = 204 })
            , test "returns Nothing for not-a-color" <|
                \_ ->
                    parseHex "not-a-color"
                        |> Expect.equal Nothing
            , test "returns Nothing for #12" <|
                \_ ->
                    parseHex "#12"
                        |> Expect.equal Nothing
            , test "returns Nothing for #12345" <|
                \_ ->
                    parseHex "#12345"
                        |> Expect.equal Nothing
            ]
        , describe "contrastRatio"
            [ test "black and white contrast is approximately 21.0" <|
                \_ ->
                    contrastRatio { r = 0, g = 0, b = 0 } { r = 255, g = 255, b = 255 }
                        |> Expect.within (Expect.Absolute 0.05) 21.0
            , test "contrastRatio is symmetric" <|
                \_ ->
                    contrastRatio { r = 255, g = 255, b = 255 } { r = 0, g = 0, b = 0 }
                        |> Expect.within (Expect.Absolute 0.05) 21.0
            , test "white and white contrast is approximately 1.0" <|
                \_ ->
                    contrastRatio { r = 255, g = 255, b = 255 } { r = 255, g = 255, b = 255 }
                        |> Expect.within (Expect.Absolute 0.05) 1.0
            ]
        ]
