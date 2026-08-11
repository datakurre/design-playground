module TokensTest exposing (..)

import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (..)
import Tokens exposing (AstNode(..), TokenValue(..))


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
                                            [ ( "primary", TokenNode { value = StringValue "#ff0000", type_ = "color", description = Nothing } )
                                            ]
                                        )
                                  )
                                ]
                            )

                    expected =
                        [ ( [ "color", "primary" ], { value = StringValue "#ff0000", type_ = "color", description = Nothing } ) ]
                in
                Expect.equal expected (Tokens.flattenAst ast)
        , test "buildAst converts List FlatToken back to AstNode" <|
            \_ ->
                let
                    flatTokens =
                        [ ( [ "spacing", "small" ], { value = StringValue "8px", type_ = "dimension", description = Just "Small spacing" } ) ]

                    expected =
                        GroupNode
                            (Dict.fromList
                                [ ( "spacing"
                                  , GroupNode
                                        (Dict.fromList
                                            [ ( "small", TokenNode { value = StringValue "8px", type_ = "dimension", description = Just "Small spacing" } )
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
                        Ok [ ( [ "color", "background" ], { value = StringValue "#ffffff", type_ = "color", description = Nothing } ) ]
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
                        Ok [ ( [ "font", "base" ], { value = StringValue "16px", type_ = "dimension", description = Just "Base font size" } ) ]
                in
                Expect.equal expected (Decode.decodeString Tokens.decoder json)
        , test "encodes flat tokens back to W3C token JSON" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "text" ], { value = StringValue "#333333", type_ = "color", description = Nothing } ) ]

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
                        [ ( [ "color", "primary" ], { value = StringValue "#ff0000", type_ = "color", description = Nothing } )
                        , ( [ "button", "bg" ], { value = StringValue "{color.primary}", type_ = "color", description = Nothing } )
                        ]
                in
                Expect.equal "#ff0000" (Tokens.resolveAlias tokens "{color.primary}")
        , test "resolves nested alias" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "red", "500" ], { value = StringValue "#ff0000", type_ = "color", description = Nothing } )
                        , ( [ "color", "primary" ], { value = StringValue "{color.red.500}", type_ = "color", description = Nothing } )
                        , ( [ "button", "bg" ], { value = StringValue "{color.primary}", type_ = "color", description = Nothing } )
                        ]
                in
                Expect.equal "#ff0000" (Tokens.resolveAlias tokens "{button.bg}")
        , test "returns raw value if alias not found" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "primary" ], { value = StringValue "#ff0000", type_ = "color", description = Nothing } ) ]
                in
                Expect.equal "{color.secondary}" (Tokens.resolveAlias tokens "{color.secondary}")
        , test "a cycle resolves to a marker, not to a plausible wrong value" <|
            \_ ->
                -- Running out of depth used to hand back the input unchanged,
                -- which no caller could tell apart from a resolved value. The
                -- renderer would draw it and the contract validator would judge
                -- it.
                let
                    tokens =
                        [ ( [ "a" ], { value = StringValue "{b}", type_ = "color", description = Nothing } )
                        , ( [ "b" ], { value = StringValue "{a}", type_ = "color", description = Nothing } )
                        ]
                in
                Tokens.resolveAlias tokens "{a}"
                    |> Tokens.isUnresolved
                    |> Expect.equal True
        , test "a value that fully resolves is not flagged as unresolved" <|
            \_ ->
                let
                    tokens =
                        [ ( [ "color", "primary" ], { value = StringValue "#ff0000", type_ = "color", description = Nothing } ) ]
                in
                Tokens.resolveAlias tokens "1px solid {color.primary}"
                    |> Tokens.isUnresolved
                    |> Expect.equal False
        ]
