module Pages.TokenStudio exposing (RowContext, viewTokenList, viewTokenStudio)

{-| The Tokens tab.

`viewTokenList` and the `RowContext` it takes are exposed for `TokenStudioTest`.
It takes what it actually needs rather than a whole `Model`, which keeps the
part with behaviour worth locking down easy to test and easy to read.
`Renderer.renderScreenNode` is shaped the same way.

This started as a workaround: a `Model` carried a `Nav.Key`, so nothing taking
one was reachable from a test at all. `Effect` fixed that, and the shape stayed
because it was the better one anyway.

-}

import Dict
import Help
import Html exposing (Html, button, div, h3, li, span, text)
import Html.Attributes exposing (style, value)
import Html.Events exposing (onCheck, onClick, onInput)
import Html.Keyed
import Set
import Tailwind as Tw exposing (classes)
import Tailwind.Theme exposing (amber, s0, s0_dot_5, s1, s100, s2, s200, s24, s3, s300, s32, s4, s48, s500, s6, s64, s700, s8, s800, slate)
import Templates
import Themes exposing (Theme)
import TokenBrowse exposing (Node(..))
import Tokens
import Types exposing (..)
import Ui


viewTokenStudio : Model -> Html Msg
viewTokenStudio model =
    case model.tokens of
        Nothing ->
            div [ Ui.muted ] [ text "Loading tokens..." ]

        Just baseTokens ->
            let
                activeThemeObj =
                    model.activeThemeName |> Maybe.andThen (\name -> List.filter (\t -> t.name == name) model.themes |> List.head)

                displayTokens =
                    Themes.resolve baseTokens model.themes model.activeThemeName

                -- The two questions a token can't answer about itself. `changed`
                -- compares the base list, because `originalTokens` is the last
                -- committed *base* file — themes are never snapshotted, which is
                -- why that filter is offered on the base theme only.
                marks =
                    { overridden = TokenBrowse.pathSet (Maybe.withDefault [] (Maybe.map .overrides activeThemeObj))
                    , changed = TokenBrowse.changedPaths (Maybe.withDefault [] model.originalTokens) baseTokens
                    }

                filters =
                    { search = model.tokenSearch
                    , type_ = model.tokenTypeFilter
                    , overriddenOnly = model.tokenOverriddenOnly
                    , changedOnly = model.tokenChangedOnly
                    }

                visibleTokens =
                    TokenBrowse.apply marks filters displayTokens

                rowContext =
                    { newPartName = model.newCompositePropertyName
                    , activeTheme = activeThemeObj
                    , displayTokens = displayTokens
                    }
            in
            div [ Ui.panel ]
                [ viewToolbar model
                , Html.datalist [ Html.Attributes.id "token-alias-list" ]
                    (List.map (\( p, _ ) -> Html.option [ value ("{" ++ String.join "." p ++ "}") ] []) displayTokens)
                , Html.datalist [ Html.Attributes.id "token-groups-list" ]
                    (List.map (\p -> Html.option [ value p ] []) (TokenBrowse.groupPaths displayTokens))
                , if List.isEmpty displayTokens then
                    viewEmptyState model

                  else
                    div []
                        [ viewFilters model filters (List.length visibleTokens) (List.length displayTokens)
                        , viewTokenList rowContext filters marks visibleTokens
                        ]
                , if model.activeThemeName == Nothing then
                    viewNewToken model

                  else
                    div [ Ui.muted, classes [ Tw.mt s6, Tw.pt s4 ], Ui.divider ]
                        [ text "Switch to the base theme to define a new token. A theme can only override tokens that already exist." ]
                ]


viewToolbar : Model -> Html Msg
viewToolbar model =
    div [ classes [ Tw.flex, Tw.justify_between, Tw.items_center, Tw.gap s4, Tw.flex_wrap ] ]
        [ div []
            [ h3 [ Ui.pageTitle ] [ text "Tokens" ]
            , div [ classes [ Tw.flex, Tw.gap s2, Tw.items_center, Tw.mt s2 ] ]
                [ Ui.themePicker (List.map .name model.themes) model.activeThemeName SelectTheme
                , Ui.contextHelp Help.themes
                , Html.input
                    [ Ui.textInput
                    , value model.newThemeName
                    , onInput UpdateNewThemeName
                    , Html.Attributes.placeholder "New theme name"
                    ]
                    []
                , Html.select
                    [ Ui.selectInput
                    , onInput UpdateNewThemeTemplate
                    , value model.newThemeTemplate
                    , Html.Attributes.attribute "aria-label" "Start from"
                    ]
                    (List.map (\t -> Html.option [ value t.id ] [ text t.label ]) Templates.themeTemplates)
                , button [ Ui.btnNeutral, onClick CreateTheme ] [ text "Add theme" ]
                , if model.activeThemeName == Nothing then
                    button [ Ui.btnNeutral, onClick ApplyStarterTokenScale ] [ text "Add starter scale" ]

                  else
                    text ""
                ]
            ]
        , div [ classes [ Tw.flex, Tw.gap s2 ] ]
            [ button [ Ui.btnPrimary, onClick SaveTokens ]
                [ text
                    (if model.activeThemeName == Nothing then
                        "Save tokens"

                     else
                        "Save theme"
                    )
                ]
            , if model.activeThemeName /= Nothing then
                button [ Ui.btnDanger, onClick (DeleteTheme (Maybe.withDefault "" model.activeThemeName)) ]
                    [ text "Delete theme" ]

              else
                text ""
            ]
        ]


{-| A repository with no tokens/tokens.json yet is the normal starting point,
so this is an invitation rather than the red error it used to be.
-}
viewEmptyState : Model -> Html Msg
viewEmptyState model =
    div [ classes [ Tw.py s6, Tw.text_center ] ]
        [ div [ Ui.muted ]
            [ text
                (if model.activeThemeName == Nothing then
                    "No tokens yet. Add your first one below, or click \"Add starter scale\" above for an opinionated color / spacing / font-size ramp to start from."

                 else
                    "This theme doesn't override anything yet."
                )
            ]
        ]


{-| What a row needs, which is much less than the whole `Model`. Passing the
model made every row look like it depended on all of it.
-}
type alias RowContext =
    { newPartName : String
    , activeTheme : Maybe Theme
    , displayTokens : List Tokens.FlatToken
    }


{-| The row of controls that narrows the list. A design system runs to hundreds
of tokens, and until this existed the only way to reach one was to scroll.
-}
viewFilters : Model -> TokenBrowse.Filters -> Int -> Int -> Html Msg
viewFilters model filters shown total =
    div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.flex_wrap, Tw.mt s4 ] ]
        [ Html.input
            [ Ui.textInput
            , Html.Attributes.type_ "search"
            , value model.tokenSearch
            , onInput UpdateTokenSearch
            , Html.Attributes.placeholder "Find a token"
            , Html.Attributes.attribute "aria-label" "Find a token"
            , Html.Attributes.spellcheck False
            , classes [ Tw.w s64 ]
            ]
            []
        , Html.select
            [ Ui.selectInput
            , onInput UpdateTokenTypeFilter
            , Html.Attributes.attribute "aria-label" "Filter by type"
            ]
            (List.map
                (\( optionValue, label ) ->
                    Html.option [ value optionValue, Html.Attributes.selected (model.tokenTypeFilter == optionValue) ]
                        [ text label ]
                )
                [ ( "", "All types" ), ( "color", "Color" ), ( "dimension", "Dimension" ), ( "typography", "Typography" ) ]
            )

        -- Each of these only has an answer in one of the two modes, so only one
        -- of them is ever on screen. See `Model.tokenChangedOnly`.
        , if model.activeThemeName == Nothing then
            viewFilterCheckbox "Unsaved changes only" model.tokenChangedOnly ToggleTokenChangedOnly

          else
            viewFilterCheckbox "Overridden only" model.tokenOverriddenOnly ToggleTokenOverriddenOnly
        , Ui.contextHelp Help.tokenFilters
        , if TokenBrowse.filtersActive filters then
            span [ Ui.mutedSmall ]
                [ text (String.fromInt shown ++ " of " ++ String.fromInt total ++ " tokens") ]

          else
            text ""
        ]


viewFilterCheckbox : String -> Bool -> Msg -> Html Msg
viewFilterCheckbox label isOn toMsg =
    Html.label
        [ classes
            [ Tw.inline_flex
            , Tw.items_center
            , Tw.gap s1
            , Tw.text_xs
            , Tw.text_color (slate s500)
            , Tw.cursor_pointer
            ]
        ]
        [ Html.input
            [ Html.Attributes.type_ "checkbox"
            , Html.Attributes.checked isOn
            , onCheck (\_ -> toMsg)
            , classes [ Tw.cursor_pointer ]
            ]
            []
        , text label
        ]


{-| Grouped while you're browsing, flat while you're searching.

Filtering deliberately drops the groups rather than expanding the ones that
contain a match: a `<details>` is open or closed in the DOM, so once someone has
toggled one by hand the vdom's `open` attribute no longer moves it, and a tree
that only _sometimes_ expands to your match is worse than no tree.

-}
viewTokenList : RowContext -> TokenBrowse.Filters -> TokenBrowse.Marks -> List Tokens.FlatToken -> Html Msg
viewTokenList context filters marks visibleTokens =
    if TokenBrowse.filtersActive filters then
        if List.isEmpty visibleTokens then
            viewNoMatches filters marks

        else
            Html.Keyed.ul [ classes [ Tw.list_none, Tw.p s0, Tw.mt s2 ] ]
                (List.map (viewLeaf context) visibleTokens)

    else
        Html.Keyed.ul [ classes [ Tw.list_none, Tw.p s0, Tw.mt s2 ] ]
            (List.map (viewNode context (List.length visibleTokens)) (TokenBrowse.tree visibleTokens))


{-| Keyed, because a group's open/closed state lives in the DOM rather than in
the model: without keys, deleting a token shifts the list and the wrong group
stays open.
-}
viewNode : RowContext -> Int -> Node -> ( String, Html Msg )
viewNode context total node =
    case node of
        Leaf token ->
            viewLeaf context token

        Group group ->
            ( "group:" ++ String.join "." group.path
            , li []
                [ Html.details
                    (if total <= smallEnoughToShowInFull then
                        [ Html.Attributes.attribute "open" "" ]

                     else
                        []
                    )
                    [ Html.summary
                        [ classes
                            [ Tw.flex
                            , Tw.items_center
                            , Tw.gap s2
                            , Tw.py s2
                            , Tw.cursor_pointer
                            , Tw.select_none
                            , Tw.font_mono
                            , Tw.text_xs
                            , Tw.font_medium
                            , Tw.text_color (slate s700)
                            ]
                        ]
                        [ text group.label
                        , span [ Ui.mutedSmall ] [ text ("(" ++ String.fromInt group.count ++ ")") ]
                        ]
                    , Html.Keyed.ul
                        [ classes
                            [ Tw.list_none
                            , Tw.p s0
                            , Tw.pl s3
                            , Tw.ml s2
                            , Tw.border_l
                            , Tw.border_color (slate s200)
                            ]
                        ]
                        (List.map (viewNode context total) group.children)
                    ]
                ]
            )


viewLeaf : RowContext -> Tokens.FlatToken -> ( String, Html Msg )
viewLeaf context ( path, token ) =
    ( String.join "." path, viewTokenEditor context path token )


{-| A list that fits on screen shouldn't be hidden behind folders; a list that
doesn't should open with the shape of the system rather than a wall of rows.
-}
smallEnoughToShowInFull : Int
smallEnoughToShowInFull =
    12


viewNoMatches : TokenBrowse.Filters -> TokenBrowse.Marks -> Html Msg
viewNoMatches filters marks =
    div [ classes [ Tw.py s6, Tw.text_center ] ]
        [ div [ Ui.muted ]
            [ text
                (if filters.changedOnly && Set.isEmpty marks.changed then
                    "Nothing has changed since the last commit."

                 else
                    "No token matches what you're filtering by."
                )
            ]
        , div [ classes [ Tw.mt s2 ] ]
            [ button [ Ui.btnNeutral, onClick ClearTokenFilters ] [ text "Clear filters" ] ]
        ]


viewNewToken : Model -> Html Msg
viewNewToken model =
    div [ classes [ Tw.mt s6, Tw.pt s4 ], Ui.divider ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
            [ h3 [ Ui.sectionTitle ] [ text "Add a token" ]
            , Ui.contextHelp Help.newToken
            ]
        , div [ classes [ Tw.flex, Tw.gap s2, Tw.items_center, Tw.flex_wrap ] ]
            [ Html.input
                [ Ui.textInput
                , value model.newTokenPath
                , onInput UpdateNewTokenPath
                , Html.Attributes.placeholder "Name, e.g. color.primary"
                , Html.Attributes.attribute "aria-label" "Token name"
                , Html.Attributes.attribute "list" "token-groups-list"
                , Html.Attributes.spellcheck False
                ]
                []
            , Html.select
                [ Ui.selectInput
                , onInput UpdateNewTokenType
                , Html.Attributes.attribute "aria-label" "Token type"
                ]
                [ Html.option [ value "color", Html.Attributes.selected (model.newTokenType == "color") ] [ text "Color" ]
                , Html.option [ value "dimension", Html.Attributes.selected (model.newTokenType == "dimension") ] [ text "Dimension" ]
                , Html.option [ value "typography", Html.Attributes.selected (model.newTokenType == "typography") ] [ text "Typography" ]
                ]
            , Html.input
                [ Ui.textInput
                , value model.newTokenValue
                , onInput UpdateNewTokenValue
                , Html.Attributes.placeholder "Value, or {another.token}"
                , Html.Attributes.attribute "aria-label" "Token value"
                , Html.Attributes.attribute "list" "token-alias-list"
                , Html.Attributes.spellcheck False
                ]
                []
            , if model.newTokenType == "color" then
                viewColorWell model.newTokenValue UpdateNewTokenValue

              else
                text ""
            , button [ Ui.btnNeutral, onClick CreateToken ] [ text "Add" ]
            ]
        ]


{-| The native colour input, sized to match the text inputs beside it.
-}
viewColorWell : String -> (String -> Msg) -> Html Msg
viewColorWell currentValue toMsg =
    Html.input
        [ Html.Attributes.type_ "color"
        , Html.Attributes.attribute "aria-label" "Pick a colour"
        , value
            (if String.startsWith "#" currentValue then
                String.left 7 currentValue

             else
                "#000000"
            )
        , onInput toMsg
        , classes
            [ Tw.w s8
            , Tw.h s8
            , Tw.p s0
            , Tw.border
            , Tw.border_color (slate s300)
            , Tw.rounded_md
            , Tw.cursor_pointer
            ]
        ]
        []


viewTokenEditor : RowContext -> Tokens.TokenPath -> Tokens.DesignToken -> Html Msg
viewTokenEditor context path token =
    let
        pathString =
            String.join "." path

        isOverridden =
            case context.activeTheme of
                Just theme ->
                    List.any (\( p, _ ) -> p == path) theme.overrides

                Nothing ->
                    False

        resolvedColorStr =
            if token.type_ == "color" then
                case token.value of
                    Tokens.StringValue s ->
                        case Tokens.resolveAliasValue context.displayTokens (Tokens.StringValue s) of
                            Tokens.StringValue r ->
                                r

                            _ ->
                                s

                    _ ->
                        ""

            else
                ""
    in
    li [ classes [ Tw.flex, Tw.flex_col, Tw.py s2 ], Ui.divider, classes [ Tw.border_t_0, Tw.border_b ] ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.w_full ] ]
            [ div [ classes [ Tw.w s48, Tw.font_mono, Tw.text_xs, Tw.text_color (slate s800), Tw.truncate ] ]
                [ text pathString ]
            , case token.value of
                Tokens.StringValue s ->
                    div [ classes [ Tw.flex, Tw.flex_1, Tw.items_center, Tw.gap s2 ] ]
                        [ if token.type_ == "color" then
                            div
                                [ style "background" resolvedColorStr
                                , classes [ Tw.w s6, Tw.h s6, Tw.rounded_md, Tw.border, Tw.border_color (slate s300) ]
                                ]
                                []

                          else
                            text ""
                        , Html.input
                            [ Ui.textInput
                            , value s
                            , onInput (UpdateToken path)
                            , Html.Attributes.attribute "aria-label" ("Value of " ++ pathString)
                            , Html.Attributes.attribute "list" "token-alias-list"
                            , Html.Attributes.spellcheck False
                            , classes [ Tw.flex_1 ]
                            ]
                            []
                        , if token.type_ == "color" then
                            viewColorWell resolvedColorStr (UpdateToken path)

                          else
                            text ""

                        -- There used to be a "Use another token..." <select>
                        -- here, listing every token, on every row: quadratic
                        -- markup, and the single reason a few hundred tokens
                        -- brought the tab to a stop. The value input beside it
                        -- already offers the same `{path}` completions from
                        -- `#token-alias-list`, which is built once.
                        ]

                Tokens.CompositeValue _ ->
                    div [ Ui.muted, classes [ Tw.flex_1, Tw.italic ] ] [ text "Several values" ]
            , div [ Ui.mutedSmall, classes [ Tw.w s24 ] ] [ text token.type_ ]
            , if isOverridden then
                span
                    [ classes
                        [ Tw.px s2
                        , Tw.py s0_dot_5
                        , Tw.rounded_full
                        , Tw.text_xs
                        , Tw.font_medium
                        , Tw.bg_color (amber s100)
                        , Tw.text_color (amber s800)
                        ]
                    ]
                    [ text "Overridden" ]

              else
                text ""
            , button
                [ Ui.iconButton
                , onClick (DeleteToken path)
                , Html.Attributes.attribute "aria-label" ("Delete " ++ pathString)
                , Html.Attributes.title ("Delete " ++ pathString)
                ]
                [ text "×" ]
            ]
        , case token.value of
            Tokens.StringValue _ ->
                div [ classes [ Tw.ml s48, Tw.mt s1 ] ]
                    [ button [ Ui.btnQuiet, onClick (AddCompositeProperty path "newProperty") ]
                        [ text "Split into parts" ]
                    ]

            Tokens.CompositeValue dict ->
                div [ Ui.panelSunken, classes [ Tw.ml s48, Tw.mt s1 ] ]
                    ((Dict.toList dict
                        |> List.map
                            (\( prop, val ) ->
                                div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s1 ] ]
                                    [ div [ Ui.fieldLabel, classes [ Tw.w s32 ] ] [ text prop ]
                                    , Html.input
                                        [ Ui.textInput
                                        , value val
                                        , onInput (UpdateCompositeToken path prop)
                                        , Html.Attributes.attribute "aria-label" (prop ++ " of " ++ pathString)
                                        , Html.Attributes.attribute "list" "token-alias-list"
                                        , Html.Attributes.spellcheck False
                                        , classes [ Tw.flex_1 ]
                                        ]
                                        []
                                    , button
                                        [ Ui.iconButton
                                        , onClick (DeleteCompositeProperty path prop)
                                        , Html.Attributes.attribute "aria-label" ("Remove " ++ prop)
                                        , Html.Attributes.title ("Remove " ++ prop)
                                        ]
                                        [ text "×" ]
                                    ]
                            )
                     )
                        ++ [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mt s2, Tw.pt s2 ], Ui.divider ]
                                [ Html.input
                                    [ Ui.textInput
                                    , Html.Attributes.placeholder "Part name"
                                    , Html.Attributes.attribute "aria-label" "New part name"
                                    , value context.newPartName
                                    , onInput UpdateNewCompositePropertyName
                                    , Html.Attributes.spellcheck False
                                    , classes [ Tw.w s32 ]
                                    ]
                                    []
                                , button [ Ui.btnSmall, onClick (AddCompositeProperty path context.newPartName) ]
                                    [ text "Add part" ]
                                , button [ Ui.btnDanger, onClick (RevertToSingleValue path) ]
                                    [ text "Revert to single value" ]
                                ]
                           ]
                    )
        ]
