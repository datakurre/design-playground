module TokensTest exposing (..)

import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (..)
import Tokens exposing (AstNode(..))


astTests : Test
astTests =
    describe "Tokens AST and Flattening"
        [ test "flattenAst converts AstNode to List FlatToken" <|
            \_ ->
                let
                    ast =
                        GroupNode
                            (Dict.fromList
                                [ ( "color"
                                  , GroupNode
                                        (Dict.fromList
                                            [ ( "primary", TokenNode { value = "#ff0000", type_ = "color", description = Nothing } )
                                            ]
                                        )
                                  )
                                ]
                            )

                    expected =
                        [ ( [ "color", "primary" ], { value = "#ff0000", type_ = "color", description = Nothing } ) ]
                in
                Expect.equal expected (Tokens.flattenAst ast)
        , test "buildAst converts List FlatToken back to AstNode" <|
            \_ ->
                let
                    flatTokens =
                        [ ( [ "spacing", "small" ], { value = "8px", type_ = "dimension", description = Just "Small spacing" } ) ]

                    expected =
                        GroupNode
                            (Dict.fromList
                                [ ( "spacing"
                                  , GroupNode
                                        (Dict.fromList
                                            [ ( "small", TokenNode { value = "8px", type_ = "dimension", description = Just "Small spacing" } )
                                            ]
                                        )
                                  )
                                ]
                            )
                in
                Expect.equal expected (Tokens.buildAst flatTokens)
        ]


decoderTests : Test
decoderTests =
    describe "Tokens JSON Decoders"
        [ test "decodes simple W3C token JSON to flat tokens" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "color": {
                                "background": {
                                    "$value": "#ffffff",
                                    "$type": "color"
                                }
                            }
                        }
                        """

                    expected =
                        Ok [ ( [ "color", "background" ], { value = "#ffffff", type_ = "color", description = Nothing } ) ]
                in
                Expect.equal expected (Decode.decodeString Tokens.decoder json)
        , test "decodes token with description" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "font": {
                                "base": {
                                    "$value": "16px",
                                    "$type": "dimension",
                                    "$description": "Base font size"
                                }
                            }
                        }
                        """

                    expected =
                        Ok [ ( [ "font", "base" ], { value = "16px", type_ = "dimension", description = Just "Base font size" } ) ]
                in
                Expect.equal expected (Decode.decodeString Tokens.decoder json)
        , test "encodes flat tokens back to W3C token JSON" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "text" ], { value = "#333333", type_ = "color", description = Nothing } ) ]

                    encoded =
                        Encode.encode 0 (Tokens.encoder tokens)

                    expectedJson =
                        """{"color":{"text":{"$value":"#333333","$type":"color"}}}"""
                in
                Expect.equal expectedJson encoded
        ]


aliasTests : Test
aliasTests =
    describe "Alias Resolution"
        [ test "resolves simple alias" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "primary" ], { value = "#ff0000", type_ = "color", description = Nothing } )
                        , ( [ "button", "bg" ], { value = "{color.primary}", type_ = "color", description = Nothing } )
                        ]
                in
                Expect.equal "#ff0000" (Tokens.resolveAlias tokens "{color.primary}")
        , test "resolves nested alias" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "red", "500" ], { value = "#ff0000", type_ = "color", description = Nothing } )
                        , ( [ "color", "primary" ], { value = "{color.red.500}", type_ = "color", description = Nothing } )
                        , ( [ "button", "bg" ], { value = "{color.primary}", type_ = "color", description = Nothing } )
                        ]
                in
                Expect.equal "#ff0000" (Tokens.resolveAlias tokens "{button.bg}")
        , test "returns raw value if alias not found" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "primary" ], { value = "#ff0000", type_ = "color", description = Nothing } ) ]
                in
                Expect.equal "{color.secondary}" (Tokens.resolveAlias tokens "{color.secondary}")
        ]
