module ScreensTest exposing (suite)

import Dict
import Expect
import Json.Decode as Decode
import Renderer
import Screens exposing (Screen, ScreenNode(..))
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "Screens Codecs"
        [ test "decodes and encodes a Screen accurately" <|
            \_ ->
                let
                    screen : Screen
                    screen =
                        { name = "Home Page"
                        , path = "/"
                        , root =
                            Container
                                { direction = "column"
                                , styles = Dict.fromList [ ( "padding", "1rem" ) ]
                                }
                                [ ComponentInstance
                                    { componentName = "Header"
                                    , variant = Just "primary"
                                    , state = Nothing
                                    , slots =
                                        [ ( "title", [ TextNode "Welcome" ] ) ]
                                    }
                                ]
                        }

                    encoded =
                        Screens.encoder screen

                    decoded =
                        Decode.decodeValue Screens.decoder encoded
                in
                Expect.equal (Ok screen) decoded
        , describe "formsCycle"
            [ test "a screen that includes itself is a loop" <|
                \_ ->
                    Expect.equal True
                        (Screens.formsCycle library [ "Shell" ] (screenInstance "Shell"))
            , test "a loop through a screen in between is still a loop" <|
                \_ ->
                    -- Shell contains Page, so putting Shell inside Page closes
                    -- the ring one screen further out.
                    Expect.equal True
                        (Screens.formsCycle library [ "Page" ] (screenInstance "Shell"))
            , test "including a screen that doesn't come back is not a loop" <|
                \_ ->
                    Expect.equal False
                        (Screens.formsCycle library [ "Shell" ] (screenInstance "Footer"))
            , test "a screen that isn't in the library can't be followed, so it isn't a loop" <|
                \_ ->
                    Expect.equal False
                        (Screens.formsCycle library [ "Shell" ] (screenInstance "Missing"))
            , test "a component is never a loop" <|
                \_ ->
                    Expect.equal False
                        (Screens.formsCycle library
                            [ "Shell" ]
                            (ComponentInstance { componentName = "Button", variant = Nothing, state = Nothing, slots = [] })
                        )
            ]
        , describe "the editor and the preview agree about what a loop is" <|
            -- The rule is implemented twice. `formsCycle` runs up front so the
            -- editor can flag the offending row; `Renderer.renderScreenNode`
            -- rediscovers it on the way down, because it has to report at the
            -- node rather than about the tree. Merging them would cost the
            -- renderer that. What must not drift is the rule, so it is pinned
            -- here rather than the implementation.
            let
                agree case_ =
                    test case_.description <|
                        \_ ->
                            let
                                rendered =
                                    Renderer.renderScreenNode Dict.empty library case_.visited [] case_.node
                                        |> Query.fromHtml
                            in
                            Expect.all
                                [ \_ ->
                                    Screens.formsCycle library case_.visited case_.node
                                        |> Expect.equal case_.isLoop
                                , \_ ->
                                    if case_.isLoop then
                                        rendered |> Query.has [ Selector.text (loopMessage case_.namesInMessage) ]

                                    else
                                        rendered |> Query.hasNot [ Selector.text (loopMessage case_.namesInMessage) ]
                                ]
                                ()
            in
            List.map agree
                [ { description = "a screen that includes itself"
                  , visited = [ "Shell" ]
                  , node = screenInstance "Shell"
                  , isLoop = True
                  , namesInMessage = "Shell"
                  }
                , { description = "a loop through a screen in between"
                  , visited = [ "Page" ]
                  , node = screenInstance "Shell"
                  , isLoop = True

                  -- The preview names the screen where the ring closes rather
                  -- than the one you started from, which is the screen you have
                  -- to edit to break the loop.
                  , namesInMessage = "Page"
                  }
                , { description = "a chain that ends"
                  , visited = [ "Shell" ]
                  , node = screenInstance "Footer"
                  , isLoop = False
                  , namesInMessage = "Footer"
                  }
                , { description = "a screen that isn't in the library"
                  , visited = [ "Shell" ]
                  , node = screenInstance "Missing"
                  , isLoop = False
                  , namesInMessage = "Missing"
                  }
                ]
        ]


{-| What the preview says when it walks into a loop. The wording is behaviour —
it is the only thing that tells someone what happened — so it is spelled out
here rather than reached for from the source.
-}
loopMessage : String -> String
loopMessage screenName =
    screenName ++ " ends up including itself — remove the loop to preview it."


{-| Shell contains Page, Page contains Footer, Footer contains nothing.
-}
library : Dict.Dict String Screen
library =
    [ ( "Shell", screenInstance "Page" )
    , ( "Page", screenInstance "Footer" )
    , ( "Footer", TextNode "fin" )
    ]
        |> List.map
            (\( name, child ) ->
                ( name
                , { name = name
                  , path = "/" ++ name
                  , root = Container { direction = "column", styles = Dict.empty } [ child ]
                  }
                )
            )
        |> Dict.fromList


screenInstance : String -> ScreenNode
screenInstance name =
    ScreenInstance { screenName = name }
