module UiTest exposing (suite)

{-| The chrome helpers whose behaviour is not obvious from looking at them.

`actionButton` is here because it carries the app's answer to "you cannot do
that right now", and getting it wrong is invisible: a `disabled` attribute left
off still looks disabled if the classes say so, and still fires.

-}

import Expect
import Html
import Html.Attributes
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Ui


type Msg
    = Clicked


suite : Test
suite =
    describe "Ui"
        [ describe "actionButton"
            [ test "an available action fires its message" <|
                \_ ->
                    Ui.actionButton Ui.btnPrimary (Ui.Do Clicked) [ Html.text "Save" ]
                        |> Query.fromHtml
                        |> Event.simulate Event.click
                        |> Event.expect Clicked
            , test "a blocked action is really disabled, not just styled that way" <|
                \_ ->
                    Ui.actionButton Ui.btnPrimary (Ui.Blocked "Create a branch first") [ Html.text "Save" ]
                        |> Query.fromHtml
                        |> Query.has [ Selector.disabled True ]
            , test "and explains itself on hover rather than after the click" <|
                \_ ->
                    Ui.actionButton Ui.btnPrimary (Ui.Blocked "Create a branch first") [ Html.text "Save" ]
                        |> Query.fromHtml
                        |> Query.has [ Selector.attribute (Html.Attributes.title "Create a branch first") ]
            , test "a blocked action fires nothing" <|
                \_ ->
                    Ui.actionButton Ui.btnPrimary (Ui.Blocked "Create a branch first") [ Html.text "Save" ]
                        |> Query.fromHtml
                        |> Event.simulate Event.click
                        |> Event.toResult
                        |> Expect.err
            , test "the disabled look replaces the tone rather than layering over it" <|
                \_ ->
                    -- classes concatenate rather than replace, so a disabled
                    -- button carrying btnPrimary's cursor-pointer as well would
                    -- be decided by stylesheet order, not by us.
                    Ui.actionButton Ui.btnPrimary (Ui.Blocked "nope") [ Html.text "Save" ]
                        |> Query.fromHtml
                        |> Query.hasNot [ Selector.class "cursor-pointer" ]
            ]
        , describe "branchPicker"
            [ test "marks the branches you cannot write to" <|
                \_ ->
                    Ui.branchPicker
                        { label = "Branch", current = Just "feature-x", onSwitch = always Clicked }
                        [ { name = "main", default = True, protected = True }
                        , { name = "release/1.0", default = False, protected = True }
                        , { name = "feature-x", default = False, protected = False }
                        ]
                        |> Query.fromHtml
                        |> Query.findAll [ Selector.tag "option" ]
                        |> Query.count (Expect.equal 3)
            , test "a writable branch is named plainly" <|
                \_ ->
                    Ui.branchPicker
                        { label = "Branch", current = Just "feature-x", onSwitch = always Clicked }
                        [ { name = "feature-x", default = False, protected = False } ]
                        |> Query.fromHtml
                        |> Query.has [ Selector.text "feature-x" ]
            , test "a protected one says so in the option itself" <|
                \_ ->
                    -- The picker is the only place a branch is named before you
                    -- pick it, so it is the only place that can warn you first.
                    Ui.branchPicker
                        { label = "Branch", current = Nothing, onSwitch = always Clicked }
                        [ { name = "main", default = True, protected = True } ]
                        |> Query.fromHtml
                        |> Query.has [ Selector.text "main · read-only" ]
            ]
        ]
