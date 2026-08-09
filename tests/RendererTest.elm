module RendererTest exposing (suite)

import Dict
import Renderer
import Screens exposing (ScreenNode(..))
import Test exposing (..)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


{-| The preview's error boxes are the app's last line of guidance: when a
screen template instantiates a component the user hasn't created, this red box
is the only thing that tells them what happened. So the wording is behavior,
and it's locked here.

`renderScreenNode` takes dictionaries and a node rather than a `Model`, which
is what makes it reachable from a test at all — everything in `update` and
every `Model`-taking view is behind a `Nav.Key`.
-}
suite : Test
suite =
    describe "Renderer preview problems"
        [ test "a missing component says where to create it" <|
            \_ ->
                instance "Button"
                    |> render
                    |> Query.has
                        [ Selector.text "There is no component called Button — create one with that name on the Components tab." ]
        , test "a component with no layout says where to add one" <|
            \_ ->
                let
                    empty =
                        { name = "Button"
                        , description = Nothing
                        , variants = []
                        , slots = []
                        , states = []
                        , layout = Nothing
                        }
                in
                Renderer.renderScreenNode (Dict.fromList [ ( "Button", empty ) ]) Dict.empty [] [] (instance "Button")
                    |> Query.fromHtml
                    |> Query.has
                        [ Selector.text "Button has no layout yet — add one on the Components tab." ]
        , test "a missing screen names the screen" <|
            \_ ->
                ScreenInstance { screenName = "Shell" }
                    |> render
                    |> Query.has [ Selector.text "There is no screen called Shell." ]
        , test "a screen that includes itself says to remove the loop" <|
            \_ ->
                Renderer.renderScreenNode Dict.empty Dict.empty [ "Shell" ] [] (ScreenInstance { screenName = "Shell" })
                    |> Query.fromHtml
                    |> Query.has [ Selector.text "Shell ends up including itself — remove the loop to preview it." ]
        ]


instance : String -> ScreenNode
instance name =
    ComponentInstance { componentName = name, variant = Nothing, state = Nothing, slots = [] }


render : ScreenNode -> Query.Single msg
render node =
    Renderer.renderScreenNode Dict.empty Dict.empty [] [] node
        |> Query.fromHtml
