module Auth exposing (User, fetchProfile, loginUrl, parseToken, userDecoder)

import Http
import Json.Decode as Decode exposing (Decoder)
import Url exposing (Url)



-- OAUTH CONFIGURATION


clientId : String
clientId =
    "YOUR_GITLAB_CLIENT_ID"


redirectUri : String
redirectUri =
    -- Replace with your actual development server or production URL
    "http://localhost:5173/"


gitlabAuthorizeUrl : String
gitlabAuthorizeUrl =
    "https://gitlab.com/oauth/authorize"


loginUrl : String
loginUrl =
    gitlabAuthorizeUrl
        ++ "?client_id="
        ++ clientId
        ++ "&redirect_uri="
        ++ Url.percentEncode redirectUri
        ++ "&response_type=token"
        ++ "&state=design-playground"
        ++ "&scope=read_user+api"



-- TOKEN PARSING


{-| Parses the access\_token from the URL hash fragment.
OAuth implicit grant returns the token in the format:
#access\_token=xyz&token\_type=bearer&expires\_in=...
-}
parseToken : Url -> Maybe String
parseToken url =
    case url.fragment of
        Just fragment ->
            fragment
                -- Split by '&' to get key-value pairs
                |> String.split "&"
                -- Find the one starting with "access_token="
                |> List.filter (String.startsWith "access_token=")
                |> List.head
                -- Extract the value after '='
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
