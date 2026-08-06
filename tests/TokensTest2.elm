module TokensTest2 exposing (..)

import Expect
import Json.Encode as Encode
import Test exposing (..)
import Tokens exposing (TokenValue(..))

testEncoder : Test
testEncoder =
    test "encodes multiple tokens with same prefix" <|
        \_ ->
            let
                tokens =
                    [ ( [ "color", "primary" ], { value = StringValue "red", type_ = "color", description = Nothing } )
                    , ( [ "color", "secondary" ], { value = StringValue "blue", type_ = "color", description = Nothing } )
                    ]

                encoded =
                    Encode.encode 0 (Tokens.encoder tokens)

                expectedJson =
                    """{"color":{"primary":{"$value":"red","$type":"color"},"secondary":{"$value":"blue","$type":"color"}}}"""
            in
            Expect.equal expectedJson encoded
