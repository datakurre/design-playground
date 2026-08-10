module RouteTest exposing (suite)

import Expect
import Route exposing (Route(..), TabRoute(..))
import Test exposing (Test, describe, test)
import Types exposing (Tab(..))
import Url


{-| The routes are how a repository, a tab and a selection survive a refresh, so
what matters is that `parse` and `toString` agree: anything the app writes into
the address bar has to read back as the thing it was written from.

Routing lives in the URL fragment, so these build a URL with a path of
`/design-playground/` — the subpath the app is actually deployed under — to keep
the tests honest about the base path being irrelevant.

-}
suite : Test
suite =
    describe "Route"
        [ describe "round-trips through the address bar"
            (List.map roundTrips
                [ Home
                , Repo "acme/design" TokensTab
                , Repo "acme/design" (ComponentsTab Nothing)
                , Repo "acme/design" (ComponentsTab (Just "Button"))
                , Repo "acme/design" (ScreensTab Nothing)
                , Repo "acme/design" (ScreensTab (Just "Checkout"))
                , Repo "acme/design" GitWorkflowsTab
                , Repo "acme/design" ExportPipelineTab

                -- A namespace can be a nested group, so a project path is not
                -- always two segments.
                , Repo "acme/platform/design" (ComponentsTab (Just "Button"))
                ]
            )
        , describe "names that aren't URL-safe"
            (List.map roundTrips
                [ Repo "acme/design" (ComponentsTab (Just "Icon Button"))
                , Repo "acme/design" (ComponentsTab (Just "Nav/Item"))
                , Repo "acme/design" (ComponentsTab (Just "Heading #1"))
                , Repo "acme/design" (ScreensTab (Just "Sign in / up"))
                , Repo "acme/design" (ScreensTab (Just "100% width"))
                ]
            )
        , describe "reading URLs"
            [ test "the bare entry URL is Home, not a repository called after the base path" <|
                \_ ->
                    -- Before routing moved into the fragment, going Back to the
                    -- page you arrived on parsed the deploy subpath as a
                    -- project and tried to fetch it.
                    Expect.equal (Just Home) (Route.parse (url Nothing))
            , test "an empty fragment is Home" <|
                \_ ->
                    Expect.equal (Just Home) (Route.parse (url (Just "")))
            , test "a project with no tab opens on tokens" <|
                \_ ->
                    Expect.equal
                        (Just (Repo "acme/design" TokensTab))
                        (Route.parse (url (Just "/acme/design")))
            , test "a project whose own last segment is a tab word is still the project" <|
                \_ ->
                    -- `export` here can't be the tab: nothing would be left to
                    -- name the project.
                    Expect.equal
                        (Just (Repo "acme/export" TokensTab))
                        (Route.parse (url (Just "/acme/export")))
            , test "the same word one segment later is the tab" <|
                \_ ->
                    Expect.equal
                        (Just (Repo "acme/design" ExportPipelineTab))
                        (Route.parse (url (Just "/acme/design/export")))
            , test "a component named after a tab word is a component" <|
                \_ ->
                    Expect.equal
                        (Just (Repo "acme/design" (ComponentsTab (Just "tokens"))))
                        (Route.parse (url (Just "/acme/design/components/tokens")))
            , test "one segment can't name a project, so it isn't a route" <|
                \_ ->
                    Expect.equal Nothing (Route.parse (url (Just "/design-playground")))
            , test "trailing and doubled slashes don't change the route" <|
                \_ ->
                    Expect.equal
                        (Just (Repo "acme/design" TokensTab))
                        (Route.parse (url (Just "//acme//design//tokens/")))
            ]
        , describe "writing URLs"
            [ test "routes are written into the fragment, so the deploy subpath is left alone" <|
                \_ ->
                    Expect.equal
                        "#/acme/design/components/Button"
                        (Route.toString (Repo "acme/design" (ComponentsTab (Just "Button"))))
            , test "a slash in a name is escaped rather than becoming a separator" <|
                \_ ->
                    Expect.equal
                        "#/acme/design/components/Nav%2FItem"
                        (Route.toString (Repo "acme/design" (ComponentsTab (Just "Nav/Item"))))
            ]
        , describe "tabs"
            [ test "every tab has a route, and it leads back to that tab" <|
                \_ ->
                    let
                        tabs =
                            [ TokenStudio, ComponentRegistry, ScreenComposer, GitWorkflows, ExportPipeline ]
                    in
                    Expect.equal tabs
                        (List.map (\t -> Route.toTab (Route.tabRouteFor t Nothing Nothing)) tabs)
            , test "the components tab carries the selected component" <|
                \_ ->
                    Expect.equal
                        (ComponentsTab (Just "Button"))
                        (Route.tabRouteFor ComponentRegistry (Just "Button") (Just "Checkout"))
            , test "the screens tab carries the selected screen" <|
                \_ ->
                    Expect.equal
                        (ScreensTab (Just "Checkout"))
                        (Route.tabRouteFor ScreenComposer (Just "Button") (Just "Checkout"))
            ]
        ]


{-| `toString` then `parse` has to be the identity, which is what lets the app
put a route in the address bar and get the same one back on reload.
-}
roundTrips : Route -> Test
roundTrips route =
    test (Route.toString route) <|
        \_ ->
            Expect.equal (Just route) (Route.parse (url (Just (fragmentOf (Route.toString route)))))


fragmentOf : String -> String
fragmentOf written =
    String.dropLeft 1 written


{-| The app is served from a subpath, and every route has to survive that.
-}
url : Maybe String -> Url.Url
url fragment =
    { protocol = Url.Https
    , host = "datakurre.github.io"
    , port_ = Nothing
    , path = "/design-playground/"
    , query = Nothing
    , fragment = fragment
    }
