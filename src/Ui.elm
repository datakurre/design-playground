module Ui exposing
    ( pageTitle, sectionTitle, fieldLabel, muted, mutedSmall
    , panel, panelSunken, page, divider
    , btnPrimary, btnNeutral, btnDanger, btnBrand, btnSmall, btnQuiet, iconButton
    , textInput, selectInput
    , tab, themePicker
    , PillTone(..), pill
    , previewSurface
    , contextHelp, tabLede
    )

{-| The app's own chrome, in one place.

Every visual decision the editor makes about itself lives here so that pages
stay readable and so that a button looks the same wherever it appears. Before
this module the five pages had four unrelated "primary" colours (#28a745,
#4caf50, #2196f3, #e91e63) and headings ran from h2 to h6 with no scale.

The palette is deliberately neutral (slate). The previews render the user's own
design tokens, and the chrome should not compete with them.


# Type scale

Three steps, and no more.

@docs pageTitle, sectionTitle, fieldLabel, muted, mutedSmall


# Surfaces

@docs panel, panelSunken, page, divider


# Buttons

@docs btnPrimary, btnNeutral, btnDanger, btnBrand, btnSmall, btnQuiet, iconButton


# Form controls

@docs textInput, selectInput


# Navigation

@docs tab, themePicker


# Status

@docs PillTone, pill


# Preview

@docs previewSurface


# Help

@docs contextHelp, tabLede

-}

import Html exposing (Attribute, Html)
import Html.Attributes exposing (selected, value)
import Html.Events exposing (onInput)
import Tailwind as Tw exposing (Tailwind, batch, classes)
import Tailwind.Breakpoints exposing (hover)
import Tailwind.Theme exposing (emerald, orange, red, s0, s0_dot_5, s1, s1_dot_5, s2, s3, s4, s5, s6, s50, s100, s200, s300, s400, s500, s600, s700, s800, s900, slate, white)



-- TYPE SCALE


{-| The title of whatever the user is looking at. One per screen.
-}
pageTitle : Attribute msg
pageTitle =
    classes [ Tw.text_lg, Tw.font_semibold, Tw.text_color (slate s900) ]


{-| A group of controls within a page.
-}
sectionTitle : Attribute msg
sectionTitle =
    classes [ Tw.text_sm, Tw.font_semibold, Tw.text_color (slate s700) ]


{-| The label above or beside a single control.
-}
fieldLabel : Attribute msg
fieldLabel =
    classes [ Tw.text_xs, Tw.font_medium, Tw.text_color (slate s500) ]


{-| Secondary prose: hints, empty states, explanations.
-}
muted : Attribute msg
muted =
    classes [ Tw.text_sm, Tw.text_color (slate s500) ]


{-| Secondary prose that sits inside a dense row.
-}
mutedSmall : Attribute msg
mutedSmall =
    classes [ Tw.text_xs, Tw.text_color (slate s500) ]



-- SURFACES


{-| The one content column. Applied once, so the layout stops jumping width
between the project picker and the editor.
-}
page : Attribute msg
page =
    classes [ Tw.mx_auto, Tw.raw "max-w-6xl", Tw.px s4, Tw.py s4 ]


{-| A raised card holding one group of related controls.
-}
panel : Attribute msg
panel =
    classes
        [ Tw.bg_simple white
        , Tw.border
        , Tw.border_color (slate s200)
        , Tw.rounded_lg
        , Tw.p s4
        ]


{-| A recessed card, for things the user reads rather than edits.
-}
panelSunken : Attribute msg
panelSunken =
    classes
        [ Tw.bg_color (slate s50)
        , Tw.border
        , Tw.border_color (slate s200)
        , Tw.rounded_lg
        , Tw.p s4
        ]


{-| -}
divider : Attribute msg
divider =
    classes [ Tw.border_t, Tw.border_color (slate s200) ]



-- BUTTONS


btnBase : Tailwind
btnBase =
    batch
        [ Tw.inline_flex
        , Tw.items_center
        , Tw.gap s1_dot_5
        , Tw.px s3
        , Tw.py s1_dot_5
        , Tw.rounded_md
        , Tw.text_sm
        , Tw.font_medium
        , Tw.border
        , Tw.cursor_pointer
        , Tw.transition_colors
        , Tw.whitespace_nowrap
        ]


{-| The one action that commits the user's work on this screen.
-}
btnPrimary : Attribute msg
btnPrimary =
    classes
        [ btnBase
        , Tw.bg_color (slate s900)
        , Tw.border_color (slate s900)
        , Tw.text_simple white
        , hover [ Tw.bg_color (slate s700), Tw.border_color (slate s700) ]
        ]


{-| Everything else.
-}
btnNeutral : Attribute msg
btnNeutral =
    classes
        [ btnBase
        , Tw.bg_simple white
        , Tw.border_color (slate s300)
        , Tw.text_color (slate s700)
        , hover [ Tw.bg_color (slate s50), Tw.text_color (slate s900) ]
        ]


{-| Destructive, and quiet until you reach for it. These commit to Git
immediately with no confirmation step, so they should not invite a stray click.
-}
btnDanger : Attribute msg
btnDanger =
    classes
        [ btnBase
        , Tw.bg_simple white
        , Tw.border_color (slate s300)
        , Tw.text_color (red s600)
        , hover [ Tw.bg_color (red s50), Tw.border_color (red s300) ]
        ]


{-| Sign-in, in GitLab's own orange so it reads as the third-party handoff it is.
-}
btnBrand : Attribute msg
btnBrand =
    classes
        [ btnBase
        , Tw.bg_color (orange s600)
        , Tw.border_color (orange s600)
        , Tw.text_simple white
        , Tw.no_underline
        , hover [ Tw.bg_color (orange s700), Tw.border_color (orange s700) ]
        ]


{-| For the dense "+ Stack / + Grid / + Text" rows inside the layout editor.
-}
btnSmall : Attribute msg
btnSmall =
    classes
        [ Tw.inline_flex
        , Tw.items_center
        , Tw.px s2
        , Tw.py s1
        , Tw.rounded_md
        , Tw.text_xs
        , Tw.font_medium
        , Tw.border
        , Tw.cursor_pointer
        , Tw.transition_colors
        , Tw.bg_simple white
        , Tw.border_color (slate s300)
        , Tw.text_color (slate s700)
        , hover [ Tw.bg_color (slate s50), Tw.text_color (slate s900) ]
        ]


{-| A secondary action that repeats down a list. Bordered buttons at that
frequency read as clutter, so this is a quiet text action instead.
-}
btnQuiet : Attribute msg
btnQuiet =
    classes
        [ Tw.inline_flex
        , Tw.items_center
        , Tw.text_xs
        , Tw.border_none
        , Tw.p s0
        , Tw.raw "bg-transparent"
        , Tw.text_color (slate s500)
        , Tw.underline
        , Tw.cursor_pointer
        , Tw.transition_colors
        , hover [ Tw.text_color (slate s900) ]
        ]


{-| A bare glyph. Callers must pass an aria-label — the glyph alone says
nothing to a screen reader.
-}
iconButton : Attribute msg
iconButton =
    classes
        [ Tw.inline_flex
        , Tw.items_center
        , Tw.justify_center
        , Tw.w s6
        , Tw.h s6
        , Tw.rounded_md
        , Tw.border_none
        , Tw.raw "bg-transparent"
        , Tw.text_color (slate s400)
        , Tw.cursor_pointer
        , Tw.transition_colors
        , hover [ Tw.bg_color (red s50), Tw.text_color (red s600) ]
        ]



-- FORM CONTROLS


{-| -}
textInput : Attribute msg
textInput =
    classes
        [ Tw.px s2
        , Tw.py s1_dot_5
        , Tw.text_sm
        , Tw.border
        , Tw.border_color (slate s300)
        , Tw.rounded_md
        , Tw.bg_simple white
        , Tw.text_color (slate s900)
        ]


{-| -}
selectInput : Attribute msg
selectInput =
    classes
        [ Tw.px s2
        , Tw.py s1_dot_5
        , Tw.text_sm
        , Tw.border
        , Tw.border_color (slate s300)
        , Tw.rounded_md
        , Tw.bg_simple white
        , Tw.text_color (slate s900)
        , Tw.cursor_pointer
        ]



-- NAVIGATION


{-| An underlined tab. Replaces the five near-identical twenty-line button
blocks that each hardcoded a #e0f7fa fill.
-}
tab : Bool -> msg -> String -> Html msg
tab isActive msg label =
    Html.button
        [ Html.Events.onClick msg
        , Html.Attributes.attribute "aria-current"
            (if isActive then
                "page"

             else
                "false"
            )
        , classes
            [ Tw.px s1
            , Tw.py s3
            , Tw.text_sm
            , Tw.border_b_2
            , Tw.raw "bg-transparent"
            , Tw.cursor_pointer
            , Tw.transition_colors
            , if isActive then
                batch
                    [ Tw.font_semibold
                    , Tw.text_color (slate s900)
                    , Tw.border_color (slate s900)
                    ]

              else
                batch
                    [ Tw.font_medium
                    , Tw.text_color (slate s500)
                    , Tw.raw "border-transparent"
                    , hover [ Tw.text_color (slate s800) ]
                    ]
            ]
        ]
        [ Html.text label ]


{-| The same picker appeared three times with identical markup in TokenStudio,
ComponentRegistry and ScreenComposer, all driving the same global state.
-}
themePicker : List String -> Maybe String -> (Maybe String -> msg) -> Html msg
themePicker themeNames active toMsg =
    Html.select
        [ selectInput
        , Html.Attributes.attribute "aria-label" "Theme"
        , onInput
            (\val ->
                toMsg
                    (if val == "" then
                        Nothing

                     else
                        Just val
                    )
            )
        ]
        (Html.option [ value "" ] [ Html.text "Base theme" ]
            :: List.map
                (\name ->
                    Html.option [ value name, selected (active == Just name) ]
                        [ Html.text name ]
                )
                themeNames
        )



-- STATUS


{-| -}
type PillTone
    = Neutral
    | Positive
    | Negative


{-| A short status message. The old status line coloured itself by comparing
the message string to "Success!" and "Writing...", so everything else — saving,
branch switched, branch created — rendered red and read as a failure.
-}
pill : PillTone -> String -> Html msg
pill tone label =
    Html.span
        [ classes
            [ Tw.inline_flex
            , Tw.items_center
            , Tw.px s2
            , Tw.py s0_dot_5
            , Tw.rounded_full
            , Tw.text_xs
            , Tw.font_medium
            , case tone of
                Neutral ->
                    batch [ Tw.bg_color (slate s100), Tw.text_color (slate s600) ]

                Positive ->
                    batch [ Tw.bg_color (emerald s50), Tw.text_color (emerald s700) ]

                Negative ->
                    batch [ Tw.bg_color (red s50), Tw.text_color (red s700) ]
            ]
        ]
        [ Html.text label ]



-- PREVIEW


{-| The frame around a live preview. Everything *inside* it is styled from the
user's design tokens with inline styles, not from this palette.
-}
previewSurface : Attribute msg
previewSurface =
    classes
        [ Tw.border
        , Tw.raw "border-dashed"
        , Tw.border_color (slate s300)
        , Tw.rounded_md
        , Tw.bg_simple white
        , Tw.p s4
        ]



-- HELP


{-| A collapsed "?" disclosure that sits beside a page or section title and
explains the surface below it. Built on native `<details>`/`<summary>` —
the same choice `Main.elm` already makes for the repository file listing —
so whether the panel is open is plain DOM state, not something threaded
through `Model`/`Msg` for every topic.

Takes any record with `title`/`body` fields (in practice, a `Help.Topic`)
rather than importing `Help` here, so this module stays scoped to chrome —
it has no opinion on what the help text says, only how it's disclosed.

The panel is positioned rather than left in flow: every glyph sits in a
`flex items-center` heading row, so an in-flow panel grew the row and shoved
the whole section below it down each time someone opened one. It does not
close on an outside click — `<details>` has no such thing, and adding it
would mean the `Model`/`Msg` state this deliberately avoids.
-}
contextHelp : { r | title : String, body : List String } -> Html msg
contextHelp topic =
    Html.details [ classes [ Tw.relative, Tw.inline_block ] ]
        [ Html.summary
            [ classes
                [ Tw.inline_flex
                , Tw.items_center
                , Tw.justify_center
                , Tw.w s5
                , Tw.h s5
                , Tw.rounded_full
                , Tw.border
                , Tw.border_color (slate s300)
                , Tw.text_color (slate s500)
                , Tw.text_xs
                , Tw.font_medium
                , Tw.cursor_pointer
                , Tw.raw "bg-transparent"
                , Tw.transition_colors
                , Tw.raw "list-none [&::-webkit-details-marker]:hidden"
                , hover [ Tw.bg_color (slate s50), Tw.text_color (slate s900) ]
                ]
            , Html.Attributes.attribute "aria-label" ("Help: " ++ topic.title)
            ]
            [ Html.text "?" ]
        , Html.div
            [ panelSunken
            , classes
                [ Tw.absolute
                , Tw.top_full
                , Tw.raw "left-0"
                , Tw.z_10
                , Tw.mt s2

                -- Out of flow it would otherwise shrink to the glyph's width,
                -- so let it size to its text and cap that as before.
                , Tw.w_max
                , Tw.raw "max-w-md"

                -- It floats over the content now, so it has to read as
                -- something laid on top rather than part of the page.
                -- `panelSunken` already supplies an opaque background.
                , Tw.shadow_lg
                ]
            ]
            (Html.h4 [ fieldLabel, classes [ Tw.mb s1 ] ] [ Html.text topic.title ]
                :: List.map (\p -> Html.p [ muted, classes [ Tw.mt s1 ] ] [ Html.text p ]) topic.body
            )
        ]


{-| The sentence under the tab bar saying what this tab is for, with the tab's
own "?" beside it.

Collapsed help alone meant a first-run user saw no guidance at all — fifteen
topics, none of them on screen, and nothing anywhere stating that tokens come
before components come before screens. One line per tab is the cheapest thing
that is actually *read*, and it costs no `Model` state.

Renders nothing for a topic without a `lede`, so section topics can share the
`Topic` type without ever appearing here.
-}
tabLede : { r | title : String, lede : Maybe String, body : List String } -> Html msg
tabLede topic =
    case topic.lede of
        Nothing ->
            Html.text ""

        Just sentence ->
            Html.div [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.mt s3 ] ]
                [ Html.p [ muted ] [ Html.text sentence ]
                , contextHelp topic
                ]
