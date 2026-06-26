module Main exposing (main)

import Auth
import Browser
import Browser.Navigation as Nav
import Html exposing (Html, a, button, div, h1, img, text)
import Html.Attributes exposing (href, src, style)
import Html.Events exposing (onClick)
import Http
import Ports
import Url exposing (Url)



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- MODEL


type alias Flags =
    Maybe String


type alias Model =
    { key : Nav.Key
    , url : Url
    , token : Maybe String
    , user : Maybe Auth.User
    , error : Maybe String
    }


init : Flags -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        -- Check if the URL has an access token
        urlToken =
            Auth.parseToken url

        -- Determine the final token
        finalToken =
            case urlToken of
                Just t ->
                    Just t

                Nothing ->
                    flags

        initialModel =
            { key = key
            , url = url
            , token = finalToken
            , user = Nothing
            , error = Nothing
            }

        cmds =
            case urlToken of
                Just t ->
                    -- If we got the token from the URL, clear the hash and cache it
                    [ Nav.replaceUrl key (Url.toString { url | fragment = Nothing })
                    , Ports.cacheToken t
                    , Auth.fetchProfile t GotProfile
                    ]

                Nothing ->
                    case finalToken of
                        Just t ->
                            [ Auth.fetchProfile t GotProfile ]

                        Nothing ->
                            []
    in
    ( initialModel, Cmd.batch cmds )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | GotProfile (Result Http.Error Auth.User)
    | Logout


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External hrefString ->
                    ( model, Nav.load hrefString )

        UrlChanged url ->
            let
                urlToken =
                    Auth.parseToken url
            in
            case urlToken of
                Just t ->
                    ( { model | url = url, token = Just t }
                    , Cmd.batch
                        [ Nav.replaceUrl model.key (Url.toString { url | fragment = Nothing })
                        , Ports.cacheToken t
                        , Auth.fetchProfile t GotProfile
                        ]
                    )

                Nothing ->
                    ( { model | url = url }, Cmd.none )

        GotProfile result ->
            case result of
                Ok user ->
                    ( { model | user = Just user, error = Nothing }, Cmd.none )

                Err _ ->
                    -- On error (e.g., token expired), clear the token
                    ( { model | token = Nothing, user = Nothing, error = Just "Failed to fetch profile. Token may have expired." }
                    , Ports.clearToken ()
                    )

        Logout ->
            ( { model | token = Nothing, user = Nothing, error = Nothing }
            , Ports.clearToken ()
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Design Playground"
    , body =
        [ div [ style "font-family" "sans-serif", style "padding" "2rem" ]
            [ h1 [] [ text "Design Playground SPA" ]
            , viewAuth model
            , div [ style "margin-top" "2rem" ] [ text ("Current URL: " ++ Url.toString model.url) ]
            , div [ style "margin-top" "1rem" ]
                [ a [ href "/" ] [ text "Home" ]
                , text " | "
                , a [ href "/about" ] [ text "About" ]
                ]
            ]
        ]
    }


viewAuth : Model -> Html Msg
viewAuth model =
    div [ style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px", style "display" "inline-block" ]
        [ case model.error of
            Just err ->
                div [ style "color" "red", style "margin-bottom" "1rem" ] [ text err ]

            Nothing ->
                text ""
        , case model.token of
            Nothing ->
                a
                    [ href Auth.loginUrl
                    , style "display" "inline-block"
                    , style "padding" "0.5rem 1rem"
                    , style "background" "#fc6d26"
                    , style "color" "white"
                    , style "text-decoration" "none"
                    , style "border-radius" "4px"
                    , style "font-weight" "bold"
                    ]
                    [ text "Connect to GitLab" ]

            Just _ ->
                case model.user of
                    Nothing ->
                        text "Loading profile..."

                    Just user ->
                        div [ style "display" "flex", style "align-items" "center", style "gap" "1rem" ]
                            [ img [ src user.avatarUrl, style "width" "48px", style "border-radius" "50%" ] []
                            , div []
                                [ div [ style "font-weight" "bold" ] [ text user.name ]
                                , div [ style "color" "#666" ] [ text ("@" ++ user.username) ]
                                ]
                            , button
                                [ onClick Logout
                                , style "margin-left" "1rem"
                                , style "padding" "0.5rem 1rem"
                                , style "cursor" "pointer"
                                , style "background" "#f4f4f4"
                                , style "border" "1px solid #ccc"
                                , style "border-radius" "4px"
                                ]
                                [ text "Logout" ]
                            ]
        ]
