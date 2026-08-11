module Export exposing (escapeCssValue, escapeJsString, generateCssVariables, generateTailwindConfig)

import Dict
import Tokens exposing (FlatToken)


{-| Token names and values come out of a repository, and a repository is
something someone else can write. Both generators build their output by
concatenating strings, so without this a token value containing a quote, a
newline or a `}` doesn't produce a broken file — it produces a working file
that says something the author didn't write.

`escapeCssValue` drops the characters that would end the declaration or the
block early. `escapeJsString` escapes rather than drops, because a JS string
literal has a real escape syntax and a colour like `rgb(0, 0, 0)` is legitimate
content that shouldn't be mangled.

-}
escapeCssValue : String -> String
escapeCssValue value =
    value
        |> String.replace "\\" ""
        |> String.replace ";" ""
        |> String.replace "}" ""
        |> String.replace "{" ""
        |> String.replace "\n" " "
        |> String.replace "\u{000D}" " "
        |> String.trim


escapeJsString : String -> String
escapeJsString value =
    value
        |> String.replace "\\" "\\\\"
        |> String.replace "'" "\\'"
        |> String.replace "\n" "\\n"
        |> String.replace "\u{000D}" "\\r"
        |> String.replace "\u{2028}" "\\u2028"
        |> String.replace "\u{2029}" "\\u2029"


{-| A CSS custom property name may not contain whitespace, quotes, braces or a
semicolon. Token path segments are normally plain identifiers, but nothing
guarantees it, so the name gets the same treatment as the value.
-}
escapeCssName : String -> String
escapeCssName name =
    name
        |> String.replace " " "-"
        |> escapeCssValue


generateCssVariables : List FlatToken -> String
generateCssVariables tokens =
    let
        variables =
            List.concatMap
                (\( path, token ) ->
                    let
                        varName =
                            "--" ++ escapeCssName (String.join "-" path)
                    in
                    case Tokens.resolveAliasValue tokens token.value of
                        Tokens.StringValue s ->
                            [ "  " ++ varName ++ ": " ++ escapeCssValue s ++ ";" ]

                        Tokens.CompositeValue dict ->
                            Dict.toList dict
                                |> List.map
                                    (\( subProp, subVal ) ->
                                        "  " ++ varName ++ "-" ++ escapeCssName subProp ++ ": " ++ escapeCssValue subVal ++ ";"
                                    )
                )
                tokens
    in
    ":root {\n" ++ String.join "\n" variables ++ "\n}\n"


generateTailwindConfig : List FlatToken -> String
generateTailwindConfig tokens =
    let
        -- For a simple tailwind config, we'll map tokens to a nested JS object
        -- Assuming top-level categories like "color", "font", "spacing" map to tailwind theme keys.
        colors =
            List.filter (\( path, _ ) -> List.head path == Just "color") tokens
                |> List.concatMap
                    (\( path, token ) ->
                        let
                            keyPath =
                                List.drop 1 path

                            key =
                                String.join "-" keyPath
                        in
                        case Tokens.resolveAliasValue tokens token.value of
                            Tokens.StringValue s ->
                                [ "        '" ++ escapeJsString key ++ "': '" ++ escapeJsString s ++ "'" ]

                            Tokens.CompositeValue _ ->
                                []
                    )
    in
    """module.exports = {
  theme: {
    extend: {
      colors: {
"""
        ++ String.join ",\n" colors
        ++ """
      }
    }
  }
};
"""
