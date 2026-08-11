module ExportTest exposing (suite)

import Expect
import Export exposing (generateCssVariables, generateTailwindConfig)
import Test exposing (Test, describe, test)
import Tokens exposing (TokenValue(..))


suite : Test
suite =
    describe "Export Pipeline Generators"
        [ test "generateCssVariables produces valid CSS" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "primary" ], { value = StringValue "#ff0000", type_ = "color", description = Nothing } )
                        , ( [ "spacing", "small" ], { value = StringValue "8px", type_ = "spacing", description = Nothing } )
                        , ( [ "color", "alias" ], { value = StringValue "{color.primary}", type_ = "color", description = Nothing } )
                        ]

                    expected =
                        """:root {
  --color-primary: #ff0000;
  --spacing-small: 8px;
  --color-alias: #ff0000;
}
"""
                in
                generateCssVariables tokens
                    |> Expect.equal expected
        , test "generateTailwindConfig produces valid JS config" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "primary" ], { value = StringValue "#ff0000", type_ = "color", description = Nothing } )
                        , ( [ "color", "secondary", "light" ], { value = StringValue "#00ff00", type_ = "color", description = Nothing } )
                        , ( [ "spacing", "small" ], { value = StringValue "8px", type_ = "spacing", description = Nothing } )
                        ]

                    expected =
                        """module.exports = {
  theme: {
    extend: {
      colors: {
        'primary': '#ff0000',
        'secondary-light': '#00ff00'
      }
    }
  }
};
"""
                in
                generateTailwindConfig tokens
                    |> Expect.equal expected
        , describe "escaping"
            [ test "a token value can't end the CSS declaration early" <|
                \_ ->
                    -- Both generators build their output by concatenation, and
                    -- both read a repository someone else can write to. Without
                    -- this the file isn't broken, it just says something the
                    -- author didn't write.
                    let
                        tokens =
                            [ ( [ "color", "evil" ]
                              , { value = StringValue "red; } body { display: none; "
                                , type_ = "color"
                                , description = Nothing
                                }
                              )
                            ]
                    in
                    generateCssVariables tokens
                        |> Expect.equal ":root {\n  --color-evil: red  body  display: none;\n}\n"
            , test "a token value can't close the JS string literal" <|
                \_ ->
                    let
                        tokens =
                            [ ( [ "color", "evil" ]
                              , { value = StringValue "#fff', evil: require('child_process"
                                , type_ = "color"
                                , description = Nothing
                                }
                              )
                            ]
                    in
                    generateTailwindConfig tokens
                        |> String.contains "'evil': '#fff\\', evil: require(\\'child_process'"
                        |> Expect.equal True
            , test "a token name can't close it either" <|
                \_ ->
                    let
                        tokens =
                            [ ( [ "color", "a': x, 'b" ]
                              , { value = StringValue "#fff", type_ = "color", description = Nothing }
                              )
                            ]
                    in
                    generateTailwindConfig tokens
                        |> String.contains "'a\\': x, \\'b': '#fff'"
                        |> Expect.equal True
            , test "an ordinary value with commas and parens survives intact" <|
                \_ ->
                    -- Escaping that mangles rgb() would be its own bug.
                    let
                        tokens =
                            [ ( [ "color", "brand" ]
                              , { value = StringValue "rgb(255, 0, 0)", type_ = "color", description = Nothing }
                              )
                            ]
                    in
                    generateCssVariables tokens
                        |> Expect.equal ":root {\n  --color-brand: rgb(255, 0, 0);\n}\n"
            ]
        ]
