module Pages.ComponentRegistry exposing (viewComponentRegistry)

import Components
import CssProperties
import Dict
import Html exposing (Html, button, div, h3, h4, li, text, ul)
import Html.Attributes exposing (value)
import Html.Events exposing (onClick, onInput)
import Renderer
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (hover)
import Tailwind.Theme exposing (s0, s0_dot_5, s1, s2, s3, s4, s6, s24, s40, s50, s64, s100, s200, s700, s900, slate)
import Themes
import Tokens
import Contracts
import Types exposing (..)
import Ui exposing (PillTone(..))


{-| One node in the layout tree. Layouts nest, so this recurses.
-}
viewLayoutEditorNode : Model -> List Int -> Components.Layout -> Html Msg
viewLayoutEditorNode model path layout =
    let
        ( nodeType, styles, childrenNodes ) =
            case layout of
                Components.Stack props children ->
                    ( "Stack", props.styles, children )

                Components.Grid props children ->
                    ( "Grid", props.styles, children )

                Components.Element props content ->
                    ( "Text", props.styles, [] )
    in
    div
        [ classes
            [ Tw.mb s2
            , Tw.border
            , Tw.border_color (slate s200)
            , Tw.rounded_md
            , Tw.overflow_hidden
            ]
        ]
        [ div
            [ classes
                [ Tw.flex
                , Tw.justify_between
                , Tw.items_center
                , Tw.px s2
                , Tw.py s1
                , Tw.bg_color (slate s50)
                , Tw.border_b
                , Tw.border_color (slate s200)
                ]
            ]
            [ Html.strong [ Ui.fieldLabel ] [ text nodeType ]
            , button
                [ Ui.iconButton
                , onClick (DeleteLayoutNode path)
                , Html.Attributes.attribute "aria-label" ("Remove this " ++ nodeType)
                , Html.Attributes.title ("Remove this " ++ nodeType)
                ]
                [ text "×" ]
            ]
        , div [ classes [ Tw.p s2 ] ]
            [ div [ Ui.fieldLabel, classes [ Tw.mb s1 ] ] [ text "Styles" ]
            , ul [ classes [ Tw.list_none, Tw.p s0, Tw.mb s1 ] ]
                (List.map
                    (\( key, val ) ->
                        li [ classes [ Tw.flex, Tw.gap s2, Tw.items_center, Tw.mb s1 ] ]
                            [ div [ Ui.mutedSmall, classes [ Tw.w s24, Tw.truncate ] ] [ text key ]
                            , Html.input
                                [ Ui.textInput
                                , value val
                                , onInput (UpdateLayoutProperty path key)
                                , Html.Attributes.attribute "aria-label" key
                                , Html.Attributes.attribute "list" "tokensList"
                                , classes [ Tw.flex_1 ]
                                ]
                                []
                            , button
                                [ Ui.iconButton
                                , onClick (RemoveLayoutProperty path key)
                                , Html.Attributes.attribute "aria-label" ("Remove " ++ key)
                                , Html.Attributes.title ("Remove " ++ key)
                                ]
                                [ text "×" ]
                            ]
                    )
                    (Dict.toList styles)
                )
            , div [ classes [ Tw.flex, Tw.gap s2, Tw.items_center ] ]
                [ Html.input
                    [ Ui.textInput
                    , value model.newLayoutPropertyName
                    , onInput UpdateNewLayoutPropertyName
                    , Html.Attributes.placeholder "CSS property"
                    , Html.Attributes.attribute "aria-label" "CSS property"
                    , Html.Attributes.attribute "list" "css-properties-list"
                    , classes [ Tw.w s40 ]
                    ]
                    []
                , Html.input
                    [ Ui.textInput
                    , value model.newLayoutPropertyValue
                    , onInput UpdateNewLayoutPropertyValue
                    , Html.Attributes.placeholder "Value or {token}"
                    , Html.Attributes.attribute "aria-label" "Value"
                    , Html.Attributes.attribute "list" "tokensList"
                    , classes [ Tw.flex_1 ]
                    ]
                    []
                , button [ Ui.btnSmall, onClick (UpdateLayoutProperty path model.newLayoutPropertyName model.newLayoutPropertyValue) ]
                    [ text "Add style" ]
                ]
            ]
        , case layout of
            Components.Element _ content ->
                div [ classes [ Tw.px s2, Tw.pb s2 ] ]
                    [ div [ Ui.fieldLabel, classes [ Tw.mb s1 ] ] [ text "Text" ]
                    , Html.input
                        [ Ui.textInput
                        , value content
                        , onInput (UpdateLayoutText path)
                        , Html.Attributes.attribute "aria-label" "Text content"
                        , classes [ Tw.w_full ]
                        ]
                        []
                    ]

            _ ->
                div [ classes [ Tw.px s2, Tw.pb s2 ] ]
                    [ div [ Ui.fieldLabel, classes [ Tw.mb s1 ] ] [ text "Inside" ]
                    , div [ classes [ Tw.pl s2, Tw.border_l_2, Tw.border_color (slate s100) ] ]
                        (List.indexedMap (\i child -> viewLayoutEditorNode model (path ++ [ i ]) child) childrenNodes)
                    , div [ classes [ Tw.flex, Tw.gap s2, Tw.mt s1 ] ]
                        [ button [ Ui.btnSmall, onClick (AddLayoutStack path) ] [ text "+ Stack" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutGrid path) ] [ text "+ Grid" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutText path "New Text") ] [ text "+ Text" ]
                        ]
                    ]
        ]


viewComponentRegistry : Model -> Html Msg
viewComponentRegistry model =
    case model.components of
        Nothing ->
            div [ Ui.muted ] [ text "Loading components..." ]

        Just components ->
            div [ classes [ Tw.flex, Tw.gap s4, Tw.items_start ] ]
                [ viewComponentList model components
                , div [ classes [ Tw.flex_1 ] ] [ viewSelectedComponent model components ]
                ]


viewComponentList : Model -> List Components.Component -> Html Msg
viewComponentList model components =
    let
        displayTokens = resolveDisplayTokens model
    in
    div [ Ui.panel, classes [ Tw.w s64 ] ]
        [ h3 [ Ui.pageTitle, classes [ Tw.mb s2 ] ] [ text "Components" ]
        , ul [ classes [ Tw.list_none, Tw.p s0 ] ]
            (List.map
                (\c ->
                    let
                        contractState =
                            case model.contracts of
                                Nothing ->
                                    Nothing

                                Just contracts ->
                                    List.filter (\contract -> contract.component == c.name) contracts
                                        |> List.head

                        pillHtml =
                            case contractState of
                                Nothing ->
                                    text ""

                                Just contract ->
                                    let
                                        violations = Contracts.validate displayTokens contract c
                                    in
                                    if List.isEmpty violations then
                                        Ui.pill Positive "OK"
                                    else
                                        Ui.pill Negative (String.fromInt (List.length violations))
                    in
                    li []
                        [ button
                            [ onClick (SelectComponent (Just c.name))
                            , classes
                                [ Tw.flex
                                , Tw.justify_between
                                , Tw.items_center
                                , Tw.w_full
                                , Tw.text_left
                                , Tw.px s2
                                , Tw.py s2
                                , Tw.text_sm
                                , Tw.border_none
                                , Tw.rounded_md
                                , Tw.cursor_pointer
                                , if model.selectedComponentName == Just c.name then
                                    Tw.batch
                                        [ Tw.bg_color (slate s100)
                                        , Tw.font_medium
                                        , Tw.text_color (slate s900)
                                        ]

                                  else
                                    Tw.batch
                                        [ Tw.raw "bg-transparent"
                                        , Tw.text_color (slate s700)
                                        , hover [ Tw.bg_color (slate s50) ]
                                        ]
                                ]
                            ]
                            [ text c.name, pillHtml ]
                        ]
                )
                components
            )
        , div [ classes [ Tw.mt s3, Tw.pt s3, Tw.flex, Tw.flex_col, Tw.gap s2 ], Ui.divider ]
            [ Html.input
                [ Ui.textInput
                , value model.newComponentName
                , onInput UpdateNewComponentName
                , Html.Attributes.placeholder "New component"
                , Html.Attributes.attribute "aria-label" "New component name"
                , classes [ Tw.w_full ]
                ]
                []
            , div [ classes [ Tw.flex, Tw.gap s2 ] ]
                [ Html.select
                    [ Ui.selectInput
                    , Html.Events.onInput UpdateNewComponentTemplate
                    , value model.newComponentTemplate
                    , Html.Attributes.attribute "aria-label" "Start from"
                    , classes [ Tw.flex_1 ]
                    ]
                    [ Html.option [ value "Empty" ] [ text "Empty" ]
                    , Html.option [ value "Button" ] [ text "Button" ]
                    , Html.option [ value "Card" ] [ text "Card" ]
                    ]
                , button [ Ui.btnNeutral, onClick CreateComponent ] [ text "Add" ]
                ]
            ]
        ]


viewSelectedComponent : Model -> List Components.Component -> Html Msg
viewSelectedComponent model components =
    case model.selectedComponentName of
        Nothing ->
            div [ Ui.panel, Ui.muted, classes [ Tw.text_center, Tw.py s6 ] ]
                [ text "Pick a component to edit it." ]

        Just activeName ->
            let
                activeComponent =
                    List.filter (\c -> c.name == activeName) components |> List.head

                displayTokens = resolveDisplayTokens model
            in
            case activeComponent of
                Just comp ->
                    div [ classes [ Tw.flex, Tw.gap s4, Tw.items_start ] ]
                        [ viewComponentEditor model comp displayTokens
                        , viewComponentPreview model comp displayTokens
                        ]

                Nothing ->
                    div [ Ui.panel, Ui.muted ] [ text "That component no longer exists." ]


viewComponentEditor : Model -> Components.Component -> List Tokens.FlatToken -> Html Msg
viewComponentEditor model comp displayTokens =
    div [ Ui.panel, classes [ Tw.flex_1 ] ]
        [ div [ classes [ Tw.flex, Tw.justify_between, Tw.items_center, Tw.gap s2, Tw.mb s3, Tw.flex_wrap ] ]
            [ h3 [ Ui.pageTitle ] [ text comp.name ]
            , div [ classes [ Tw.flex, Tw.gap s2 ] ]
                [ button [ Ui.btnPrimary, onClick SaveComponent ] [ text "Save" ]
                , button [ Ui.btnDanger, onClick (DeleteComponent comp.name) ] [ text "Delete" ]
                ]
            ]
        , viewNameList "Variants" comp.variants model.newComponentVariant UpdateNewComponentVariant AddComponentVariant
        , viewNameList "States" comp.states model.newComponentState UpdateNewComponentState AddComponentState
        , viewNameList "Slots" comp.slots model.newComponentSlot UpdateNewComponentSlot AddComponentSlot
        , div [ classes [ Tw.mt s3, Tw.pt s3 ], Ui.divider ]
            [ h4 [ Ui.sectionTitle, classes [ Tw.mb s2 ] ] [ text "Layout" ]
            , Html.datalist [ Html.Attributes.id "tokensList" ]
                (List.map (\( p, _ ) -> Html.option [ value ("{" ++ String.join "." p ++ "}") ] []) displayTokens)
            , Html.datalist [ Html.Attributes.id "css-properties-list" ]
                (List.map (\prop -> Html.option [ value prop ] []) CssProperties.allProperties)
            , case comp.layout of
                Nothing ->
                    div []
                        [ div [ Ui.muted, classes [ Tw.mb s2 ] ]
                            [ text "This component has nothing in it yet." ]
                        , button [ Ui.btnNeutral, onClick InitComponentLayout ] [ text "Add a layout" ]
                        ]

                Just layoutRoot ->
                    viewLayoutEditorNode model [] layoutRoot
            ]
        , div [ classes [ Tw.mt s3, Tw.pt s3 ], Ui.divider ]
            [ viewUsageContract model comp displayTokens ]
        ]


{-| Variants, states and slots are all "a list of names you can add to".
-}
viewNameList : String -> List String -> String -> (String -> Msg) -> Msg -> Html Msg
viewNameList label names draft onDraftChange onAdd =
    div [ classes [ Tw.mb s3 ] ]
        [ h4 [ Ui.sectionTitle, classes [ Tw.mb s1 ] ] [ text label ]
        , if List.isEmpty names then
            div [ Ui.mutedSmall, classes [ Tw.mb s1 ] ] [ text "None yet." ]

          else
            div [ classes [ Tw.flex, Tw.gap s1, Tw.flex_wrap, Tw.mb s1 ] ]
                (List.map
                    (\n ->
                        Html.span
                            [ classes
                                [ Tw.px s2
                                , Tw.py s0_dot_5
                                , Tw.rounded_full
                                , Tw.text_xs
                                , Tw.bg_color (slate s100)
                                , Tw.text_color (slate s700)
                                ]
                            ]
                            [ text n ]
                    )
                    names
                )
        , div [ classes [ Tw.flex, Tw.gap s2 ] ]
            [ Html.input
                [ Ui.textInput
                , value draft
                , onInput onDraftChange
                , Html.Attributes.placeholder ("Add a " ++ String.toLower (String.dropRight 1 label))
                , Html.Attributes.attribute "aria-label" ("New " ++ String.toLower (String.dropRight 1 label))
                ]
                []
            , button [ Ui.btnSmall, onClick onAdd ] [ text "Add" ]
            ]
        ]


viewComponentPreview : Model -> Components.Component -> List Tokens.FlatToken -> Html Msg
viewComponentPreview model comp displayTokens =
    div [ Ui.panelSunken, classes [ Tw.flex_1 ] ]
        [ div [ classes [ Tw.flex, Tw.justify_between, Tw.items_center, Tw.gap s2, Tw.mb s3 ] ]
            [ h3 [ Ui.sectionTitle ] [ text "Preview" ]
            , Ui.themePicker (List.map .name model.themes) model.activeThemeName SelectTheme
            ]
        , case comp.layout of
            Just l ->
                div [ Ui.previewSurface, classes [ Tw.min_h s24 ] ]
                    [ Renderer.render displayTokens l ]

            Nothing ->
                div [ Ui.muted ] [ text "Nothing to preview yet." ]
        ]


resolveDisplayTokens : Model -> List Tokens.FlatToken
resolveDisplayTokens model =
    let
        baseTokens =
            model.tokens |> Maybe.withDefault []
    in
    case model.activeThemeName of
        Nothing ->
            baseTokens

        Just activeThemeNameStr ->
            let
                activeTheme =
                    List.filter (\t -> t.name == activeThemeNameStr) model.themes |> List.head
            in
            case activeTheme of
                Just theme ->
                    Themes.applyTheme baseTokens theme

                Nothing ->
                    baseTokens


viewUsageContract : Model -> Components.Component -> List Tokens.FlatToken -> Html Msg
viewUsageContract model comp displayTokens =
    let
        activeContract =
            model.contracts
                |> Maybe.withDefault []
                |> List.filter (\c -> c.component == comp.name)
                |> List.head
                |> Maybe.withDefault { component = comp.name, rules = [] }
                
        violations =
            Contracts.validate displayTokens activeContract comp

        headingPill =
            if List.isEmpty activeContract.rules then
                text ""
            else if List.isEmpty violations then
                Ui.pill Positive "OK"
            else
                Ui.pill Negative (String.fromInt (List.length violations))
    in
    div []
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
            [ h4 [ Ui.sectionTitle ] [ text "Usage contract" ]
            , headingPill
            ]
        , div [ Html.Attributes.attribute "aria-live" "polite", classes [ Tw.mb s3 ] ]
            (if not (List.isEmpty violations) then
                List.map
                    (\v ->
                        div [ classes [ Tw.text_color (red s700), Tw.text_sm, Tw.mb s1 ] ]
                            [ Html.strong [] [ text (Maybe.withDefault "General" v.property ++ ": ") ]
                            , text v.message
                            ]
                    )
                    violations
             else if not (List.isEmpty activeContract.rules) then
                [ div [ Ui.mutedSmall ] [ text "No contract violations." ] ]
             else
                [ div [ Ui.mutedSmall ] [ text "No rules yet — add one below to start enforcing usage for this component." ] ]
            )
        , div [ classes [ Tw.mb s3 ] ]
            (List.indexedMap
                (\index rule ->
                    div [ classes [ Tw.flex, Tw.items_center, Tw.justify_between, Tw.mb s1 ] ]
                        [ div [ Ui.mutedSmall ] [ text (ruleToString rule) ]
                        , button [ Ui.btnQuiet, onClick (RemoveContractRule index) ] [ text "Remove" ]
                        ]
                )
                activeContract.rules
            )
        , div [ classes [ Tw.flex, Tw.flex_col, Tw.gap s2, Tw.mb s3 ] ]
            [ Html.select
                [ Ui.selectInput
                , value model.newContractRuleType
                , onInput UpdateNewContractRuleType
                ]
                [ Html.option [ value "allowedTokenGroups" ] [ text "Allowed token groups" ]
                , Html.option [ value "noHardcodedValues" ] [ text "No hardcoded values" ]
                , Html.option [ value "spacingOnScale" ] [ text "Spacing on scale" ]
                , Html.option [ value "contrastThreshold" ] [ text "Contrast threshold" ]
                ]
            , case model.newContractRuleType of
                "allowedTokenGroups" ->
                    div []
                        [ Html.input
                            [ Ui.textInput
                            , value (Dict.get "groups" model.newContractRuleFields |> Maybe.withDefault "")
                            , onInput (UpdateNewContractRuleField "groups")
                            , Html.Attributes.placeholder "interactive, spacing"
                            , classes [ Tw.w_full, Tw.mb s1 ]
                            ] []
                        , div [ Ui.mutedSmall ] [ text "Comma-separated token group paths." ]
                        ]

                "noHardcodedValues" ->
                    div []
                        [ Html.input
                            [ Ui.textInput
                            , value (Dict.get "properties" model.newContractRuleFields |> Maybe.withDefault "")
                            , onInput (UpdateNewContractRuleField "properties")
                            , Html.Attributes.placeholder "color, background-color"
                            , classes [ Tw.w_full, Tw.mb s1 ]
                            ] []
                        , div [ Ui.mutedSmall ] [ text "Comma-separated CSS property names." ]
                        ]

                "spacingOnScale" ->
                    div [ classes [ Tw.flex, Tw.gap s2, Tw.items_start ] ]
                        [ div [ classes [ Tw.flex_1 ] ]
                            [ Html.input
                                [ Ui.textInput
                                , value (Dict.get "properties" model.newContractRuleFields |> Maybe.withDefault "")
                                , onInput (UpdateNewContractRuleField "properties")
                                , Html.Attributes.placeholder "padding, margin, gap"
                                , classes [ Tw.w_full, Tw.mb s1 ]
                                ] []
                            ]
                        , div [ classes [ Tw.flex_1 ] ]
                            [ Html.input
                                [ Ui.textInput
                                , value (Dict.get "scale" model.newContractRuleFields |> Maybe.withDefault "")
                                , onInput (UpdateNewContractRuleField "scale")
                                , Html.Attributes.placeholder "spacing"
                                , classes [ Tw.w_full, Tw.mb s1 ]
                                ] []
                            , div [ Ui.mutedSmall ] [ text "Token group path acting as the allowed scale." ]
                            ]
                        ]

                "contrastThreshold" ->
                    div [ classes [ Tw.flex, Tw.gap s2, Tw.items_start ] ]
                        [ div [ classes [ Tw.flex_1 ] ]
                            [ Html.input
                                [ Ui.textInput
                                , value (Dict.get "foreground" model.newContractRuleFields |> Maybe.withDefault "")
                                , onInput (UpdateNewContractRuleField "foreground")
                                , Html.Attributes.placeholder "color"
                                , classes [ Tw.w_full, Tw.mb s1 ]
                                ] []
                            ]
                        , div [ classes [ Tw.flex_1 ] ]
                            [ Html.input
                                [ Ui.textInput
                                , value (Dict.get "background" model.newContractRuleFields |> Maybe.withDefault "")
                                , onInput (UpdateNewContractRuleField "background")
                                , Html.Attributes.placeholder "background-color"
                                , classes [ Tw.w_full, Tw.mb s1 ]
                                ] []
                            ]
                        , div [ classes [ Tw.flex_1 ] ]
                            [ Html.input
                                [ Ui.textInput
                                , value (Dict.get "minimumRatio" model.newContractRuleFields |> Maybe.withDefault "")
                                , onInput (UpdateNewContractRuleField "minimumRatio")
                                , Html.Attributes.placeholder "4.5"
                                , classes [ Tw.w_full, Tw.mb s1 ]
                                ] []
                            , div [ Ui.mutedSmall ] [ text "A number, e.g. 4.5 for WCAG AA." ]
                            ]
                        ]

                _ ->
                    text ""
            , button [ Ui.btnNeutral, onClick AddContractRule ] [ text "Add rule" ]
            ]
        , div [ classes [ Tw.flex, Tw.gap s2 ] ]
            ([ button [ Ui.btnPrimary, onClick SaveContract ] [ text "Save contract" ] ]
                ++ (if List.member comp.name model.existingContracts then
                        [ button [ Ui.btnDanger, onClick (DeleteContract comp.name) ] [ text "Delete contract" ] ]

                    else
                        []
                   )
            )
        ]


ruleToString : Contracts.Rule -> String
ruleToString rule =
    case rule of
        Contracts.AllowedTokenGroups groups ->
            "Allowed token groups: " ++ String.join ", " (List.map (String.join ".") groups)

        Contracts.NoHardcodedValues props ->
            "No hardcoded values: " ++ String.join ", " props

        Contracts.SpacingOnScale props scale ->
            "Spacing on scale (" ++ String.join "." scale ++ "): " ++ String.join ", " props

        Contracts.ContrastThreshold { foreground, background, minimumRatio } ->
            "Contrast >= " ++ String.fromFloat minimumRatio ++ " between " ++ foreground ++ " and " ++ background
