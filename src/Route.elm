module Route exposing
    ( Route(..), TabRoute(..), parse, toString
    , tabRouteFor, toTab
    )

{-| Where you are in the app, as a URL.

The route lives in the **fragment** — `#/acme/design/components/Button` — not the
path. The app is served from a subpath (`base` in `vite.config.js`) on GitHub
Pages, which serves static files and has no history fallback, so a path-based
deep link would 404 the moment anyone refreshed or shared one. A fragment never
reaches the server, so every URL the app produces survives a reload without any
hosting configuration.

@docs Route, TabRoute, parse, toString
@docs tabRouteFor, toTab

-}

import Types exposing (Tab(..))
import Url exposing (Url)


{-| -}
type Route
    = Home
    | Repo String TabRoute


{-| -}
type TabRoute
    = TokensTab
    | ComponentsTab (Maybe String)
    | ScreensTab (Maybe String)
    | GitWorkflowsTab
    | ExportPipelineTab


{-| A GitLab project path is always at least `namespace/project`, and longer
when the namespace is a nested group. That floor is what tells a tab keyword
apart from a project whose own last segment happens to be `export`: the keyword
only counts as one when enough segments are left over to name a project.

`#/acme/export` is therefore the _project_ `acme/export`, while
`#/acme/design/export` is the export tab of `acme/design`. The one case this
can't call is a nested group whose project really is named `export` — for that,
`toString` always writes the tab out in full, so only a hand-typed URL is
ambiguous.

-}
minProjectSegments : Int
minProjectSegments =
    2


{-| -}
parse : Url -> Maybe Route
parse url =
    url.fragment
        |> Maybe.withDefault ""
        |> String.split "/"
        |> List.filter (\s -> not (String.isEmpty s))
        |> List.map (\s -> Url.percentDecode s |> Maybe.withDefault s)
        |> fromSegments


fromSegments : List String -> Maybe Route
fromSegments segments =
    case segments of
        [] ->
            Just Home

        _ ->
            case withTabSuffix (List.reverse segments) of
                Just route ->
                    Just route

                Nothing ->
                    -- No tab named, so `#/acme/design` means "open this project
                    -- where it opens by default".
                    if List.length segments >= minProjectSegments then
                        Just (Repo (String.join "/" segments) TokensTab)

                    else
                        Nothing


{-| Takes the segments back-to-front, so the tab keyword — the thing being
matched — comes first and the project path is whatever is left.

The longer reading has to be tried first, or a component named after a tab
would be read as the tab: `…/components/tokens` is the component `tokens`, not
the tokens tab of a project called `…/components`. Each reading can also decline
— that's what a keyword with too little left over to name a project does — so
they're tried in turn rather than being chosen by pattern.

-}
withTabSuffix : List String -> Maybe Route
withTabSuffix reversed =
    case namedTab reversed of
        Just route ->
            Just route

        Nothing ->
            bareTab reversed


{-| `…/components/Button` — a tab that also names what's selected in it.
-}
namedTab : List String -> Maybe Route
namedTab reversed =
    case reversed of
        name :: "components" :: rest ->
            repoWith rest (ComponentsTab (Just name))

        name :: "screens" :: rest ->
            repoWith rest (ScreensTab (Just name))

        _ ->
            Nothing


{-| `…/tokens` — a tab on its own.
-}
bareTab : List String -> Maybe Route
bareTab reversed =
    case reversed of
        "tokens" :: rest ->
            repoWith rest TokensTab

        "components" :: rest ->
            repoWith rest (ComponentsTab Nothing)

        "screens" :: rest ->
            repoWith rest (ScreensTab Nothing)

        "branches" :: rest ->
            repoWith rest GitWorkflowsTab

        "export" :: rest ->
            repoWith rest ExportPipelineTab

        _ ->
            Nothing


{-| Declines when what's left can't be a project path, which is how a tab
keyword that is really part of the project's own name gets rejected.
-}
repoWith : List String -> TabRoute -> Maybe Route
repoWith reversedPath tab =
    if List.length reversedPath >= minProjectSegments then
        Just (Repo (String.join "/" (List.reverse reversedPath)) tab)

    else
        Nothing


{-| Which tab a route lands on.
-}
toTab : TabRoute -> Tab
toTab tabRoute =
    case tabRoute of
        TokensTab ->
            TokenStudio

        ComponentsTab _ ->
            ComponentRegistry

        ScreensTab _ ->
            ScreenComposer

        GitWorkflowsTab ->
            GitWorkflows

        ExportPipelineTab ->
            ExportPipeline


{-| The other direction: the route for a tab, carrying whatever is currently
selected so that switching away and back doesn't lose it. Both the tab bar and
the `SwitchTab` handler need this, and they used to spell it out separately.
-}
tabRouteFor : Tab -> Maybe String -> Maybe String -> TabRoute
tabRouteFor tab selectedComponent selectedScreen =
    case tab of
        TokenStudio ->
            TokensTab

        ComponentRegistry ->
            ComponentsTab selectedComponent

        ScreenComposer ->
            ScreensTab selectedScreen

        GitWorkflows ->
            GitWorkflowsTab

        ExportPipeline ->
            ExportPipelineTab


{-| -}
toString : Route -> String
toString route =
    case route of
        Home ->
            "#/"

        Repo path tab ->
            let
                base =
                    "#/" ++ encodePath path
            in
            case tab of
                TokensTab ->
                    base ++ "/tokens"

                ComponentsTab Nothing ->
                    base ++ "/components"

                ComponentsTab (Just comp) ->
                    base ++ "/components/" ++ Url.percentEncode comp

                ScreensTab Nothing ->
                    base ++ "/screens"

                ScreensTab (Just scr) ->
                    base ++ "/screens/" ++ Url.percentEncode scr

                GitWorkflowsTab ->
                    base ++ "/branches"

                ExportPipelineTab ->
                    base ++ "/export"


{-| `Url.percentEncode` escapes `/` too, so the separators have to be put back
by encoding one segment at a time. Component and screen names go through it as
well: `Naming.check` only rejects blank and duplicate names, so a name is free
to contain a slash or a space.
-}
encodePath : String -> String
encodePath path =
    path
        |> String.split "/"
        |> List.map Url.percentEncode
        |> String.join "/"
