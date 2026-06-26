module Pages.ExportPipeline exposing (viewExportPipeline)

import Html exposing (Html, button, div, h2, input, p, text)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Types exposing (..)


viewExportPipeline : Model -> Html Msg
viewExportPipeline model =
    div [ style "padding" "2rem", style "background" "#fff", style "border-radius" "8px", style "box-shadow" "0 2px 4px rgba(0,0,0,0.1)" ]
        [ h2 [] [ text "Export Pipeline" ]
        , p [] [ text "Generate target formats from your tokens and commit them to the repository." ]
        , div [ style "margin-top" "1rem", style "margin-bottom" "1rem" ]
            [ div [ style "margin-bottom" "0.5rem" ]
                [ input
                    [ Html.Attributes.type_ "checkbox"
                    , Html.Attributes.checked (List.member "css" model.exportTargets)
                    , onClick (ToggleExportTarget "css")
                    , style "margin-right" "0.5rem"
                    ]
                    []
                , text "CSS Variables"
                ]
            , div [ style "margin-bottom" "0.5rem" ]
                [ input
                    [ Html.Attributes.type_ "checkbox"
                    , Html.Attributes.checked (List.member "tailwind" model.exportTargets)
                    , onClick (ToggleExportTarget "tailwind")
                    , style "margin-right" "0.5rem"
                    ]
                    []
                , text "Tailwind Config"
                ]
            ]
        , button
            [ onClick RunExportPipeline
            , style "padding" "0.5rem 1rem"
            , style "background" "#e91e63"
            , style "color" "white"
            , style "border" "none"
            , style "border-radius" "4px"
            , style "cursor" "pointer"
            , style "font-size" "1em"
            ]
            [ text "Run Export Pipeline" ]
        ]
