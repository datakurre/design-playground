module Pages.TokenStudio exposing (viewTokenStudio)

import Dict
import Help
import Html exposing (Html, button, div, h3, li, span, text, ul)
import Html.Attributes exposing (style, value)
import Html.Events exposing (onClick, onInput)
import Set
import Tailwind as Tw exposing (classes)
import Tailwind.Theme exposing (amber, s0, s0_dot_5, s1, s100, s2, s24, s300, s32, s4, s48, s6, s8, s800, slate)
import Themes exposing (Theme)
import Tokens
import Templates
import Types exposing (..)
import Ui


viewTokenStudio : Model -> Html Msg
viewTokenStudio model =
    case model.tokens of
        Nothing ->
            div [ Ui.muted ] [ text "Loading tokens..." ]

        Just baseTokens ->
            let
                -- Determine which tokens to show based on active theme
                displayTokens =
                    case model.activeThemeName of
                        Nothing ->
                            baseTokens

                        Just activeName ->
                            let
                                activeTheme =
                                    List.filter (\t -> t.name == activeName) model.themes |> List.head
                            in
                            case activeTheme of
                                Just theme ->
                                    Themes.applyTheme baseTokens theme

                                Nothing ->
                                    baseTokens

                activeThemeObj =
                    model.activeThemeName |> Maybe.andThen (\name -> List.filter (\t -> t.name == name) model.themes |> List.head)
            in
            div [ Ui.panel ]
                [ viewToolbar model
                , Html.datalist [ Html.Attributes.id "token-alias-list" ]
                    (List.map (\( p, _ ) -> Html.option [ value ("{" ++ String.join "." p ++ "}") ] []) displayTokens)
                , Html.datalist [ Html.Attributes.id "token-groups-list" ]
                    (List.map (\p -> Html.option [ value p ] []) (tokenGroupPaths displayTokens))
                , if List.isEmpty displayTokens then
                    viewEmptyState model

                  else
                    ul [ classes [ Tw.list_none, Tw.p s0, Tw.mt s4 ] ]
                        (List.map (\( path, token ) -> viewTokenEditor model path token activeThemeObj displayTokens) displayTokens)
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


{-| The unique group prefixes of every token path, e.g. `color.primary.500`
contributes `color` and `color.primary` (but not the full leaf path). Used to
suggest consistent, nested names when creating a new token. Mirrors the
identically-named helper in `Pages.ComponentRegistry`, which needs the same
computation for its contract-rule suggestions.
-}
tokenGroupPaths : List Tokens.FlatToken -> List String
tokenGroupPaths tokens =
    tokens
        |> List.concatMap (\( path, _ ) -> properPrefixes path)
        |> List.map (String.join ".")
        |> Set.fromList
        |> Set.toList


properPrefixes : List String -> List (List String)
properPrefixes path =
    List.range 1 (List.length path - 1)
        |> List.map (\n -> List.take n path)


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


viewTokenEditor : Model -> Tokens.TokenPath -> Tokens.DesignToken -> Maybe Theme -> List Tokens.FlatToken -> Html Msg
viewTokenEditor model path token activeThemeObj displayTokens =
    let
        pathString =
            String.join "." path

        isOverridden =
            case activeThemeObj of
                Just theme ->
                    List.any (\( p, _ ) -> p == path) theme.overrides

                Nothing ->
                    False

        resolvedColorStr =
            if token.type_ == "color" then
                case token.value of
                    Tokens.StringValue s ->
                        case Tokens.resolveAliasValue displayTokens (Tokens.StringValue s) of
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
                        , Html.select
                            [ Ui.selectInput
                            , Html.Attributes.attribute "aria-label" ("Point " ++ pathString ++ " at another token")
                            , onInput
                                (\v ->
                                    if v /= "" then
                                        UpdateToken path ("{" ++ v ++ "}")

                                    else
                                        UpdateToken path s
                                )
                            ]
                            (Html.option [ value "" ] [ text "Use another token..." ]
                                :: List.map (\( p, _ ) -> Html.option [ value (String.join "." p) ] [ text (String.join "." p) ]) displayTokens
                            )
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
                                    , value model.newCompositePropertyName
                                    , onInput UpdateNewCompositePropertyName
                                    , Html.Attributes.spellcheck False
                                    , classes [ Tw.w s32 ]
                                    ]
                                    []
                                , button [ Ui.btnSmall, onClick (AddCompositeProperty path model.newCompositePropertyName) ]
                                    [ text "Add part" ]
                                ]
                           ]
                    )
        ]
