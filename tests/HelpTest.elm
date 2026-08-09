module HelpTest exposing (..)

import Expect
import Help
import Test exposing (..)


suite : Test
suite =
    describe "Help"
        [ test "topic ids are exactly in order" <|
            \_ ->
                Expect.equal
                    [ "tokens"
                    , "new-token"
                    , "components"
                    , "component-layout"
                    , "usage-contract"
                    , "component-editor"
                    , "screens"
                    , "add-component-to-screen"
                    , "add-screen-to-screen"
                    , "screen-editor"
                    , "git-workflows"
                    , "branch"
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
                Expect.equal (List.length ids) (List.length (List.foldl (\id acc -> if List.member id acc then acc else id :: acc) [] ids))
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
        ]
