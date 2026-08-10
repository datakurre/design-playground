module GitLab.Request exposing
    ( Request, Body(..)
    , authorized, bodyValue
    , toCmd
    )

{-| A GitLab call described as data rather than issued as a `Cmd`.

The point is testability. A `Cmd` is opaque: given one, a test can say nothing
about which endpoint was called, on which branch, or with what content. Nor does
returning `Http.Body` help — it is opaque too, and there is no
`Http.bodyToString`. So the body travels as the `Json.Encode.Value` it was built
from, which a test reads back with `Decode.decodeValue`.

That is what makes the decisions in `Update` checkable: whether a save became a
`create` or an `update`, which file path it wrote, and which branch it committed
to. All of those live in the request body and were unverifiable before.

`toCmd` is the only place `Http.request` is called.


# The description

@docs Request, Body


# Building one

@docs authorized, bodyValue


# Issuing one

@docs toCmd

-}

import Http
import Json.Encode as Encode


{-| Note `expect` carries a function, so a `Request` is not comparable — `==` on
one throws at runtime. Assert on `.method`, `.url`, `.headers` and `.body`
instead.
-}
type alias Request msg =
    { method : String
    , url : String
    , headers : List ( String, String )
    , body : Body
    , expect : Http.Expect msg
    }


{-| `FormBody` exists for the OAuth token exchange, which is the one call that
posts `application/x-www-form-urlencoded` rather than JSON.
-}
type Body
    = EmptyBody
    | JsonBody Encode.Value
    | FormBody String


{-| The bearer header every call but the token exchange carries.

Headers are pairs rather than a bare `token` field because `Auth.exchangeToken`
sends no bearer token at all, and a `token : String` field would have forced it
to pass a lie.

-}
authorized : String -> List ( String, String )
authorized token =
    [ ( "Authorization", "Bearer " ++ token ) ]


{-| The JSON a request is sending, for tests to decode. `Nothing` for the bodies
that are not JSON.
-}
bodyValue : Body -> Maybe Encode.Value
bodyValue body =
    case body of
        JsonBody value ->
            Just value

        EmptyBody ->
            Nothing

        FormBody _ ->
            Nothing


{-| -}
toCmd : Request msg -> Cmd msg
toCmd request =
    Http.request
        { method = request.method
        , headers = List.map (\( key, value ) -> Http.header key value) request.headers
        , url = request.url
        , body =
            case request.body of
                EmptyBody ->
                    Http.emptyBody

                JsonBody value ->
                    Http.jsonBody value

                FormBody raw ->
                    Http.stringBody "application/x-www-form-urlencoded" raw
        , expect = request.expect
        , timeout = Nothing
        , tracker = Nothing
        }
