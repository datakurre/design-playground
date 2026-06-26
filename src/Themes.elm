module Themes exposing (Theme, applyTheme, fromTokens, toTokens)

import Dict exposing (Dict)
import Tokens exposing (DesignToken, FlatToken, TokenPath)


type alias Theme =
    { name : String
    , overrides : List FlatToken
    }


{-| Converts a list of FlatToken to a Dict keyed by TokenPath for easier merging.
-}
toDict : List FlatToken -> Dict TokenPath DesignToken
toDict tokens =
    Dict.fromList tokens


{-| Converts a Dict back to a List of FlatToken.
-}
fromDict : Dict TokenPath DesignToken -> List FlatToken
fromDict dict =
    Dict.toList dict


{-| Applies theme overrides to the base tokens.
It replaces base tokens with overrides if the path matches, and adds any new overrides.
-}
applyTheme : List FlatToken -> Theme -> List FlatToken
applyTheme base theme =
    let
        baseDict =
            toDict base

        overridesDict =
            toDict theme.overrides

        mergedDict =
            Dict.union overridesDict baseDict
    in
    fromDict mergedDict


{-| Helper to create a theme from parsed tokens.
-}
fromTokens : String -> List FlatToken -> Theme
fromTokens name overrides =
    { name = name, overrides = overrides }


{-| Helper to get the tokens out of a theme for saving.
-}
toTokens : Theme -> List FlatToken
toTokens theme =
    theme.overrides
