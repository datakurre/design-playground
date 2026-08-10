module ReadOnlyViewTest exposing (suite)

{-| The read-only branch, rendered.

`Guard` decides the rule and `UpdateTest` proves `update` enforces it. This
covers the third obligation: that the pages actually _look_ refused, so nobody
clicks a live-looking button only to be told no afterwards.

These render the whole `Model`-taking entry points rather than a helper, which
is only possible because the `Nav.Key` lives in `Main` — see `UpdateTest`'s
note. It is worth doing here because `make smoke` cannot reach any of this:
every one of these screens is behind GitLab sign-in, which is impossible
locally.

Note what is _not_ asserted: that every button on the page is disabled. Picking
a component, clearing a filter and switching theme all stay live on a read-only
branch, and should — reading is the whole point of being there. The assertions
below name the controls that write.

-}

import Components
import Dict
import Expect
import Html.Attributes
import Pages.ComponentRegistry
import Pages.ExportPipeline
import Pages.ScreenComposer
import Screens
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Types
import Url



-- THE TESTS


suite : Test
suite =
    describe "the editors on a read-only branch"
        [ describe "Export"
            [ test "the commit button is disabled and says why" <|
                \_ ->
                    Pages.ExportPipeline.viewExportPipeline onDefaultBranch
                        |> Query.fromHtml
                        |> Query.find [ Selector.tag "button" ]
                        |> Query.has [ Selector.disabled True, Selector.text "Export and commit" ]
            , test "and live on a branch of your own" <|
                \_ ->
                    Pages.ExportPipeline.viewExportPipeline onBranch
                        |> Query.fromHtml
                        |> Query.find [ Selector.tag "button" ]
                        |> Query.hasNot [ Selector.disabled True ]
            , test "but choosing a format stays available, because it writes nothing" <|
                \_ ->
                    Pages.ExportPipeline.viewExportPipeline onDefaultBranch
                        |> Query.fromHtml
                        |> Query.findAll [ Selector.attribute (Html.Attributes.type_ "checkbox"), Selector.disabled True ]
                        |> Query.count (Expect.equal 0)
            ]
        , describe "Components"
            [ test "the create form's name field is readonly, not disabled" <|
                \_ ->
                    -- readonly keeps it focusable, selectable and announced by
                    -- a screen reader. On a page whose whole purpose is now
                    -- reading, disabled would be the worse bug.
                    Pages.ComponentRegistry.viewComponentRegistry (withComponents onDefaultBranch)
                        |> Query.fromHtml
                        |> Query.find [ Selector.attribute (Html.Attributes.attribute "aria-label" "New component name") ]
                        |> Query.has [ Selector.attribute (Html.Attributes.readonly True) ]
            , test "and editable on a branch of your own" <|
                \_ ->
                    Pages.ComponentRegistry.viewComponentRegistry (withComponents onBranch)
                        |> Query.fromHtml
                        |> Query.find [ Selector.attribute (Html.Attributes.attribute "aria-label" "New component name") ]
                        |> Query.hasNot [ Selector.attribute (Html.Attributes.readonly True) ]
            , test "every control refused for the branch is really disabled" <|
                \_ ->
                    Pages.ComponentRegistry.viewComponentRegistry (editingComponent onDefaultBranch)
                        |> Query.fromHtml
                        |> Query.findAll [ Selector.attribute (Html.Attributes.title branchRefusal) ]
                        |> Query.each (Query.has [ Selector.disabled True ])
            , test "and there are several of them, so that is not passing on an empty page" <|
                \_ ->
                    -- Save, Delete, and the "+ Stack / + Grid / + Element" row
                    -- a component with no layout yet offers.
                    Pages.ComponentRegistry.viewComponentRegistry (editingComponent onDefaultBranch)
                        |> Query.fromHtml
                        |> Query.findAll [ Selector.attribute (Html.Attributes.title branchRefusal) ]
                        |> Query.count (Expect.greaterThan 1)
            , test "none of which is refused on a branch of your own" <|
                \_ ->
                    Pages.ComponentRegistry.viewComponentRegistry (editingComponent onBranch)
                        |> Query.fromHtml
                        |> Query.findAll [ Selector.attribute (Html.Attributes.title branchRefusal) ]
                        |> Query.count (Expect.equal 0)
            ]
        , describe "Screens"
            [ test "every control refused for the branch is really disabled" <|
                \_ ->
                    Pages.ScreenComposer.viewScreenComposer (editingScreen onDefaultBranch)
                        |> Query.fromHtml
                        |> Query.findAll [ Selector.attribute (Html.Attributes.title branchRefusal) ]
                        |> Query.each (Query.has [ Selector.disabled True ])
            , test "the new-screen field is readonly" <|
                \_ ->
                    Pages.ScreenComposer.viewScreenComposer (editingScreen onDefaultBranch)
                        |> Query.fromHtml
                        |> Query.find [ Selector.attribute (Html.Attributes.attribute "aria-label" "New screen name") ]
                        |> Query.has [ Selector.attribute (Html.Attributes.readonly True) ]
            , test "and editable on a branch of your own" <|
                \_ ->
                    Pages.ScreenComposer.viewScreenComposer (editingScreen onBranch)
                        |> Query.fromHtml
                        |> Query.find [ Selector.attribute (Html.Attributes.attribute "aria-label" "New screen name") ]
                        |> Query.hasNot [ Selector.attribute (Html.Attributes.readonly True) ]
            ]
        ]


{-| What `Guard.refusal` produces for the default branch, spelled out rather
than called: it is the sentence the user reads on hover, so a copy edit should
have to be made deliberately here too.
-}
branchRefusal : String
branchRefusal =
    "You're on main, the default branch — create a branch, then make your changes on it"



-- FIXTURES


{-| A repository open on its default branch: read-only.
-}
onDefaultBranch : Types.Model
onDefaultBranch =
    { base
        | currentBranch = Just "main"
        , branches = Just [ { name = "main", commitId = "aaa", default = True, protected = True } ]
    }


onBranch : Types.Model
onBranch =
    { base
        | currentBranch = Just "feature-x"
        , branches =
            Just
                [ { name = "main", commitId = "aaa", default = True, protected = True }
                , { name = "feature-x", commitId = "bbb", default = False, protected = False }
                ]
    }


base : Types.Model
base =
    { blank
        | selectedProject =
            Just
                { id = 7
                , name = "design"
                , pathWithNamespace = "acme/design"
                , defaultBranch = "main"
                }
        , tokens = Just []
        , exportTargets = [ "css" ]
    }


blank : Types.Model
blank =
    Types.initial
        { protocol = Url.Https
        , host = "datakurre.github.io"
        , port_ = Nothing
        , path = "/design-playground/"
        , query = Nothing
        , fragment = Just "/acme/design/tokens"
        }
        { token = Just "secret", pkceChallenge = "challenge", pkceVerifier = "verifier" }


withComponents : Types.Model -> Types.Model
withComponents model =
    { model | components = Just [ button ] }


editingComponent : Types.Model -> Types.Model
editingComponent model =
    { model | components = Just [ button ], selectedComponentName = Just "Button" }


button : Components.Component
button =
    { name = "Button"
    , description = Nothing
    , variants = [ "primary" ]
    , slots = []
    , states = []
    , layout = Nothing
    }


editingScreen : Types.Model -> Types.Model
editingScreen model =
    { model
        | components = Just [ button ]
        , screens = Just [ home ]
        , selectedScreenName = Just "Home"
    }


home : Screens.Screen
home =
    { name = "Home"
    , path = "/"
    , root = Screens.Container { direction = "column", styles = Dict.empty } []
    }
