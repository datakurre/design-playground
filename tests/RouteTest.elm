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
                , repo "acme/design" TokensTab
                , repo "acme/design" (ComponentsTab Nothing)
                , repo "acme/design" (ComponentsTab (Just "Button"))
                , repo "acme/design" (ScreensTab Nothing)
                , repo "acme/design" (ScreensTab (Just "Checkout"))
                , repo "acme/design" GitWorkflowsTab
                , repo "acme/design" ExportPipelineTab

                -- A namespace can be a nested group, so a project path is not
                -- always two segments.
                , repo "acme/platform/design" (ComponentsTab (Just "Button"))
                ]
            )
        , describe "names that aren't URL-safe"
            (List.map roundTrips
                [ repo "acme/design" (ComponentsTab (Just "Icon Button"))
                , repo "acme/design" (ComponentsTab (Just "Nav/Item"))
                , repo "acme/design" (ComponentsTab (Just "Heading #1"))
                , repo "acme/design" (ScreensTab (Just "Sign in / up"))
                , repo "acme/design" (ScreensTab (Just "100% width"))

                -- A raw `?` is what the branch is split on, so a name that
                -- would produce one has to be escaped before it gets there.
                , repo "acme/design" (ComponentsTab (Just "Why?"))
                , repo "acme/design" (ScreensTab (Just "Sign in?next=/"))
                ]
            )
        , describe "the branch rides in the fragment"
            (List.map roundTrips
                [ onBranch "feature-x" (repo "acme/design" TokensTab)
                , onBranch "feature/new-colors" (repo "acme/design" (ComponentsTab (Just "Button")))
                , onBranch "release/1.0" (repo "acme/design" GitWorkflowsTab)

                -- Git allows both of these in a ref name, and both mean
                -- something else in a query string.
                , onBranch "a&b" (repo "acme/design" TokensTab)
                , onBranch "100%" (repo "acme/design" ExportPipelineTab)

                -- A component name and a branch name in the same URL, each
                -- escaped by a different rule.
                , onBranch "fix/nav" (repo "acme/design" (ComponentsTab (Just "Nav/Item")))
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
                        (Just (repo "acme/design" TokensTab))
                        (Route.parse (url (Just "/acme/design")))
            , test "a project whose own last segment is a tab word is still the project" <|
                \_ ->
                    -- `export` here can't be the tab: nothing would be left to
                    -- name the project.
                    Expect.equal
                        (Just (repo "acme/export" TokensTab))
                        (Route.parse (url (Just "/acme/export")))
            , test "the same word one segment later is the tab" <|
                \_ ->
                    Expect.equal
                        (Just (repo "acme/design" ExportPipelineTab))
                        (Route.parse (url (Just "/acme/design/export")))
            , test "a component named after a tab word is a component" <|
                \_ ->
                    Expect.equal
                        (Just (repo "acme/design" (ComponentsTab (Just "tokens"))))
                        (Route.parse (url (Just "/acme/design/components/tokens")))
            , test "one segment can't name a project, so it isn't a route" <|
                \_ ->
                    Expect.equal Nothing (Route.parse (url (Just "/design-playground")))
            , test "trailing and doubled slashes don't change the route" <|
                \_ ->
                    Expect.equal
                        (Just (repo "acme/design" TokensTab))
                        (Route.parse (url (Just "//acme//design//tokens/")))
            , test "a branch on a project path with no tab still opens on tokens" <|
                \_ ->
                    Expect.equal
                        (Just (onBranch "feature-x" (repo "acme/design" TokensTab)))
                        (Route.parse (url (Just "/acme/design?branch=feature-x")))
            , test "an empty branch parameter reads as no branch, not a branch called \"\"" <|
                \_ ->
                    Expect.equal
                        (Just (repo "acme/design" TokensTab))
                        (Route.parse (url (Just "/acme/design/tokens?branch=")))
            , test "an unrelated parameter alongside the branch is ignored" <|
                \_ ->
                    Expect.equal
                        (Just (onBranch "feature-x" (repo "acme/design" TokensTab)))
                        (Route.parse (url (Just "/acme/design/tokens?ref=old&branch=feature-x")))
            , test "the query part never leaks into the project path" <|
                \_ ->
                    Route.parse (url (Just "/acme/design/tokens?branch=feature-x"))
                        |> Maybe.andThen repoPath
                        |> Expect.equal (Just "acme/design")
            , test "branchOf reads the branch straight off a URL" <|
                \_ ->
                    ( Route.branchOf (url (Just "/acme/design/tokens?branch=feature%2Fx"))
                    , Route.branchOf (url (Just "/acme/design/tokens"))
                    , Route.branchOf (url (Just ""))
                    )
                        |> Expect.equal ( Just "feature/x", Nothing, Nothing )
            ]
        , describe "writing URLs"
            [ test "routes are written into the fragment, so the deploy subpath is left alone" <|
                \_ ->
                    Expect.equal
                        "#/acme/design/components/Button"
                        (Route.toString (repo "acme/design" (ComponentsTab (Just "Button"))))
            , test "a slash in a name is escaped rather than becoming a separator" <|
                \_ ->
                    Expect.equal
                        "#/acme/design/components/Nav%2FItem"
                        (Route.toString (repo "acme/design" (ComponentsTab (Just "Nav/Item"))))
            , test "the branch is written last, after the tab" <|
                \_ ->
                    Expect.equal
                        "#/acme/design/tokens?branch=feature%2Fx"
                        (Route.toString (onBranch "feature/x" (repo "acme/design" TokensTab)))
            ]
        , describe "forProject decides whether the branch is worth writing down"
            [ test "a branch of your own is written into the URL" <|
                \_ ->
                    Route.forProject project (Just "feature-x") TokensTab
                        |> Route.toString
                        |> Expect.equal "#/acme/design/tokens?branch=feature-x"
            , test "the default branch is left out, so read-only browsing keeps the short URL" <|
                \_ ->
                    -- Otherwise every history entry would carry ?branch=main
                    -- and Back would walk through a string of them.
                    Route.forProject project (Just "main") TokensTab
                        |> Route.toString
                        |> Expect.equal "#/acme/design/tokens"
            , test "and so is no branch at all" <|
                \_ ->
                    Route.forProject project Nothing TokensTab
                        |> Route.toString
                        |> Expect.equal "#/acme/design/tokens"
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


{-| A repository route on its default branch, which is what most of these are
about. `onBranch` puts one somewhere else.
-}
repo : String -> TabRoute -> Route
repo path tab =
    Repo { path = path, branch = Nothing, tab = tab }


onBranch : String -> Route -> Route
onBranch branch route =
    case route of
        Repo r ->
            Repo { r | branch = Just branch }

        Home ->
            Home


repoPath : Route -> Maybe String
repoPath route =
    case route of
        Repo r ->
            Just r.path

        Home ->
            Nothing


project : { pathWithNamespace : String, defaultBranch : String }
project =
    { pathWithNamespace = "acme/design", defaultBranch = "main" }


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
