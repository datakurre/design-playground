module Route exposing
    ( Route(..), RepoRoute, TabRoute(..), parse, toString
    , forProject, branchOf
    , tabRouteFor, toTab
    )

{-| Where you are in the app, as a URL.

The route lives in the **fragment** — `#/acme/design/components/Button` — not the
path. The app is served from a subpath (`base` in `vite.config.js`) on GitHub
Pages, which serves static files and has no history fallback, so a path-based
deep link would 404 the moment anyone refreshed or shared one. A fragment never
reaches the server, so every URL the app produces survives a reload without any
hosting configuration.

The branch rides along as `?branch=…` **inside** the fragment. It has to be in
the URL at all because the branch now decides whether the app is editable, and a
reload that silently dropped you back onto the read-only default branch would
look like lost work. It cannot be another path segment, because branch names
contain slashes — the app itself suggests `feature/`, `fix/` and friends.

@docs Route, RepoRoute, TabRoute, parse, toString
@docs forProject, branchOf
@docs tabRouteFor, toTab

-}

import Types exposing (Tab(..))
import Url exposing (Url)


{-| -}
type Route
    = Home
    | Repo RepoRoute


{-| A record rather than three positional arguments: `path` and `branch` are
both strings, and an argument order is a poor place to keep the difference.

`branch = Nothing` means "the project's default branch", not "unspecified".
That is what keeps `#/acme/design/tokens` the canonical URL for read-only
browsing instead of every history entry growing a `?branch=main`.

-}
type alias RepoRoute =
    { path : String
    , branch : Maybe String
    , tab : TabRoute
    }


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


{-| The branch is split off before the segments are, so everything below it
parses exactly the URLs it always did.

Splitting on the first raw `?` is unambiguous, which is easier to believe with
the two reasons written down. Git refuses `?` in a ref name
(`git-check-ref-format`), so a branch can never contribute one. And
`Url.percentEncode` escapes `?` to `%3F`, so a component called `Why?` never
puts a raw one in the path either.

-}
parse : Url -> Maybe Route
parse url =
    let
        ( pathPart, queryPart ) =
            splitOnFirst "?" (Maybe.withDefault "" url.fragment)
    in
    pathPart
        |> String.split "/"
        |> List.filter (\s -> not (String.isEmpty s))
        |> List.map (\s -> Url.percentDecode s |> Maybe.withDefault s)
        |> fromSegments
        |> Maybe.map (withBranch (branchParam queryPart))


{-| The branch a URL asks for, for the places that hold a `Url` rather than a
`Route`. `Nothing` for `Home`, for a URL that names no branch, and for one whose
`branch=` is empty — all three mean the same thing here.
-}
branchOf : Url -> Maybe String
branchOf url =
    case parse url of
        Just (Repo repo) ->
            repo.branch

        _ ->
            Nothing


splitOnFirst : String -> String -> ( String, String )
splitOnFirst separator string =
    case String.indexes separator string of
        first :: _ ->
            ( String.left first string, String.dropLeft (first + String.length separator) string )

        [] ->
            ( string, "" )


{-| `branch=feature%2Fx` out of a query string, tolerating the other parameters
this app does not write but a hand-edited URL might carry. A present-but-empty
`?branch=` reads as absent rather than as a branch called "".
-}
branchParam : String -> Maybe String
branchParam query =
    query
        |> String.split "&"
        |> List.filterMap
            (\pair ->
                case splitOnFirst "=" pair of
                    ( "branch", value ) ->
                        Url.percentDecode value
                            |> Maybe.withDefault value
                            |> nonEmpty

                    _ ->
                        Nothing
            )
        |> List.head


nonEmpty : String -> Maybe String
nonEmpty string =
    if String.isEmpty string then
        Nothing

    else
        Just string


withBranch : Maybe String -> Route -> Route
withBranch branch route =
    case route of
        Home ->
            Home

        Repo repo ->
            Repo { repo | branch = branch }


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
                        Just (Repo { path = String.join "/" segments, branch = Nothing, tab = TokensTab })

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
        Just (Repo { path = String.join "/" (List.reverse reversedPath), branch = Nothing, tab = tab })

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


{-| The route for a tab of a repository, with the branch attached only when it
is not the project's default one.

This is the one place that decision is made. Every link in the app goes through
it, so a tab click or a component link cannot quietly drop the branch and put
the user back on the read-only default.

It takes an extensible record rather than importing `GitLab.Projects`, the same
way `Ui.contextHelp` takes one rather than importing `Help`.

-}
forProject : { r | pathWithNamespace : String, defaultBranch : String } -> Maybe String -> TabRoute -> Route
forProject project branch tab =
    Repo
        { path = project.pathWithNamespace
        , branch =
            if branch == Just project.defaultBranch then
                Nothing

            else
                branch
        , tab = tab
        }


{-| -}
toString : Route -> String
toString route =
    case route of
        Home ->
            "#/"

        Repo repo ->
            let
                base =
                    "#/" ++ encodePath repo.path

                query =
                    case repo.branch of
                        Just branch ->
                            "?branch=" ++ Url.percentEncode branch

                        Nothing ->
                            ""
            in
            (case repo.tab of
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
            )
                ++ query


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
