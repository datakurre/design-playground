module Pages.ExportPipeline exposing (viewExportPipeline)

import Html exposing (Html, button, div, h3, input, label, p, text)
import Html.Attributes exposing (checked, type_)
import Html.Events exposing (onClick)
import Tailwind as Tw exposing (classes)
import Tailwind.Theme exposing (s1, s2, s3, s4)
import Types exposing (..)
import Ui


viewExportPipeline : Model -> Html Msg
viewExportPipeline model =
    div [ Ui.panel ]
        [ h3 [ Ui.pageTitle, classes [ Tw.mb s1 ] ] [ text "Export" ]
        , p [ Ui.muted, classes [ Tw.mb s4 ] ]
            [ text "Write your tokens out in other formats and commit them to the repository." ]
        , div [ classes [ Tw.flex, Tw.flex_col, Tw.gap s2, Tw.mb s4 ] ]
            [ viewTarget model "css" "CSS custom properties" "exports/variables.css"
            , viewTarget model "tailwind" "Tailwind config" "exports/tailwind.config.js"
            ]
        , button [ Ui.btnPrimary, onClick RunExportPipeline ] [ text "Export and commit" ]
        ]


{-| The old checkboxes named only the format. Naming the file it writes makes
the commit predictable before you click.
-}
viewTarget : Model -> String -> String -> String -> Html Msg
viewTarget model target title path =
    label [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.cursor_pointer ] ]
        [ input
            [ type_ "checkbox"
            , checked (List.member target model.exportTargets)
            , onClick (ToggleExportTarget target)
            , classes [ Tw.cursor_pointer ]
            ]
            []
        , Html.span [ classes [ Tw.text_sm ] ] [ text title ]
        , Html.span [ Ui.mutedSmall, classes [ Tw.font_mono, Tw.ml s3 ] ] [ text path ]
        ]
