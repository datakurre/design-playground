module FixturesTest exposing (suite)

{-| Half of the round trip that connects the Elm codecs to the JSON Schemas.

Here: each fixture in `Fixtures` decodes, and re-encoding it reproduces the
fixture byte for byte. In `tests/schemas.test.js`: those same strings, read out
of `Fixtures.elm`, validate against `schemas/`.

So an encoder that gains a field fails here until the fixture is updated, and
the updated fixture then fails over there until the schema is too. Neither
suite could see the other before, and the gap is where
`"rules": {"type": "object"}` survived — validating nothing, letting a
malformed rule commit and then vanish on load.

-}

import Components
import Contracts
import Expect
import Fixtures
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Screens
import Test exposing (Test, describe, test)
import Tokens


suite : Test
suite =
    describe "fixtures are exactly what the encoders write"
        [ test "tokens" <|
            \_ -> expectRoundTrip Tokens.decoder Tokens.encoder Fixtures.tokens
        , test "component" <|
            \_ -> expectRoundTrip Components.decoder Components.encoder Fixtures.component
        , test "screen" <|
            \_ -> expectRoundTrip Screens.decoder Screens.encoder Fixtures.screen
        , test "contract" <|
            \_ -> expectRoundTrip Contracts.decoder Contracts.encoder Fixtures.contract
        ]


{-| Indentation is 4 because that is what `Encode.encode 4` writes, and the
fixture has to be the encoder's own output rather than something equivalent to
it — otherwise "the schema validates what we write" is only true of a file
nobody writes.

The app itself saves with `Encode.encode 2`; indentation is the one difference,
and it is not something a JSON Schema can see.

-}
expectRoundTrip : Decoder a -> (a -> Value) -> String -> Expect.Expectation
expectRoundTrip decoder encoder fixture =
    case Decode.decodeString decoder fixture of
        Ok value ->
            Encode.encode 4 (encoder value)
                |> Expect.equal fixture

        Err error ->
            Expect.fail (Decode.errorToString error)
