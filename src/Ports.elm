port module Ports exposing (cacheToken, clearToken)

{-| This module defines the JavaScript interop ports for managing the OAuth token
in the browser's localStorage.
-}


port cacheToken : String -> Cmd msg


port clearToken : () -> Cmd msg
