module Pages.TokenStudio exposing (viewTokenStudio)

import Html exposing (Html, button, div, h4, li, span, text, ul)
import Html.Attributes exposing (style, value)
import Html.Events exposing (onClick, onInput)
import Themes exposing (Theme)
import Tokens
import Types exposing (..)


viewTokenStudio : Model -> Html Msg
viewTokenStudio model =
    case model.tokens of
        Nothing ->
            text "Loading tokens..."

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
            div [ style "background" "#fff", style "padding" "1rem", style "border" "1px solid #ccc", style "border-radius" "8px" ]
                [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "center", style "margin-bottom" "1rem" ]
                    [ div []
                        [ h4 [ style "margin" "0 0 0.5rem 0" ] [ text "Token Studio" ]
                        , div [ style "display" "flex", style "gap" "0.5rem", style "align-items" "center" ]
                            [ Html.select
                                [ onInput
                                    (\val ->
                                        SelectTheme
                                            (if val == "" then
                                                Nothing

                                             else
                                                Just val
                                            )
                                    )
                                , style "padding" "0.5rem"
                                ]
                                (Html.option [ value "" ] [ text "Base Theme" ]
                                    :: List.map (\t -> Html.option [ value t.name, Html.Attributes.selected (model.activeThemeName == Just t.name) ] [ text t.name ]) model.themes
                                )
                            , Html.input
                                [ value model.newThemeName
                                , onInput UpdateNewThemeName
                                , Html.Attributes.placeholder "New theme name"
                                , style "padding" "0.5rem"
                                ]
                                []
                            , button [ onClick CreateTheme, style "padding" "0.5rem" ] [ text "Create Theme" ]
                            ]
                        ]
                    , button [ onClick SaveTokens, style "padding" "0.5rem 1rem", style "background" "#28a745", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ]
                        [ text
                            (if model.activeThemeName == Nothing then
                                "Save Base Tokens"

                             else
                                "Save Theme"
                            )
                        ]
                    ]
                , if List.isEmpty displayTokens then
                    text "No tokens found."

                  else
                    ul [ style "list-style" "none", style "padding" "0" ]
                        (List.map (\( path, token ) -> viewTokenEditor path token activeThemeObj displayTokens) displayTokens)
                , div [ style "margin-top" "2rem", style "padding-top" "1rem", style "border-top" "1px solid #eee" ]
                    [ h4 [ style "margin" "0 0 1rem 0" ] [ text "Create New Token" ]
                    , div [ style "display" "flex", style "gap" "1rem", style "align-items" "center" ]
                        [ Html.input
                            [ value model.newTokenPath
                            , onInput UpdateNewTokenPath
                            , Html.Attributes.placeholder "Path (e.g. color.primary)"
                            , style "padding" "0.5rem"
                            ]
                            []
                        , Html.select
                            [ onInput UpdateNewTokenType
                            , style "padding" "0.5rem"
                            ]
                            [ Html.option [ value "color", Html.Attributes.selected (model.newTokenType == "color") ] [ text "Color" ]
                            , Html.option [ value "dimension", Html.Attributes.selected (model.newTokenType == "dimension") ] [ text "Dimension" ]
                            , Html.option [ value "typography", Html.Attributes.selected (model.newTokenType == "typography") ] [ text "Typography" ]
                            ]
                        , Html.input
                            [ value model.newTokenValue
                            , onInput UpdateNewTokenValue
                            , Html.Attributes.placeholder "Value or {alias}"
                            , style "padding" "0.5rem"
                            ]
                            []
                        , button [ onClick CreateToken, style "padding" "0.5rem" ] [ text "Add Token" ]
                        ]
                    ]
                ]


viewTokenEditor : Tokens.TokenPath -> Tokens.DesignToken -> Maybe Theme -> List Tokens.FlatToken -> Html Msg
viewTokenEditor path token activeThemeObj displayTokens =
    let
        pathString =
            String.join "." path

        isOverridden =
            case activeThemeObj of
                Just theme ->
                    List.any (\( p, _ ) -> p == path) theme.overrides

                Nothing ->
                    False

        resolvedColor =
            if token.type_ == "color" then
                Tokens.resolveAlias displayTokens token.value

            else
                ""
    in
    li [ style "display" "flex", style "align-items" "center", style "padding" "0.5rem 0", style "border-bottom" "1px solid #eee" ]
        [ div [ style "width" "200px", style "font-family" "monospace", style "font-weight" "bold" ] [ text pathString ]
        , if token.type_ == "color" then
            div [ style "width" "24px", style "height" "24px", style "background" resolvedColor, style "margin-right" "1rem", style "border" "1px solid #ccc", style "border-radius" "4px" ] []

          else
            text ""
        , Html.input
            [ value token.value
            , onInput (UpdateToken path)
            , style "flex" "1"
            , style "padding" "0.5rem"
            , style "border" "1px solid #ccc"
            , style "border-radius" "4px"
            ]
            []
        , div [ style "width" "100px", style "margin-left" "1rem", style "color" "#666", style "font-size" "0.9em" ] [ text token.type_ ]
        , if isOverridden then
            span [ style "margin-left" "1rem", style "background" "#ffeeba", style "padding" "0.2rem 0.5rem", style "border-radius" "4px", style "font-size" "0.8em" ] [ text "Overridden" ]

          else
            text ""
        ]
