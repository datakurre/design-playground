module Pages.ComponentRegistry exposing (viewComponentRegistry)

import Components
import Contracts
import CssProperties
import Dict
import Help
import Html exposing (Html, button, div, h3, h4, li, text, ul)
import Html.Attributes exposing (value)
import Html.Events exposing (onCheck, onClick, onInput)
import Renderer
import Route
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (hover)
import Tailwind.Theme exposing (red, s0, s0_dot_5, s1, s100, s2, s200, s24, s3, s300, s4, s40, s400, s50, s6, s600, s64, s700, s800, s900, slate)
import Templates
import Themes
import TokenBrowse
import Tokens
import Types exposing (..)
import Ui exposing (PillTone(..))


{-| One node in the layout tree. Layouts nest, so this recurses.
-}
viewLayoutEditorNode : Model -> Components.Component -> List Int -> Components.Layout -> Html Msg
viewLayoutEditorNode model comp path layout =
    let
        ( nodeType, childrenNodes ) =
            case layout of
                Components.Stack _ children ->
                    ( "Stack", children )

                Components.Grid _ children ->
                    ( "Grid", children )

                Components.Element _ _ ->
                    ( "Text", [] )

                Components.When _ children ->
                    ( "When", children )
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
        , case Components.styling layout of
            Just node ->
                let
                    context =
                        editingContext model

                    -- What this node looks like in the context being edited,
                    -- and which of those properties this context is itself
                    -- responsible for. A property that arrives from the base or
                    -- from a less specific layer is shown but can't be reset
                    -- from here — you'd switch to the context that set it.
                    resolved =
                        Components.resolveStyles context node

                    ownStyles =
                        if context == Components.baseContext then
                            node.base

                        else
                            node.overrides
                                |> List.filter (\layer -> layer.variant == context.variant && layer.state == context.state)
                                |> List.head
                                |> Maybe.map .styles
                                |> Maybe.withDefault Dict.empty
                in
                div [ classes [ Tw.p s2 ] ]
                    [ div [ Ui.fieldLabel, classes [ Tw.mb s1 ] ] [ text "Styles" ]
                    , ul [ classes [ Tw.list_none, Tw.p s0, Tw.mb s1 ] ]
                        (List.map
                            (\( key, val ) ->
                                let
                                    isOwn =
                                        Dict.member key ownStyles
                                in
                                li [ classes [ Tw.flex, Tw.gap s2, Tw.items_center, Tw.mb s1 ] ]
                                    [ div [ Ui.mutedSmall, classes [ Tw.w s24, Tw.truncate ] ] [ text key ]
                                    , Html.input
                                        [ Ui.textInput
                                        , value val
                                        , onInput (UpdateLayoutProperty path key)
                                        , Html.Attributes.attribute "aria-label" key
                                        , Html.Attributes.attribute "list" "tokensList"
                                        , Html.Attributes.spellcheck False
                                        , classes [ Tw.flex_1 ]
                                        ]
                                        []
                                    , if context == Components.baseContext then
                                        text ""

                                      else if isOwn then
                                        Ui.pill Positive "overridden"

                                      else
                                        Ui.pill Neutral "inherited"
                                    , if isOwn then
                                        let
                                            label =
                                                if context == Components.baseContext then
                                                    "Remove " ++ key

                                                else
                                                    "Reset " ++ key ++ " to inherited"
                                        in
                                        button
                                            [ Ui.iconButton
                                            , onClick (RemoveLayoutProperty path key)
                                            , Html.Attributes.attribute "aria-label" label
                                            , Html.Attributes.title label
                                            ]
                                            [ text "×" ]

                                      else
                                        text ""
                                    ]
                            )
                            (Dict.toList resolved)
                        )
                    , div [ classes [ Tw.flex, Tw.gap s2, Tw.items_center ] ]
                        [ Html.input
                            [ Ui.textInput
                            , value model.newLayoutPropertyName
                            , onInput UpdateNewLayoutPropertyName
                            , Html.Attributes.placeholder "CSS property"
                            , Html.Attributes.attribute "aria-label" "CSS property"
                            , Html.Attributes.attribute "list" "css-properties-list"
                            , Html.Attributes.spellcheck False
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
                            , Html.Attributes.spellcheck False
                            , classes [ Tw.flex_1 ]
                            ]
                            []
                        , button [ Ui.btnSmall, onClick (UpdateLayoutProperty path model.newLayoutPropertyName model.newLayoutPropertyValue) ]
                            [ text "Add style" ]
                        ]
                    ]

            Nothing ->
                text ""
        , case layout of
            Components.Element props content ->
                div [ classes [ Tw.px s2, Tw.pb s2 ] ]
                    [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
                        [ Html.input
                            [ Html.Attributes.type_ "checkbox"
                            , Html.Attributes.checked props.isSlot
                            , onCheck (ToggleLayoutNodeIsSlot path)
                            ]
                            []
                        , text "Is Slot Placeholder"
                        ]
                    , if props.isSlot then
                        if List.isEmpty comp.slots then
                            div [ Ui.mutedSmall, classes [ Tw.text_color (red s600) ] ]
                                [ text "No slots defined. Add slots in the header above first." ]

                        else
                            Html.select
                                [ onInput (UpdateLayoutText path)
                                , classes [ Tw.w_full, Tw.p s1, Tw.border, Tw.border_color (slate s300), Tw.rounded_sm ]
                                ]
                                (Html.option [ value "" ] [ text "-- Select a slot --" ]
                                    :: List.map (\s -> Html.option [ value s, Html.Attributes.selected (s == content) ] [ text s ]) comp.slots
                                )

                      else
                        Html.input
                            [ Ui.textInput
                            , value content
                            , onInput (UpdateLayoutText path)
                            , Html.Attributes.placeholder "Text content"
                            , classes [ Tw.w_full ]
                            ]
                            []
                    , div [ Ui.mutedSmall, classes [ Tw.mt s2 ] ]
                        [ text "Elements render text or slots and cannot contain other layout nodes (like Stack or Grid)." ]
                    ]

            Components.When props _ ->
                div [ classes [ Tw.px s2, Tw.pb s2 ] ]
                    [ div [ Ui.fieldLabel, classes [ Tw.mb s1 ] ] [ text "Condition" ]
                    , div [ classes [ Tw.flex, Tw.gap s2, Tw.mb s2 ] ]
                        [ Html.select
                            [ onInput (UpdateLayoutWhenCondition path "variant")
                            , classes [ Tw.w_full, Tw.p s1, Tw.border, Tw.border_color (slate s300), Tw.rounded_sm ]
                            ]
                            (Html.option [ value "" ] [ text "Any Variant" ]
                                :: List.map (\s -> Html.option [ value s, Html.Attributes.selected (props.variant == Just s) ] [ text ("Variant: " ++ s) ]) comp.variants
                            )
                        , Html.select
                            [ onInput (UpdateLayoutWhenCondition path "state")
                            , classes [ Tw.w_full, Tw.p s1, Tw.border, Tw.border_color (slate s300), Tw.rounded_sm ]
                            ]
                            (Html.option [ value "" ] [ text "Any State" ]
                                :: List.map (\s -> Html.option [ value s, Html.Attributes.selected (props.state == Just s) ] [ text ("State: " ++ s) ]) comp.states
                            )
                        ]
                    , div [ Ui.fieldLabel, classes [ Tw.mb s1 ] ] [ text "Inside" ]
                    , div [ classes [ Tw.pl s2, Tw.border_l_2, Tw.border_color (slate s100) ] ]
                        (List.indexedMap (\i child -> viewLayoutEditorNode model comp (path ++ [ i ]) child) childrenNodes)
                    , div [ classes [ Tw.flex, Tw.gap s2, Tw.mt s1 ] ]
                        [ button [ Ui.btnSmall, onClick (AddLayoutStack path) ] [ text "+ Stack" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutGrid path) ] [ text "+ Grid" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutWhen path) ] [ text "+ When" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutText path "New Text") ] [ text "+ Text" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutSlot path) ] [ text "+ Slot" ]
                        ]
                    ]

            _ ->
                div [ classes [ Tw.px s2, Tw.pb s2 ] ]
                    [ div [ Ui.fieldLabel, classes [ Tw.mb s1 ] ] [ text "Inside" ]
                    , div [ classes [ Tw.pl s2, Tw.border_l_2, Tw.border_color (slate s100) ] ]
                        (List.indexedMap (\i child -> viewLayoutEditorNode model comp (path ++ [ i ]) child) childrenNodes)
                    , div [ classes [ Tw.flex, Tw.gap s2, Tw.mt s1 ] ]
                        [ button [ Ui.btnSmall, onClick (AddLayoutStack path) ] [ text "+ Stack" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutGrid path) ] [ text "+ Grid" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutWhen path) ] [ text "+ When" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutText path "New Text") ] [ text "+ Text" ]
                        , button [ Ui.btnSmall, onClick (AddLayoutSlot path) ] [ text "+ Slot" ]
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
        displayTokens =
            resolveDisplayTokens model
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
                                        violations =
                                            Contracts.validate displayTokens contract c
                                    in
                                    -- Same three-way test as the editor's heading pill
                                    -- (viewUsageContract), so the two never disagree.
                                    if List.isEmpty contract.rules then
                                        text ""

                                    else if List.isEmpty violations then
                                        Ui.pill Positive "OK"

                                    else
                                        Ui.pill Negative (String.fromInt (List.length violations))
                    in
                    li []
                        [ Html.a
                            [ Html.Attributes.href
                                (case model.selectedProject of
                                    Just p ->
                                        Route.toString (Route.Repo p.pathWithNamespace (Route.ComponentsTab (Just c.name)))

                                    Nothing ->
                                        "#"
                                )
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
                                , Tw.no_underline
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
                    (List.map (\t -> Html.option [ value t.id ] [ text t.label ]) Templates.componentTemplates)
                , button [ Ui.btnNeutral, onClick CreateComponent ] [ text "Add" ]
                ]
            ]
        ]


viewSelectedComponent : Model -> List Components.Component -> Html Msg
viewSelectedComponent model components =
    case model.selectedComponentName of
        Nothing ->
            div [ Ui.panel, Ui.muted, classes [ Tw.text_center, Tw.py s6 ] ]
                [ text
                    -- "Pick a component to edit it" is a dead end when there
                    -- are none to pick, which is exactly where a new user
                    -- starts.
                    (if List.isEmpty components then
                        "No components yet. Name one on the left and pick a starting shape — Button, Card, Input, Badge or Alert."

                     else
                        "Pick a component to edit it."
                    )
                ]

        Just activeName ->
            let
                activeComponent =
                    List.filter (\c -> c.name == activeName) components |> List.head

                displayTokens =
                    resolveDisplayTokens model
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
            [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2 ] ]
                [ h3 [ Ui.pageTitle ] [ text comp.name ]
                , Ui.contextHelp Help.componentEditor
                ]
            , div [ classes [ Tw.flex, Tw.gap s2 ] ]
                [ button [ Ui.btnPrimary, onClick SaveComponent ] [ text "Save" ]
                , button [ Ui.btnDanger, onClick (DeleteComponent comp.name) ] [ text "Delete" ]
                ]
            ]
        , viewEditingContext model comp
        , viewNameList
            { label = "Variants"
            , helpTopic = Help.componentVariant
            , suggestions = commonVariantNames
            , names = comp.variants
            , draft = model.newComponentVariant
            , onDraftChange = UpdateNewComponentVariant
            , onAdd = AddComponentVariant
            , onRemove = RemoveComponentVariant
            }
        , viewNameList
            { label = "States"
            , helpTopic = Help.componentState
            , suggestions = commonStateNames
            , names = comp.states
            , draft = model.newComponentState
            , onDraftChange = UpdateNewComponentState
            , onAdd = AddComponentState
            , onRemove = RemoveComponentState
            }
        , viewNameList
            { label = "Slots"
            , helpTopic = Help.componentSlot
            , suggestions = commonSlotNames
            , names = comp.slots
            , draft = model.newComponentSlot
            , onDraftChange = UpdateNewComponentSlot
            , onAdd = AddComponentSlot
            , onRemove = RemoveComponentSlot
            }
        , div [ classes [ Tw.mt s3, Tw.pt s3 ], Ui.divider ]
            [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
                [ h4 [ Ui.sectionTitle ] [ text "Layout" ]
                , Ui.contextHelp Help.componentLayout
                ]
            , Html.datalist [ Html.Attributes.id "tokensList" ]
                (List.map (\( p, _ ) -> Html.option [ value ("{" ++ String.join "." p ++ "}") ] []) displayTokens)
            , Html.datalist [ Html.Attributes.id "css-properties-list" ]
                (List.map (\prop -> Html.option [ value prop ] []) CssProperties.allProperties)
            , Html.datalist [ Html.Attributes.id "token-groups-list" ]
                (List.map (\p -> Html.option [ value p ] []) (TokenBrowse.groupPaths displayTokens))
            , case comp.layout of
                Nothing ->
                    div []
                        [ div [ Ui.muted, classes [ Tw.mb s2 ] ]
                            [ text "This component has nothing in it yet. Choose a root layout node:" ]
                        , div [ classes [ Tw.flex, Tw.gap s2 ] ]
                            [ button [ Ui.btnNeutral, onClick (InitComponentLayout (Components.Stack { direction = "column", styles = Dict.empty, overrides = [] } [])) ] [ text "+ Stack" ]
                            , button [ Ui.btnNeutral, onClick (InitComponentLayout (Components.Grid { columns = 1, styles = Dict.empty, overrides = [] } [])) ] [ text "+ Grid" ]
                            , button [ Ui.btnNeutral, onClick (InitComponentLayout (Components.Element { isSlot = False, styles = Dict.empty, overrides = [] } "New Element")) ] [ text "+ Element" ]
                            ]
                        ]

                Just layoutRoot ->
                    viewLayoutEditorNode model comp [] layoutRoot
            ]
        , div [ classes [ Tw.mt s3, Tw.pt s3 ], Ui.divider ]
            [ viewUsageContract model comp displayTokens ]
        ]


{-| Which variant and state the component is being worked on in.

This used to sit in the preview header and only change what was drawn, which
made variants decorative: you could look at `primary` but every style you typed
went into the one shared set. It decides both now, so a style edited while
`primary` is selected belongs to `primary`.

Hidden entirely for a component that declares neither — there is no context to
choose.

-}
viewEditingContext : Model -> Components.Component -> Html Msg
viewEditingContext model comp =
    let
        context =
            editingContext model
    in
    if List.isEmpty comp.variants && List.isEmpty comp.states then
        text ""

    else
        div [ classes [ Tw.mb s3, Tw.p s2, Tw.rounded_md, Tw.bg_color (slate s50) ] ]
            [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2, Tw.flex_wrap ] ]
                [ h4 [ Ui.sectionTitle ] [ text "Editing" ]
                , Ui.contextHelp Help.componentContext
                , contextSelect "Editing variant" "Base variant" comp.variants model.editingVariant UpdateEditingVariant
                , contextSelect "Editing state" "Base state" comp.states model.editingState UpdateEditingState
                , if context == Components.baseContext then
                    text ""

                  else
                    button
                        [ Ui.btnQuiet
                        , onClick ClearEditingContext
                        ]
                        [ text "Back to base" ]
                ]
            , div [ Ui.mutedSmall ]
                [ text
                    (case describeContext context of
                        Nothing ->
                            "Styles you change apply everywhere, unless a variant or state overrides them."

                        Just described ->
                            "Styles you change apply only to " ++ described ++ ". Everything else is inherited."
                    )
                ]
            ]


{-| One half of the editing context. Empty means "not this one", which is what
the base styling is.
-}
contextSelect : String -> String -> List String -> Maybe String -> (Maybe String -> Msg) -> Html Msg
contextSelect label baseLabel names selected toMsg =
    if List.isEmpty names then
        text ""

    else
        Html.select
            [ Ui.selectInput
            , Html.Attributes.attribute "aria-label" label
            , onInput
                (\v ->
                    toMsg
                        (if v == "" then
                            Nothing

                         else
                            Just v
                        )
                )
            ]
            (Html.option [ value "", Html.Attributes.selected (selected == Nothing) ] [ text baseLabel ]
                :: List.map
                    (\n -> Html.option [ value n, Html.Attributes.selected (selected == Just n) ] [ text n ])
                    names
            )


{-| The context in words, for the editor's explanation and the preview's
caption. `Nothing` is the base, which has no name of its own.
-}
describeContext : Components.StyleContext -> Maybe String
describeContext context =
    case ( context.variant, context.state ) of
        ( Nothing, Nothing ) ->
            Nothing

        ( Just variant, Nothing ) ->
            Just variant

        ( Nothing, Just state ) ->
            Just ("the " ++ state ++ " state")

        ( Just variant, Just state ) ->
            Just (variant ++ " in the " ++ state ++ " state")


{-| Common variant names across design systems — offered as datalist
suggestions, not a closed set; anything can still be typed freehand.
-}
commonVariantNames : List String
commonVariantNames =
    [ "primary", "secondary", "tertiary", "ghost", "danger", "small", "medium", "large" ]


{-| Common interaction/state names — same idea as `commonVariantNames`.
-}
commonStateNames : List String
commonStateNames =
    [ "default", "hover", "focus", "active", "disabled", "loading", "selected", "error" ]


{-| Common slot names for placing custom content.
-}
commonSlotNames : List String
commonSlotNames =
    [ "content", "header", "body", "footer", "icon-left", "icon-right", "media", "actions" ]


{-| Variants, states and slots are all "a list of names you can add to".
`suggestions` seeds a `<datalist>` for the draft input, minus whatever has
already been added — a suggestion you can't use isn't one.

A record rather than eight positional arguments, three of which are `Msg`s of
much the same shape: `Update.addNameToComponent` describes the other half of
these three forms the same way.

-}
viewNameList :
    { label : String
    , helpTopic : Help.Topic
    , suggestions : List String
    , names : List String
    , draft : String
    , onDraftChange : String -> Msg
    , onAdd : Msg
    , onRemove : String -> Msg
    }
    -> Html Msg
viewNameList { label, helpTopic, suggestions, names, draft, onDraftChange, onAdd, onRemove } =
    let
        datalistId =
            "suggestions-" ++ label

        availableSuggestions =
            List.filter (\s -> not (List.member s names)) suggestions
    in
    div [ classes [ Tw.mb s3 ] ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s1 ] ]
            [ h4 [ Ui.sectionTitle ] [ text label ]
            , Ui.contextHelp helpTopic
            ]
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
                                , Tw.flex
                                , Tw.items_center
                                , Tw.gap s1
                                ]
                            ]
                            [ text n
                            , button
                                [ onClick (onRemove n)
                                , Html.Attributes.attribute "aria-label" ("Remove " ++ n)
                                , Html.Attributes.title ("Remove " ++ n)
                                , classes [ Tw.border_none, Tw.raw "bg-transparent", Tw.cursor_pointer, Tw.text_color (slate s400), hover [ Tw.text_color (slate s800) ] ]
                                ]
                                [ text "×" ]
                            ]
                    )
                    names
                )
        , if List.isEmpty availableSuggestions then
            text ""

          else
            Html.datalist [ Html.Attributes.id datalistId ]
                (List.map (\n -> Html.option [ value n ] []) availableSuggestions)
        , div [ classes [ Tw.flex, Tw.gap s2 ] ]
            [ Html.input
                ([ Ui.textInput
                 , value draft
                 , onInput onDraftChange
                 , Html.Attributes.placeholder ("Add a " ++ String.toLower (String.dropRight 1 label))
                 , Html.Attributes.attribute "aria-label" ("New " ++ String.toLower (String.dropRight 1 label))
                 ]
                    ++ (if List.isEmpty availableSuggestions then
                            []

                        else
                            [ Html.Attributes.attribute "list" datalistId ]
                       )
                )
                []
            , button [ Ui.btnSmall, onClick onAdd ] [ text "Add" ]
            ]
        ]


viewComponentPreview : Model -> Components.Component -> List Tokens.FlatToken -> Html Msg
viewComponentPreview model comp displayTokens =
    div [ Ui.panelSunken, classes [ Tw.flex_1 ] ]
        [ div [ classes [ Tw.flex, Tw.justify_between, Tw.items_center, Tw.gap s2, Tw.mb s3 ] ]
            [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.flex_wrap ] ]
                [ h3 [ Ui.sectionTitle ] [ text "Preview" ]

                -- Read-only on purpose: the context is chosen once, in the
                -- editor, so what you are looking at and what you are changing
                -- can't drift apart.
                , case describeContext (editingContext model) of
                    Nothing ->
                        text ""

                    Just described ->
                        Ui.pill Neutral ("Showing " ++ described)
                ]
            , Ui.themePicker (List.map .name model.themes) model.activeThemeName SelectTheme
            ]
        , case comp.layout of
            Just l ->
                div [ Ui.previewSurface, classes [ Tw.min_h s24 ] ]
                    [ Renderer.renderWithConditions displayTokens model.editingVariant model.editingState l ]

            Nothing ->
                div [ Ui.muted ] [ text "Nothing to preview yet." ]
        ]


resolveDisplayTokens : Model -> List Tokens.FlatToken
resolveDisplayTokens model =
    Themes.resolve (Maybe.withDefault [] model.tokens) model.themes model.activeThemeName


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
            , Ui.contextHelp Help.usageContract
            , headingPill
            ]
        , div [ Html.Attributes.attribute "aria-live" "polite", classes [ Tw.mb s3 ] ]
            (if not (List.isEmpty violations) then
                List.map
                    (\v ->
                        div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.text_color (red s700), Tw.text_sm, Tw.mb s1 ] ]
                            [ -- Which variant or state introduced it. Without
                              -- this, a rule broken only by one layer reads as
                              -- if the component broke it everywhere.
                              case Maybe.andThen describeContext v.context of
                                Nothing ->
                                    text ""

                                Just described ->
                                    Ui.pill Neutral described
                            , Html.span []
                                [ Html.strong [] [ text (Maybe.withDefault "General" v.property ++ ": ") ]
                                , text v.message
                                ]
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
                , Html.Attributes.attribute "aria-label" "Rule type"
                ]
                [ Html.option [ value "allowedTokenGroups" ] [ text "Allowed token groups" ]
                , Html.option [ value "noHardcodedValues" ] [ text "No hardcoded values" ]
                , Html.option [ value "spacingOnScale" ] [ text "Spacing on scale" ]
                , Html.option [ value "contrastThreshold" ] [ text "Contrast threshold" ]
                ]
            , case model.newContractRuleType of
                "allowedTokenGroups" ->
                    div []
                        [ viewRuleField model "groups" "Allowed token groups" "interactive, spacing" "Comma-separated token group paths." [ Html.Attributes.attribute "list" "token-groups-list" ] ]

                "noHardcodedValues" ->
                    div []
                        [ viewRuleField model "properties" "Properties" "color, background-color" "Comma-separated CSS property names." [ Html.Attributes.attribute "list" "css-properties-list" ] ]

                "spacingOnScale" ->
                    div [ classes [ Tw.flex, Tw.gap s2, Tw.items_start ] ]
                        [ div [ classes [ Tw.flex_1 ] ]
                            [ viewRuleField model "properties" "Properties" "padding, margin, gap" "Comma-separated CSS property names." [ Html.Attributes.attribute "list" "css-properties-list" ] ]
                        , div [ classes [ Tw.flex_1 ] ]
                            [ viewRuleField model "scale" "Scale" "spacing" "Token group path acting as the allowed scale." [ Html.Attributes.attribute "list" "token-groups-list" ] ]
                        ]

                "contrastThreshold" ->
                    div [ classes [ Tw.flex, Tw.gap s2, Tw.items_start ] ]
                        [ div [ classes [ Tw.flex_1 ] ]
                            [ viewRuleField model "foreground" "Foreground property" "color" "CSS property holding the text color." [ Html.Attributes.attribute "list" "css-properties-list" ] ]
                        , div [ classes [ Tw.flex_1 ] ]
                            [ viewRuleField model "background" "Background property" "background-color" "CSS property holding the background color." [ Html.Attributes.attribute "list" "css-properties-list" ] ]
                        , div [ classes [ Tw.flex_1 ] ]
                            [ viewRuleField model "minimumRatio" "Minimum ratio" "4.5" "A number, e.g. 4.5 for WCAG AA." [ Html.Attributes.type_ "number", Html.Attributes.step "0.1", Html.Attributes.min "1", Html.Attributes.max "21" ] ]
                        ]

                _ ->
                    text ""
            , button [ Ui.btnNeutral, onClick AddContractRule ] [ text "Add rule" ]
            ]
        , div [ classes [ Tw.flex, Tw.gap s2 ] ]
            ((if List.member comp.name model.existingComponents then
                [ button [ Ui.btnPrimary, onClick SaveContract ] [ text "Save contract" ] ]

              else
                [ button [ Ui.btnPrimary, Html.Attributes.disabled True, Html.Attributes.title "Save the component first before saving contracts" ] [ text "Save contract" ] ]
             )
                ++ (if List.member comp.name model.existingContracts then
                        [ button [ Ui.btnDanger, onClick (DeleteContract comp.name) ] [ text "Delete contract" ] ]

                    else
                        []
                   )
            )
        ]


{-| One field of the add-rule form: a text input bound to
`model.newContractRuleFields` under `key`, with a hint line underneath. The hint
is a visible line rather than only a placeholder, which disappears as soon as
the user starts typing and offers no help if they get the format wrong.

`extraAttrs` lets call sites opt into a `list="..."` datalist or a different
`type_`/`step`/`min`/`max` (e.g. the numeric "minimum ratio" field) without
branching inside this shared helper.

-}
viewRuleField : Model -> String -> String -> String -> String -> List (Html.Attribute Msg) -> Html Msg
viewRuleField model key label placeholder hint extraAttrs =
    div []
        [ Html.input
            ([ Ui.textInput
             , value (Dict.get key model.newContractRuleFields |> Maybe.withDefault "")
             , onInput (UpdateNewContractRuleField key)
             , Html.Attributes.placeholder placeholder
             , Html.Attributes.attribute "aria-label" label
             , Html.Attributes.spellcheck False
             , classes [ Tw.w_full, Tw.mb s1 ]
             ]
                ++ extraAttrs
            )
            []
        , div [ Ui.mutedSmall ] [ text hint ]
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
