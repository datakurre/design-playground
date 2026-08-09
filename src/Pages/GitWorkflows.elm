module Pages.GitWorkflows exposing (viewGitWorkflows)

import Contracts
import Help
import Html exposing (Html, a, button, div, h3, h4, input, li, option, select, span, strong, text, ul)
import Html.Attributes exposing (href, value)
import Html.Events exposing (onClick, onInput)
import Tailwind as Tw exposing (classes)
import Tailwind.Theme exposing (emerald, red, s1, s2, s3, s4, s6, s600, s64, s700, slate)
import Themes
import Tokens
import Types exposing (..)
import Ui


viewGitWorkflows : Model -> Html Msg
viewGitWorkflows model =
    div [ Ui.panel ]
        [ h3 [ Ui.pageTitle, classes [ Tw.mb s3 ] ] [ text "Branches & Reviews" ]
        , case model.selectedProject of
            Just _ ->
                div []
                    [ viewBranch model
                    , viewUnsavedChanges model
                    , viewContractCheck model
                    , viewMergeRequests model
                    ]

            Nothing ->
                div [ Ui.muted ] [ text "Choose a repository first." ]
        ]


viewBranch : Model -> Html Msg
viewBranch model =
    div [ classes [ Tw.mb s6 ] ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
            [ h4 [ Ui.sectionTitle ] [ text "Branch" ]
            , Ui.contextHelp Help.branch
            ]
        , div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s3, Tw.flex_wrap ] ]
            [ span [ Ui.fieldLabel ] [ text "Working on" ]
            , select
                [ Ui.selectInput
                , Html.Attributes.attribute "aria-label" "Current branch"
                , onInput SwitchBranch
                ]
                (List.map
                    (\branch ->
                        option
                            [ value branch.name, Html.Attributes.selected (model.currentBranch == Just branch.name) ]
                            [ text branch.name ]
                    )
                    (model.branches |> Maybe.withDefault [])
                )
            ]
        , Html.datalist [ Html.Attributes.id "branch-prefix-list" ]
            (List.map (\prefix -> Html.option [ value prefix ] []) branchPrefixes)
        , div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.flex_wrap ] ]
            [ input
                [ Ui.textInput
                , Html.Attributes.placeholder "New branch, e.g. feature/new-colors"
                , Html.Attributes.attribute "aria-label" "New branch name"
                , Html.Attributes.attribute "list" "branch-prefix-list"
                , Html.Attributes.spellcheck False
                , value model.newBranchName
                , onInput UpdateNewBranchName
                , classes [ Tw.w s64 ]
                ]
                []
            , button [ Ui.btnNeutral, onClick CreateBranch ] [ text "Create branch" ]
            ]
        ]


{-| Common branch-name prefixes, offered as suggestions for the new-branch
input — not enforced, just a nudge toward the convention the placeholder
already hints at.
-}
branchPrefixes : List String
branchPrefixes =
    [ "feature/", "fix/", "chore/", "docs/", "refactor/", "release/" ]


viewUnsavedChanges : Model -> Html Msg
viewUnsavedChanges model =
    let
        componentsChanged =
            case ( model.originalComponents, model.components ) of
                ( Just origComps, Just currentComps ) ->
                    origComps /= currentComps

                _ ->
                    False

        tokenDiffs =
            case ( model.originalTokens, model.tokens ) of
                ( Just origTokens, Just currentTokens ) ->
                    diffTokens origTokens currentTokens

                _ ->
                    []
    in
    div [ classes [ Tw.mb s6, Tw.pt s4 ], Ui.divider ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
            [ h4 [ Ui.sectionTitle ] [ text "Unsaved changes" ]
            , Ui.contextHelp Help.unsavedChanges
            ]
        , if List.isEmpty tokenDiffs && not componentsChanged then
            div [ Ui.mutedSmall ] [ text "Nothing changed since you last saved." ]

          else
            div [ Ui.panelSunken, classes [ Tw.text_sm ] ]
                [ if List.isEmpty tokenDiffs then
                    text ""

                  else
                    div [] (List.map viewTokenDiff tokenDiffs)
                , if componentsChanged then
                    div [ Ui.muted, classes [ Tw.mt s2 ] ]
                        [ text "Components have unsaved edits. Save them on the Components tab to commit them to this branch." ]

                  else
                    text ""
                ]
        ]


viewMergeRequests : Model -> Html Msg
viewMergeRequests model =
    div [ classes [ Tw.pt s4 ], Ui.divider ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
            [ h4 [ Ui.sectionTitle ] [ text "Merge requests" ]
            , Ui.contextHelp Help.mergeRequests
            ]
        , div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.flex_wrap ] ]
            [ input
                [ Ui.textInput
                , Html.Attributes.placeholder "What did you change?"
                , Html.Attributes.attribute "aria-label" "Merge request title"
                , value model.mrTitle
                , onInput UpdateMRTitle
                , classes [ Tw.w s64 ]
                ]
                []
            , button [ Ui.btnPrimary, onClick CreateMergeRequest ] [ text "Open merge request" ]
            ]
        , case model.mergeRequests of
            Just mrs ->
                ul [ classes [ Tw.list_none, Tw.p Tailwind.Theme.s0, Tw.mt s3 ] ]
                    (List.map
                        (\mr ->
                            li [ classes [ Tw.py s1, Tw.text_sm ] ]
                                [ a
                                    [ href mr.webUrl
                                    , Html.Attributes.target "_blank"
                                    , Html.Attributes.rel "noopener noreferrer"
                                    , classes [ Tw.text_color (slate s700), Tw.underline ]
                                    ]
                                    [ text mr.title ]
                                , span [ Ui.mutedSmall, classes [ Tw.ml s2 ] ] [ text mr.state ]
                                ]
                        )
                        mrs
                    )

            Nothing ->
                text ""
        ]


{-| One changed token, old value struck through beside the new one.
-}
viewTokenDiff : ( List String, String, String ) -> Html Msg
viewTokenDiff ( path, oldVal, newVal ) =
    div [ classes [ Tw.mb s1, Tw.font_mono, Tw.text_xs ] ]
        [ strong [ classes [ Tw.text_color (slate s700) ] ] [ text (String.join "." path ++ " ") ]
        , span [ classes [ Tw.text_color (red s600), Tw.line_through ] ] [ text oldVal ]
        , span [ Ui.mutedSmall ] [ text " → " ]
        , span [ classes [ Tw.text_color (emerald s700) ] ] [ text newVal ]
        ]


diffTokens : List Tokens.FlatToken -> List Tokens.FlatToken -> List ( List String, String, String )
diffTokens orig current =
    let
        getVal path tokens =
            List.filter (\( p, _ ) -> p == path) tokens |> List.head |> Maybe.map (Tuple.second >> .value)

        tokenValueToString tv =
            case tv of
                Tokens.StringValue s ->
                    s

                Tokens.CompositeValue _ ->
                    "(several values)"
    in
    List.filterMap
        (\( path, tok ) ->
            case getVal path orig of
                Just origVal ->
                    if origVal /= tok.value then
                        Just ( path, tokenValueToString origVal, tokenValueToString tok.value )

                    else
                        Nothing

                Nothing ->
                    Just ( path, "(new)", tokenValueToString tok.value )
        )
        current


viewContractCheck : Model -> Html Msg
viewContractCheck model =
    let
        -- Resolved through the active theme, the same way the Component
        -- Registry resolves them, so the gate and the editor can't report
        -- different violation counts for the same component.
        tokens =
            Themes.resolve (Maybe.withDefault [] model.tokens) model.themes model.activeThemeName

        components =
            model.components |> Maybe.withDefault []

        contracts =
            model.contracts |> Maybe.withDefault []

        allViolations : List ( String, Contracts.Violation )
        allViolations =
            List.concatMap
                (\comp ->
                    let
                        compContracts =
                            List.filter (\c -> c.component == comp.name) contracts
                    in
                    List.concatMap
                        (\contract ->
                            Contracts.validate tokens contract comp
                                |> List.map (\v -> ( comp.name, v ))
                        )
                        compContracts
                )
                components
    in
    div [ classes [ Tw.mb s6, Tw.pt s4 ], Ui.divider ]
        [ div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mb s2 ] ]
            [ h4 [ Ui.sectionTitle ] [ text "Contract check" ]
            , Ui.contextHelp Help.contractCheck
            , if not (List.isEmpty allViolations) then
                Ui.pill Ui.Negative (String.fromInt (List.length allViolations))

              else
                text ""
            ]
        , if List.isEmpty contracts then
            div []
                [ Ui.pill Ui.Neutral "No contracts"
                , div [ Ui.mutedSmall, classes [ Tw.mt s2 ] ] [ text "This project has no usage contracts yet." ]
                ]

          else if List.isEmpty allViolations then
            div []
                [ Ui.pill Ui.Positive "Passing"
                , div [ Ui.mutedSmall, classes [ Tw.mt s2 ] ] [ text "All components satisfy their usage contracts." ]
                ]

          else
            div
                [ Ui.panelSunken
                , classes [ Tw.text_sm, Tw.flex, Tw.flex_col, Tw.gap s1 ]
                , Html.Attributes.attribute "aria-live" "polite"
                ]
                (List.map
                    (\( compName, violation ) ->
                        button
                            [ Ui.btnQuiet
                            , onClick (JumpToComponent compName)
                            , classes [ Tw.text_left, Tw.w_full, Tw.block ]
                            ]
                            [ text (compName ++ ": " ++ violation.message) ]
                    )
                    allViolations
                )
        ]
