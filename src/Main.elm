module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Html exposing (Html, text, div, h1, a)
import Html.Attributes exposing (href)
import Url exposing (Url)


-- MAIN

main : Program () Model Msg
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

type alias Model =
    { key : Nav.Key
    , url : Url
    }


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key, url = url }
    , Cmd.none
    )


-- UPDATE

type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | url = url }
            , Cmd.none
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
        [ div []
            [ h1 [] [ text "Design Playground SPA" ]
            , div [] [ text ("Current URL: " ++ Url.toString model.url) ]
            , div []
                [ a [ href "/" ] [ text "Home" ]
                , text " | "
                , a [ href "/about" ] [ text "About" ]
                ]
            ]
        ]
    }
