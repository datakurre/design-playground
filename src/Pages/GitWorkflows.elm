module Pages.GitWorkflows exposing (viewGitWorkflows)

import Html exposing (Html, a, button, div, h2, h3, input, li, option, select, span, strong, text, ul)
import Html.Attributes exposing (href, style, value)
import Html.Events exposing (onClick, onInput)
import Tokens
import Types exposing (..)

viewGitWorkflows : Model -> Html Msg
viewGitWorkflows model =
    div [ style "padding" "2rem", style "background" "#fff", style "border-radius" "8px", style "box-shadow" "0 2px 4px rgba(0,0,0,0.1)" ]
        [ h2 [] [ text "Git Workflows" ]
        , case model.selectedProject of
            Just project ->
                div []
                    [ h3 [] [ text "Branch Management" ]
                    , div [ style "margin-bottom" "1rem" ]
                        [ text "Current Branch: "
                        , select [ onInput SwitchBranch, style "padding" "0.5rem", style "margin-left" "1rem" ]
                            (List.map
                                (\branch ->
                                    option
                                        [ value branch.name, Html.Attributes.selected (model.currentBranch == Just branch.name) ]
                                        [ text branch.name ]
                                )
                                (model.branches |> Maybe.withDefault [])
                            )
                        ]
                    , div [ style "margin-bottom" "2rem" ]
                        [ input
                            [ Html.Attributes.placeholder "New branch name (e.g. feature/new-colors)"
                            , value model.newBranchName
                            , onInput UpdateNewBranchName
                            , style "padding" "0.5rem"
                            ]
                            []
                        , button
                            [ onClick CreateBranch
                            , style "padding" "0.5rem 1rem"
                            , style "margin-left" "1rem"
                            , style "background" "#4caf50"
                            , style "color" "white"
                            , style "border" "none"
                            , style "border-radius" "4px"
                            , style "cursor" "pointer"
                            ]
                            [ text "Create Branch" ]
                        ]
                    , h3 [] [ text "Visual Diffs (Local Unsaved Changes)" ]
                    , div [ style "margin-bottom" "2rem", style "padding" "1rem", style "background" "#f9f9f9", style "border" "1px solid #eee" ]
                        [ case (model.originalTokens, model.tokens) of
                            (Just origTokens, Just currentTokens) ->
                                viewTokenDiffs origTokens currentTokens
                            _ -> text ""
                        , case (model.originalComponents, model.components) of
                            (Just origComps, Just currentComps) ->
                                if origComps /= currentComps then
                                    div [ style "margin-top" "0.5rem" ] [ text "Components have been modified locally. Please Save in Component Registry to commit to the current branch." ]
                                else
                                    text ""
                            _ -> text ""
                        ]
                    , h3 [] [ text "Merge Requests" ]
                    , div [ style "margin-bottom" "2rem" ]
                        [ input
                            [ Html.Attributes.placeholder "Merge Request Title"
                            , value model.mrTitle
                            , onInput UpdateMRTitle
                            , style "padding" "0.5rem"
                            , style "width" "300px"
                            ]
                            []
                        , button
                            [ onClick CreateMergeRequest
                            , style "padding" "0.5rem 1rem"
                            , style "margin-left" "1rem"
                            , style "background" "#2196f3"
                            , style "color" "white"
                            , style "border" "none"
                            , style "border-radius" "4px"
                            , style "cursor" "pointer"
                            ]
                            [ text "Open Merge Request" ]
                        , case model.mergeRequests of
                            Just mrs ->
                                ul [ style "margin-top" "1rem" ]
                                    (List.map (\mr -> li [] [ a [ href mr.webUrl, Html.Attributes.target "_blank" ] [ text (mr.title ++ " (" ++ mr.state ++ ")") ] ]) mrs)
                            Nothing ->
                                text ""
                        ]
                    ]
            Nothing ->
                text "Select a project first."
        ]

viewTokenDiffs : List Tokens.FlatToken -> List Tokens.FlatToken -> Html Msg
viewTokenDiffs orig current =
    let
        getVal path tokens =
            List.filter (\(p, _) -> p == path) tokens |> List.head |> Maybe.map (Tuple.second >> .value)
        
        tokenValueToString tv =
            case tv of
                Tokens.StringValue s -> s
                Tokens.CompositeValue _ -> "{Composite}"

        diffs =
            List.filterMap (\(path, tok) ->
                let
                    origValOpt = getVal path orig
                in
                case origValOpt of
                    Just origVal ->
                        if origVal /= tok.value then
                            Just (path, tokenValueToString origVal, tokenValueToString tok.value)
                        else
                            Nothing
                    Nothing ->
                        Just (path, "(new)", tokenValueToString tok.value)
            ) current
    in
    if List.isEmpty diffs then
        text ""
    else
        div []
            (List.map (\(path, oldVal, newVal) ->
                div [ style "margin-bottom" "0.5rem" ]
                    [ strong [] [ text (String.join "." path ++ ": ") ]
                    , span [ style "color" "red", style "text-decoration" "line-through" ] [ text oldVal ]
                    , text " -> "
                    , span [ style "color" "green" ] [ text newVal ]
                    ]
            ) diffs)
