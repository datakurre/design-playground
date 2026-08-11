port module Ports exposing (cacheSession, clearToken, schemaValidationResult, validateSchema)

import Json.Decode
import Json.Encode


{-| This module defines the JavaScript interop ports for managing the OAuth
session in the browser's localStorage.

The refresh token travels with the access token because storing one without the
other makes renewal impossible: the app would hold a credential it knows is
about to expire and no way to replace it.

-}
port cacheSession : { accessToken : String, refreshToken : Maybe String, expiresIn : Maybe Int } -> Cmd msg


port clearToken : () -> Cmd msg


port validateSchema : { schema : String, data : Json.Encode.Value, context : Json.Encode.Value } -> Cmd msg


port schemaValidationResult : ({ valid : Bool, errors : List String, context : Json.Decode.Value } -> msg) -> Sub msg
