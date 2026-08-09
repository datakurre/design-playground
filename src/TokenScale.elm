module TokenScale exposing (seed, mergeStarterScale, grayRamp, brandRamp, spacingRamp, fontSizeRamp)

import Dict
import Tokens exposing (FlatToken, TokenValue(..))


grayRamp : List ( String, String )
grayRamp =
    [ ( "50", "#f9fafb" ), ( "100", "#f3f4f6" ), ( "200", "#e5e7eb" ), ( "300", "#d1d5db" ), ( "400", "#9ca3af" )
    , ( "500", "#6b7280" ), ( "600", "#4b5563" ), ( "700", "#374151" ), ( "800", "#1f2937" ), ( "900", "#111827" )
    ]


brandRamp : List ( String, String )
brandRamp =
    [ ( "50", "#eff6ff" ), ( "100", "#dbeafe" ), ( "200", "#bfdbfe" ), ( "300", "#93c5fd" ), ( "400", "#60a5fa" )
    , ( "500", "#3b82f6" ), ( "600", "#2563eb" ), ( "700", "#1d4ed8" ), ( "800", "#1e40af" ), ( "900", "#1e3a8a" )
    ]


spacingRamp : List ( String, String )
spacingRamp =
    [ ( "0", "0rem" ), ( "1", "0.25rem" ), ( "2", "0.5rem" ), ( "3", "0.75rem" ), ( "4", "1rem" )
    , ( "5", "1.25rem" ), ( "6", "1.5rem" ), ( "7", "1.75rem" ), ( "8", "2rem" ), ( "9", "2.25rem" )
    , ( "10", "2.5rem" ), ( "11", "2.75rem" ), ( "12", "3rem" )
    ]


fontSizeRamp : List ( String, String )
fontSizeRamp =
    [ ( "xs", "0.75rem" ), ( "sm", "0.875rem" ), ( "base", "1rem" ), ( "lg", "1.125rem" )
    , ( "xl", "1.25rem" ), ( "2xl", "1.5rem" ), ( "3xl", "1.875rem" )
    ]


seed : List FlatToken
seed =
    List.map (colorToken "gray") grayRamp
        ++ List.map (colorToken "brand") brandRamp
        ++ List.map (dimensionToken "spacing") spacingRamp
        ++ List.map (dimensionToken "fontSize") fontSizeRamp


colorToken : String -> ( String, String ) -> FlatToken
colorToken group ( step, hex ) =
    ( [ "color", group, step ], { value = StringValue hex, type_ = "color", description = Nothing } )


dimensionToken : String -> ( String, String ) -> FlatToken
dimensionToken group ( step, remValue ) =
    ( [ group, step ], { value = StringValue remValue, type_ = "dimension", description = Nothing } )


{-| Non-destructive: an existing token at a seeded path is left
untouched. Only paths the caller doesn't already have get added. This is
deliberately the opposite bias from `Themes.applyTheme` (where overrides
win) — a starter scale must never clobber something the user already
customized.
-}
mergeStarterScale : List FlatToken -> List FlatToken
mergeStarterScale existing =
    Dict.union (Dict.fromList existing) (Dict.fromList seed)
        |> Dict.toList
