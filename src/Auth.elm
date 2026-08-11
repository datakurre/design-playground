module Auth exposing
    ( Config
    , Session
    , User
    , exchangeToken
    , fetchProfile
    , loginUrl
    , parseCallback
    , refreshToken
    , sessionDecoder
    , userDecoder
    )

import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Decode as Decode exposing (Decoder)
import Url exposing (Url)



-- OAUTH CONFIGURATION


{-| Where this deployment's OAuth application lives.

These four used to be module-level constants, with `redirectUri` hardcoded to
the maintainer's GitHub Pages origin and a comment reading "Replace with your
actual development server or production URL" that nobody could act on without
editing and rebuilding. The practical consequence was that sign-in only ever
worked on one deployment: running the app locally could not complete the flow
at all, because GitLab redirects to whatever the client registered, not to
where the request came from.

They now come in through `Flags`, which `src/main.js` fills from Vite
environment variables. See `.env.example`.

`state` is per-attempt and random. It was the constant string
`"design-playground"` and was never read back — a CSRF defence in shape only.

-}
type alias Config =
    { clientId : String
    , redirectUri : String
    , scope : String
    , state : String
    }


gitlabAuthorizeUrl : String
gitlabAuthorizeUrl =
    "https://gitlab.com/oauth/authorize"


loginUrl : Config -> String -> String
loginUrl config challenge =
    gitlabAuthorizeUrl
        ++ "?client_id="
        ++ Url.percentEncode config.clientId
        ++ "&redirect_uri="
        ++ Url.percentEncode config.redirectUri
        ++ "&response_type=code"
        ++ "&state="
        ++ Url.percentEncode config.state
        ++ "&scope="
        ++ Url.percentEncode config.scope
        ++ "&code_challenge="
        ++ challenge
        ++ "&code_challenge_method=S256"



-- CALLBACK PARSING


{-| The authorization code from the callback URL, but only if the `state` that
came back is the one we sent.

Both halves used to be wrong. The old `parseCode` split the whole query on `=`
and took the second piece, so any code containing an `=` — which is legal, and
which base64url padding produces — was silently truncated to its first
fragment, and nothing percent-decoded what was left. And `state` was never
looked at, so the callback would accept a code from anywhere.

`Nothing` covers all of "no code", "no state", "wrong state" deliberately: to a
caller they are the same instruction, which is not to exchange anything.

-}
parseCallback : Config -> Url -> Maybe String
parseCallback config url =
    case url.query of
        Just query ->
            let
                params =
                    query
                        |> String.split "&"
                        |> List.filterMap parseParam
            in
            case ( lookup "state" params, lookup "code" params ) of
                ( Just returnedState, Just code ) ->
                    if returnedState == config.state then
                        Just code

                    else
                        Nothing

                _ ->
                    Nothing

        Nothing ->
            Nothing


{-| One `key=value` pair, split on the _first_ `=` only, with both halves
percent-decoded. A value may legitimately contain further `=`.
-}
parseParam : String -> Maybe ( String, String )
parseParam pair =
    case String.indexes "=" pair |> List.head of
        Just idx ->
            Maybe.map2 Tuple.pair
                (percentDecode (String.left idx pair))
                (percentDecode (String.dropLeft (idx + 1) pair))

        Nothing ->
            Nothing


{-| Query strings encode a space as `+` as well as `%20`, and `Url.percentDecode`
only knows the second spelling.
-}
percentDecode : String -> Maybe String
percentDecode =
    String.replace "+" " " >> Url.percentDecode


lookup : String -> List ( String, String ) -> Maybe String
lookup key =
    List.filter (\( k, _ ) -> k == key) >> List.head >> Maybe.map Tuple.second



-- GITLAB USER PROFILE


type alias User =
    { id : Int
    , username : String
    , name : String
    , avatarUrl : String
    }


userDecoder : Decoder User
userDecoder =
    Decode.map4 User
        (Decode.field "id" Decode.int)
        (Decode.field "username" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "avatar_url" Decode.string)



-- TOKENS


{-| Everything the token endpoint hands back that is worth keeping.

Only `access_token` used to be decoded. Expiry was therefore discovered rather
than known — by a 401 on `GET /user`, and only there, so a 401 on a commit
reported "Couldn't save to GitLab" and left the user re-clicking Save against a
token that would never work again.

`expiresIn` is seconds from now, as GitLab sends it; the caller turns it into a
deadline, because only the caller knows what "now" is.

-}
type alias Session =
    { accessToken : String
    , refreshToken : Maybe String
    , expiresIn : Maybe Int
    }


sessionDecoder : Decoder Session
sessionDecoder =
    Decode.map3 Session
        (Decode.field "access_token" Decode.string)
        (Decode.maybe (Decode.field "refresh_token" Decode.string))
        (Decode.maybe (Decode.field "expires_in" Decode.int))



-- API REQUESTS


{-| Fetches the current authenticated user's profile from GitLab API.
-}
fetchProfile : String -> (Result Http.Error User -> msg) -> Request msg
fetchProfile token toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/user"
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg userDecoder
    }


{-| Exchanges an authorization code for an access token.
-}
exchangeToken : Config -> String -> String -> (Result Http.Error Session -> msg) -> Request msg
exchangeToken config code verifier toMsg =
    { method = "POST"
    , url = "https://gitlab.com/oauth/token"

    -- The one call with no bearer token: this is what obtains it.
    , headers = []
    , body =
        FormBody
            (formEncode
                [ ( "client_id", config.clientId )
                , ( "code", code )
                , ( "grant_type", "authorization_code" )
                , ( "redirect_uri", config.redirectUri )
                , ( "code_verifier", verifier )
                ]
            )
    , expect = Http.expectJson toMsg sessionDecoder
    }


{-| Trades a refresh token for a fresh access token.

GitLab rotates refresh tokens, so the response's `refresh_token` replaces the
one that was sent rather than supplementing it.

-}
refreshToken : Config -> String -> (Result Http.Error Session -> msg) -> Request msg
refreshToken config refresh toMsg =
    { method = "POST"
    , url = "https://gitlab.com/oauth/token"
    , headers = []
    , body =
        FormBody
            (formEncode
                [ ( "client_id", config.clientId )
                , ( "refresh_token", refresh )
                , ( "grant_type", "refresh_token" )
                , ( "redirect_uri", config.redirectUri )
                ]
            )
    , expect = Http.expectJson toMsg sessionDecoder
    }


{-| Interpolating these raw was survivable only because every value happened to
be URL-safe. A client id or redirect URI now comes from configuration, so that
is no longer something this module gets to assume.
-}
formEncode : List ( String, String ) -> String
formEncode =
    List.map (\( k, v ) -> Url.percentEncode k ++ "=" ++ Url.percentEncode v)
        >> String.join "&"
