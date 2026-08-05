module Auth exposing (User, exchangeToken, fetchProfile, loginUrl, parseCode, userDecoder)

import Http
import Json.Decode as Decode exposing (Decoder)
import Url exposing (Url)



-- OAUTH CONFIGURATION


clientId : String
clientId =
    "920996e8589eec6aa245fbdb099e346fa3aefd56c3b9795f94ea9ea9b61018bd"


redirectUri : String
redirectUri =
    -- Replace with your actual development server or production URL
    "https://datakurre.github.io/design-playground"


gitlabAuthorizeUrl : String
gitlabAuthorizeUrl =
    "https://gitlab.com/oauth/authorize"


loginUrl : String -> String
loginUrl challenge =
    gitlabAuthorizeUrl
        ++ "?client_id="
        ++ clientId
        ++ "&redirect_uri="
        ++ Url.percentEncode redirectUri
        ++ "&response_type=code"
        ++ "&state=design-playground"
        ++ "&scope=read_user+api"
        ++ "&code_challenge="
        ++ challenge
        ++ "&code_challenge_method=S256"



-- TOKEN PARSING


{-| Parses the access\_token from the URL hash fragment.
OAuth implicit grant returns the token in the format:
#access\_token=xyz&token\_type=bearer&expires\_in=...
-}
parseCode : Url -> Maybe String
parseCode url =
    case url.query of
        Just query ->
            query
                |> String.split "&"
                |> List.filter (String.startsWith "code=")
                |> List.head
                |> Maybe.andThen (String.split "=" >> List.drop 1 >> List.head)

        Nothing ->
            Nothing



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



-- API REQUESTS


{-| Fetches the current authenticated user's profile from GitLab API.
-}
fetchProfile : String -> (Result Http.Error User -> msg) -> Cmd msg
fetchProfile token toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/user"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg userDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Exchanges an authorization code for an access token.
-}
exchangeToken : String -> String -> (Result Http.Error String -> msg) -> Cmd msg
exchangeToken code verifier toMsg =
    let
        body =
            "client_id="
                ++ clientId
                ++ "&code="
                ++ code
                ++ "&grant_type=authorization_code"
                ++ "&redirect_uri="
                ++ Url.percentEncode redirectUri
                ++ "&code_verifier="
                ++ verifier
    in
    Http.post
        { url = "https://gitlab.com/oauth/token"
        , body = Http.stringBody "application/x-www-form-urlencoded" body
        , expect = Http.expectJson toMsg (Decode.field "access_token" Decode.string)
        }
