module Effect exposing
    ( Effect(..)
    , none, batch
    , perform
    , toList, requests
    )

{-| What `update` asks the runtime to do, as data.

`update` used to return a `Cmd`, which is opaque: given one, a test can say
nothing about what it does. Combined with `Nav.Key` living in the `Model` — so
no test could build a `Model` at all — that left every state transition in a
2000-line `update` with type-checking as its only feedback.

So `update` returns an `Effect`, `perform` turns it into a `Cmd`, and `perform`
is the only place `Nav.Key`, `Ports` and `Http` are touched. A test runs a
branch and reads what it asked for.

`Effect` is parametrised over `msg` so it stays a leaf module that never imports
`Types`, which forecloses an import cycle between the two.


# Effects

@docs Effect


# Building them

@docs none, batch


# Running them

@docs perform


# Inspecting them

@docs toList, requests

-}

import Browser.Navigation as Nav
import GitLab.Request exposing (Request)
import Json.Encode as Encode
import Ports


{-| **Do not `Expect.equal` a whole `Effect`.** `SendRequest` carries an
`Http.Expect`, which contains a function, and Elm's `==` throws at runtime on
functions. It works fine for `PushUrl` and the rest, which makes the failure
inconsistent and therefore surprising.

Use `requests` and assert on a request's fields; use `toList` and pattern-match
for navigation and port effects.

-}
type Effect msg
    = None
    | Batch (List (Effect msg))
    | PushUrl String
    | ReplaceUrl String
    | LoadUrl String
    | CacheToken String
    | ClearToken
    | ValidateSchema { schema : String, data : Encode.Value, context : Encode.Value }
    | SendRequest (Request msg)


{-| -}
none : Effect msg
none =
    None


{-| -}
batch : List (Effect msg) -> Effect msg
batch =
    Batch


{-| -}
perform : Nav.Key -> Effect msg -> Cmd msg
perform key effect =
    case effect of
        None ->
            Cmd.none

        Batch effects ->
            Cmd.batch (List.map (perform key) effects)

        PushUrl url ->
            Nav.pushUrl key url

        ReplaceUrl url ->
            Nav.replaceUrl key url

        LoadUrl href ->
            Nav.load href

        CacheToken token ->
            Ports.cacheToken token

        ClearToken ->
            Ports.clearToken ()

        ValidateSchema payload ->
            Ports.validateSchema payload

        SendRequest request ->
            GitLab.Request.toCmd request


{-| Flattens `Batch` and drops `None`, so a test can say what a branch did
without caring how the result was nested.
-}
toList : Effect msg -> List (Effect msg)
toList effect =
    case effect of
        None ->
            []

        Batch effects ->
            List.concatMap toList effects

        other ->
            [ other ]


{-| Every GitLab call an effect makes, in order.
-}
requests : Effect msg -> List (Request msg)
requests effect =
    toList effect
        |> List.filterMap
            (\e ->
                case e of
                    SendRequest request ->
                        Just request

                    _ ->
                        Nothing
            )
