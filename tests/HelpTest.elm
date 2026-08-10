module HelpTest exposing (..)

import Expect
import Help
import Test exposing (Test, describe, test)
import Types exposing (Tab(..))


suite : Test
suite =
    describe "Help"
        [ test "topic ids are exactly in order" <|
            \_ ->
                Expect.equal
                    [ "read-only-branch"
                    , "tokens"
                    , "themes"
                    , "token-filters"
                    , "new-token"
                    , "components"
                    , "component-layout"
                    , "usage-contract"
                    , "component-editor"
                    , "component-variant"
                    , "component-state"
                    , "component-slot"
                    , "component-context"
                    , "screens"
                    , "add-component-to-screen"
                    , "add-screen-to-screen"
                    , "screen-editor"
                    , "git-workflows"
                    , "branch"
                    , "unsaved-changes"
                    , "merge-requests"
                    , "contract-check"
                    , "export"
                    ]
                    (List.map .id Help.all)
        , test "ids have no duplicates" <|
            \_ ->
                let
                    ids =
                        List.map .id Help.all
                in
                Expect.equal (List.length ids)
                    (List.length
                        (List.foldl
                            (\id acc ->
                                if List.member id acc then
                                    acc

                                else
                                    id :: acc
                            )
                            []
                            ids
                        )
                    )
        , test "every topic has a non-empty title" <|
            \_ ->
                Expect.equal True (List.all (\t -> String.trim t.title /= "") Help.all)
        , test "every topic has at least one non-empty body paragraph" <|
            \_ ->
                Expect.equal True
                    (List.all
                        (\t -> not (List.isEmpty t.body) && List.all (\p -> String.trim p /= "") t.body)
                        Help.all
                    )

        -- `forTab` is total, so a new tab won't compile until it has a topic;
        -- this then forces the pairing to be stated. Between the two, no tab
        -- can ship with nothing to say for itself. It's the closest we get to
        -- tying a topic to its render site — `Tab` is the only part of the
        -- view layer that isn't behind `Model`'s `Nav.Key`.
        , test "every tab has a topic, in tab-bar order" <|
            \_ ->
                Expect.equal
                    [ "tokens", "components", "screens", "git-workflows", "export" ]
                    (List.map (\t -> (Help.forTab t).id)
                        [ TokenStudio, ComponentRegistry, ScreenComposer, GitWorkflows, ExportPipeline ]
                    )
        , test "exactly the tab topics carry a lede" <|
            \_ ->
                Expect.equal
                    [ "tokens", "components", "screens", "git-workflows", "export" ]
                    (Help.all |> List.filter (\t -> t.lede /= Nothing) |> List.map .id)

        -- The lede is always on screen, so it has to stay one line. Left
        -- unchecked it grows back into the paragraph the "?" already holds.
        , test "every lede is a single short sentence" <|
            \_ ->
                Expect.equal []
                    (Help.all
                        |> List.filterMap (\t -> Maybe.map (Tuple.pair t.id) t.lede)
                        |> List.filter (\( _, lede ) -> String.length lede > 140 || String.contains "\n" lede)
                        |> List.map Tuple.first
                    )

        -- The app has no tree editor, no drag-and-drop, no reordering and no
        -- way to remove a child: ScreenComposer's editor is a title, Save and
        -- Delete, and two append-only rows of buttons. Two topics claimed
        -- otherwise, and nothing caught it — help drifts from the UI silently
        -- because nothing compiles against prose.
        --
        -- When one of these is genuinely built, delete its term here in the
        -- same commit that builds it.
        --
        -- It can't tell a promise from a denial, so a topic admitting it
        -- *can't* reorder has to say so without the word. That's the price of
        -- a check that needs no parser.
        , test "no topic promises an affordance the app doesn't have" <|
            \_ ->
                let
                    absent =
                        [ "tree below", "drag", "reorder", "rearrang", "right-click" ]
                in
                Expect.equal []
                    (List.concatMap
                        (\topic ->
                            List.filter
                                (\term -> List.any (\p -> String.contains term (String.toLower p)) topic.body)
                                absent
                        )
                        Help.all
                    )
        ]
