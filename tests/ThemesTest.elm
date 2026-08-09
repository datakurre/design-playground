module ThemesTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Themes
import Tokens exposing (TokenValue(..))


base : List Tokens.FlatToken
base =
    [ ( [ "color", "bg" ], { value = StringValue "#ffffff", type_ = "color", description = Nothing } ) ]


dark : Themes.Theme
dark =
    { name = "Dark"
    , overrides = [ ( [ "color", "bg" ], { value = StringValue "#000000", type_ = "color", description = Nothing } ) ]
    }


valueOf : List Tokens.FlatToken -> Maybe TokenValue
valueOf tokens =
    tokens |> List.head |> Maybe.map (\( _, t ) -> t.value)


suite : Test
suite =
    describe "Themes.resolve"
        [ test "returns the base tokens when no theme is active" <|
            \_ ->
                Themes.resolve base [ dark ] Nothing
                    |> Expect.equal base
        , test "applies the active theme's overrides" <|
            \_ ->
                Themes.resolve base [ dark ] (Just "Dark")
                    |> valueOf
                    |> Expect.equal (Just (StringValue "#000000"))
        , test "falls back to the base tokens for an unknown theme name" <|
            \_ ->
                Themes.resolve base [ dark ] (Just "Nope")
                    |> Expect.equal base
        ]
