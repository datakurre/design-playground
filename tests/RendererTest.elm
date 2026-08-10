module RendererTest exposing (suite)

import Components exposing (Layout(..))
import Dict
import Expect
import Renderer
import Screens exposing (ScreenNode(..))
import Test exposing (..)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Tokens


{-| The preview's error boxes are the app's last line of guidance: when a
screen template instantiates a component the user hasn't created, this red box
is the only thing that tells them what happened. So the wording is behavior,
and it's locked here.

`renderScreenNode` takes dictionaries and a node rather than a `Model`, which
keeps these assertions about the thing being rendered rather than about how a
model got into that state.

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
        , describe "conditional layout"
            [ test "a condition on the variant being shown is drawn" <|
                \_ ->
                    only { variant = Just "primary", state = Nothing }
                        |> preview (Just "primary") Nothing
                        |> Query.has [ Selector.text "Conditional" ]
            , test "a condition on some other variant is not" <|
                \_ ->
                    only { variant = Just "primary", state = Nothing }
                        |> preview (Just "secondary") Nothing
                        |> Query.hasNot [ Selector.text "Conditional" ]
            , test "a condition on a variant is not drawn when no variant is chosen" <|
                \_ ->
                    only { variant = Just "primary", state = Nothing }
                        |> preview Nothing Nothing
                        |> Query.hasNot [ Selector.text "Conditional" ]
            , test "a condition that names nothing is always drawn" <|
                \_ ->
                    only { variant = Nothing, state = Nothing }
                        |> preview Nothing Nothing
                        |> Query.has [ Selector.text "Conditional" ]
            , test "a condition on both holds only when both match" <|
                \_ ->
                    let
                        layout =
                            only { variant = Just "primary", state = Just "hover" }
                    in
                    -- The matching pair draws; each near miss doesn't.
                    Expect.all
                        [ \_ -> preview (Just "primary") (Just "hover") layout |> Query.has [ Selector.text "Conditional" ]
                        , \_ -> preview (Just "primary") (Just "focus") layout |> Query.hasNot [ Selector.text "Conditional" ]
                        , \_ -> preview (Just "secondary") (Just "hover") layout |> Query.hasNot [ Selector.text "Conditional" ]
                        , \_ -> preview Nothing Nothing layout |> Query.hasNot [ Selector.text "Conditional" ]
                        ]
                        ()
            , test "what sits beside a condition is drawn either way" <|
                \_ ->
                    Stack { direction = "column", styles = Dict.empty, overrides = [] }
                        [ Element { isSlot = False, styles = Dict.empty, overrides = [] } "Always"
                        , When { variant = Just "primary", state = Nothing }
                            [ Element { isSlot = False, styles = Dict.empty, overrides = [] } "Conditional" ]
                        ]
                        |> preview (Just "secondary") Nothing
                        |> Query.has [ Selector.text "Always" ]
            ]
        , describe "style layers"
            [ test "the base styles are what's drawn with nothing selected" <|
                \_ ->
                    styled [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        |> preview Nothing Nothing
                        |> Query.has [ Selector.style "color" "black" ]
            , test "a layer for the variant being shown is drawn over the base" <|
                \_ ->
                    styled [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        |> preview (Just "primary") Nothing
                        |> Query.has [ Selector.style "color" "white" ]
            , test "a layer for some other variant is not" <|
                \_ ->
                    styled [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        |> preview (Just "secondary") Nothing
                        |> Query.has [ Selector.style "color" "black" ]
            , test "what a layer doesn't mention is still inherited" <|
                \_ ->
                    styled [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ]
                        |> preview (Just "primary") Nothing
                        |> Query.has [ Selector.style "padding" "1rem" ]
            , test "a state layer wins over a variant layer" <|
                \_ ->
                    styled
                        [ layer (Just "primary") Nothing [ ( "color", "variant" ) ]
                        , layer Nothing (Just "hover") [ ( "color", "state" ) ]
                        ]
                        |> preview (Just "primary") (Just "hover")
                        |> Query.has [ Selector.style "color" "state" ]
            , test "token references in a layer resolve like any other value" <|
                \_ ->
                    Renderer.renderWithConditions
                        [ ( [ "color", "brand", "500" ], { value = Tokens.StringValue "#3b82f6", type_ = "color", description = Nothing } ) ]
                        (Just "primary")
                        Nothing
                        (styled [ layer (Just "primary") Nothing [ ( "color", "{color.brand.500}" ) ] ])
                        |> Query.fromHtml
                        |> Query.has [ Selector.style "color" "#3b82f6" ]
            , test "a screen instancing a component with a variant gets that variant's styles" <|
                \_ ->
                    -- Screens already carry variant and state on an instance,
                    -- so this needs nothing of the Screens tab — but it is the
                    -- path that makes a variant worth declaring at all.
                    let
                        button =
                            { name = "Button"
                            , description = Nothing
                            , variants = [ "primary" ]
                            , slots = []
                            , states = []
                            , layout = Just (styled [ layer (Just "primary") Nothing [ ( "color", "white" ) ] ])
                            }
                    in
                    ComponentInstance { componentName = "Button", variant = Just "primary", state = Nothing, slots = [] }
                        |> Renderer.renderScreenNode (Dict.fromList [ ( "Button", button ) ]) Dict.empty [] []
                        |> Query.fromHtml
                        |> Query.has [ Selector.style "color" "white" ]
            ]
        ]


{-| One text element with a base style and whatever layers are handed in.
-}
styled : List Components.StyleLayer -> Layout
styled overrides =
    Element
        { isSlot = False
        , styles = Dict.fromList [ ( "color", "black" ), ( "padding", "1rem" ) ]
        , overrides = overrides
        }
        "Styled"


layer : Maybe String -> Maybe String -> List ( String, String ) -> Components.StyleLayer
layer variant state styles =
    { variant = variant, state = state, styles = Dict.fromList styles }


{-| A layout whose only content sits behind `props`.
-}
only : Components.WhenProps -> Layout
only props =
    Stack { direction = "column", styles = Dict.empty, overrides = [] }
        [ When props [ Element { isSlot = False, styles = Dict.empty, overrides = [] } "Conditional" ] ]


preview : Maybe String -> Maybe String -> Layout -> Query.Single msg
preview variant state layout =
    Renderer.renderWithConditions [] variant state layout
        |> Query.fromHtml


instance : String -> ScreenNode
instance name =
    ComponentInstance { componentName = name, variant = Nothing, state = Nothing, slots = [] }


render : ScreenNode -> Query.Single msg
render node =
    Renderer.renderScreenNode Dict.empty Dict.empty [] [] node
        |> Query.fromHtml
