module Pages.TokenStudio exposing (viewTokenStudio)

import Dict
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
                    , div [ style "display" "flex", style "gap" "0.5rem" ]
                        [ button [ onClick SaveTokens, style "padding" "0.5rem 1rem", style "background" "#28a745", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ]
                            [ text
                                (if model.activeThemeName == Nothing then
                                    "Save Base Tokens"
    
                                 else
                                    "Save Theme"
                                )
                            ]
                        , if model.activeThemeName /= Nothing then
                            button [ onClick (DeleteTheme (Maybe.withDefault "" model.activeThemeName)), style "padding" "0.5rem 1rem", style "background" "#dc3545", style "color" "white", style "border" "none", style "border-radius" "4px", style "cursor" "pointer" ]
                                [ text "Delete Theme" ]
                          else
                            text ""
                        ]
                    ]
                , if List.isEmpty displayTokens then
                    text "No tokens found."

                  else
                    ul [ style "list-style" "none", style "padding" "0" ]
                        (List.map (\( path, token ) -> viewTokenEditor model path token activeThemeObj displayTokens) displayTokens)
                , if model.activeThemeName == Nothing then
                    div [ style "margin-top" "2rem", style "padding-top" "1rem", style "border-top" "1px solid #eee" ]
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
                            , if model.newTokenType == "color" then
                                Html.input
                                    [ Html.Attributes.type_ "color"
                                    , value (if String.startsWith "#" model.newTokenValue then String.left 7 model.newTokenValue else "#000000")
                                    , onInput UpdateNewTokenValue
                                    , style "margin-left" "0.5rem"
                                    , style "padding" "0"
                                    , style "border" "none"
                                    , style "width" "32px"
                                    , style "height" "32px"
                                    , style "cursor" "pointer"
                                    ]
                                    []
                              else
                                text ""
                            , button [ onClick CreateToken, style "padding" "0.5rem" ] [ text "Add Token" ]
                            ]
                        ]
                  else
                    div [ style "margin-top" "2rem", style "padding-top" "1rem", style "border-top" "1px solid #eee", style "color" "#666", style "font-style" "italic" ]
                        [ text "To define a new token, switch to the Base Theme first." ]
                ]


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
                            Tokens.StringValue r -> r
                            _ -> s
                    _ -> ""

            else
                ""
    in
    li [ style "display" "flex", style "flex-direction" "column", style "padding" "0.5rem 0", style "border-bottom" "1px solid #eee" ]
        [ div [ style "display" "flex", style "align-items" "center", style "width" "100%" ]
            [ div [ style "width" "200px", style "font-family" "monospace", style "font-weight" "bold" ] [ text pathString ]
            , case token.value of
                Tokens.StringValue s ->
                    div [ style "display" "flex", style "flex" "1", style "align-items" "center" ]
                        [ if token.type_ == "color" then
                            div [ style "width" "24px", style "height" "24px", style "background" resolvedColorStr, style "margin-right" "1rem", style "border" "1px solid #ccc", style "border-radius" "4px" ] []
                          else
                            text ""
                        , Html.input
                            [ value s
                            , onInput (UpdateToken path)
                            , style "flex" "1"
                            , style "padding" "0.5rem"
                            , style "border" "1px solid #ccc"
                            , style "border-radius" "4px"
                            ]
                            []
                        , if token.type_ == "color" then
                            Html.input
                                [ Html.Attributes.type_ "color"
                                , value (if String.startsWith "#" resolvedColorStr then String.left 7 resolvedColorStr else "#000000")
                                , onInput (UpdateToken path)
                                , style "margin-left" "0.5rem"
                                , style "padding" "0"
                                , style "border" "none"
                                , style "width" "32px"
                                , style "height" "32px"
                                , style "cursor" "pointer"
                                ]
                                []
                          else
                            text ""
                        , Html.select
                            [ onInput (\v -> if v /= "" then UpdateToken path ("{" ++ v ++ "}") else UpdateToken path s)
                            , style "margin-left" "0.5rem"
                            , style "padding" "0.5rem"
                            , style "border" "1px solid #ccc"
                            , style "border-radius" "4px"
                            ]
                            (Html.option [ value "" ] [ text "Reference..." ]
                                :: List.map (\( p, _ ) -> Html.option [ value (String.join "." p) ] [ text (String.join "." p) ]) displayTokens
                            )
                        ]
                
                Tokens.CompositeValue dict ->
                    div [ style "flex" "1", style "font-style" "italic", style "color" "#666" ] [ text "Composite Token" ]

            , div [ style "width" "100px", style "margin-left" "1rem", style "color" "#666", style "font-size" "0.9em" ] [ text token.type_ ]
            , if isOverridden then
                span [ style "margin-left" "1rem", style "background" "#ffeeba", style "padding" "0.2rem 0.5rem", style "border-radius" "4px", style "font-size" "0.8em" ] [ text "Overridden" ]

              else
                text ""
            , button [ onClick (DeleteToken path), style "margin-left" "1rem", style "padding" "0.2rem 0.5rem", style "background" "transparent", style "border" "none", style "color" "#dc3545", style "cursor" "pointer", style "font-size" "1.2rem" ] [ text "×" ]
            ]
        , case token.value of
            Tokens.StringValue _ ->
                div [ style "margin-left" "200px", style "margin-top" "0.5rem" ]
                    [ button [ onClick (AddCompositeProperty path "newProperty"), style "padding" "0.2rem 0.5rem", style "font-size" "0.8rem", style "cursor" "pointer" ] [ text "Convert to Composite" ] ]
            
            Tokens.CompositeValue dict ->
                div [ style "margin-left" "200px", style "margin-top" "0.5rem", style "background" "#f9f9f9", style "padding" "1rem", style "border-radius" "4px", style "border" "1px solid #eee" ]
                    ( (Dict.toList dict
                        |> List.map (\(prop, val) ->
                            div [ style "display" "flex", style "align-items" "center", style "margin-bottom" "0.5rem" ]
                                [ div [ style "width" "120px", style "font-weight" "bold", style "font-size" "0.9em" ] [ text prop ]
                                , Html.input [ value val, onInput (UpdateCompositeToken path prop), style "flex" "1", style "padding" "0.3rem", style "border" "1px solid #ccc", style "border-radius" "4px" ] []
                                , button [ onClick (DeleteCompositeProperty path prop), style "margin-left" "0.5rem", style "padding" "0.2rem 0.5rem", style "background" "#ffdddd", style "border" "none", style "cursor" "pointer", style "border-radius" "4px" ] [ text "X" ]
                                ]
                        )
                      ) ++ 
                      [ div [ style "display" "flex", style "align-items" "center", style "margin-top" "0.5rem", style "border-top" "1px solid #ddd", style "padding-top" "0.5rem" ]
                        [ Html.input [ Html.Attributes.placeholder "New Property Name", value model.newCompositePropertyName, onInput UpdateNewCompositePropertyName, style "width" "120px", style "padding" "0.3rem", style "margin-right" "0.5rem", style "border" "1px solid #ccc", style "border-radius" "4px" ] []
                        , button [ onClick (AddCompositeProperty path model.newCompositePropertyName), style "padding" "0.3rem 1rem", style "cursor" "pointer" ] [ text "Add Property" ]
                        ]
                      ]
                    )
        ]
