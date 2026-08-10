port module Ports exposing (cacheToken, clearToken, schemaValidationResult, validateSchema)

import Json.Decode
import Json.Encode


{-| This module defines the JavaScript interop ports for managing the OAuth token
in the browser's localStorage.
-}
port cacheToken : String -> Cmd msg


port clearToken : () -> Cmd msg


port validateSchema : { schema : String, data : Json.Encode.Value, context : Json.Encode.Value } -> Cmd msg


port schemaValidationResult : ({ valid : Bool, errors : List String, context : Json.Decode.Value } -> msg) -> Sub msg
