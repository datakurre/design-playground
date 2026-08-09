module TokenStudioTest exposing (suite)

import Expect
import Html.Attributes
import Pages.TokenStudio as TokenStudio
import Set
import Test exposing (..)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import TokenBrowse
import Tokens
import Types


{-| The token list is the one part of this tab reachable from a test:
`viewTokenStudio` takes a `Model`, and a `Model` needs a `Nav.Key`. See the same
note on `RendererTest`.

What's locked here is what makes the tab survive a real design system — the list
is grouped rather than flat, searching flattens it again, and a row does not
carry a control listing every other token.

-}
suite : Test
suite =
    describe "Pages.TokenStudio token list"
        [ describe "browsing"
            [ -- color, its two ramps, and spacing.
              test "groups tokens under a disclosure per path segment" <|
                \_ ->
                    render TokenBrowse.noFilters manyTokens
                        |> Query.findAll [ Selector.tag "summary" ]
                        |> Query.count (Expect.equal 4)
            , test "a group heading says how many tokens are under it" <|
                \_ ->
                    render TokenBrowse.noFilters manyTokens
                        |> Query.findAll [ Selector.tag "summary" ]
                        |> Query.index 1
                        |> Query.has [ Selector.text "brand", Selector.text "(10)" ]
            , test "a long list opens collapsed, so the shape shows before the rows" <|
                \_ ->
                    render TokenBrowse.noFilters manyTokens
                        |> Query.findAll [ Selector.tag "details", Selector.attribute (Html.Attributes.attribute "open" "") ]
                        |> Query.count (Expect.equal 0)
            , test "a list that fits on screen opens expanded" <|
                \_ ->
                    render TokenBrowse.noFilters fewTokens
                        |> Query.findAll [ Selector.tag "details", Selector.attribute (Html.Attributes.attribute "open" "") ]
                        |> Query.count (Expect.equal 1)
            , test "every token still gets an editable row" <|
                \_ ->
                    render TokenBrowse.noFilters manyTokens
                        |> Query.findAll [ Selector.tag "input", Selector.attribute (Html.Attributes.attribute "list" "token-alias-list") ]
                        |> Query.count (Expect.equal 21)
            ]
        , describe "filtering"
            [ test "a search flattens the tree into plain results" <|
                \_ ->
                    render { noFilters | search = "brand" } (matching "brand")
                        |> Query.findAll [ Selector.tag "details" ]
                        |> Query.count (Expect.equal 0)
            , test "the flat results are one row per match" <|
                \_ ->
                    render { noFilters | search = "brand" } (matching "brand")
                        |> Query.findAll [ Selector.tag "li" ]
                        |> Query.count (Expect.equal 10)
            , test "no matches offers the way back out" <|
                \_ ->
                    render { noFilters | search = "nothing-is-called-this" } []
                        |> Query.has [ Selector.text "Clear filters" ]
            , test "an empty changed-only filter says why it is empty" <|
                \_ ->
                    render { noFilters | changedOnly = True } []
                        |> Query.has [ Selector.text "Nothing has changed since the last commit." ]
            , test "an empty search says it is the search that found nothing" <|
                \_ ->
                    render { noFilters | search = "nothing-is-called-this" } []
                        |> Query.has [ Selector.text "No token matches what you're filtering by." ]
            ]
        , describe "rows"
            [ -- Every row used to carry a <select> of all tokens: at 400 tokens
              -- that is 160,000 option elements, rebuilt on every keystroke.
              test "a row carries no control listing every other token" <|
                \_ ->
                    render TokenBrowse.noFilters manyTokens
                        |> Query.findAll [ Selector.tag "option" ]
                        |> Query.count (Expect.equal 0)
            ]
        ]


render : TokenBrowse.Filters -> List Tokens.FlatToken -> Query.Single Types.Msg
render filters visibleTokens =
    TokenStudio.viewTokenList context filters marks visibleTokens
        |> Query.fromHtml


context : TokenStudio.RowContext
context =
    { newPartName = "", activeTheme = Nothing, displayTokens = manyTokens }


marks : TokenBrowse.Marks
marks =
    { overridden = Set.empty, changed = Set.empty }


noFilters : TokenBrowse.Filters
noFilters =
    TokenBrowse.noFilters


tok : String -> Tokens.FlatToken
tok path =
    ( String.split "." path
    , { value = Tokens.StringValue "#3b82f6", type_ = "color", description = Nothing }
    )


{-| Two ramps and a spacing step: three top-level disclosures once `color`'s two
children stop it collapsing into a chain.
-}
manyTokens : List Tokens.FlatToken
manyTokens =
    List.map (\step -> tok ("color.brand." ++ String.fromInt step)) steps
        ++ List.map (\step -> tok ("color.gray." ++ String.fromInt step)) steps
        ++ [ tok "spacing.4" ]


steps : List Int
steps =
    [ 50, 100, 200, 300, 400, 500, 600, 700, 800, 900 ]


fewTokens : List Tokens.FlatToken
fewTokens =
    [ tok "color.brand.500", tok "color.brand.50" ]


matching : String -> List Tokens.FlatToken
matching query =
    TokenBrowse.apply marks { noFilters | search = query } manyTokens
