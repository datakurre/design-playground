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
        ]
