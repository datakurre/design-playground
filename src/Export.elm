module Export exposing (generateCssVariables, generateTailwindConfig)

import Tokens exposing (FlatToken)
import Dict


generateCssVariables : List FlatToken -> String
generateCssVariables tokens =
    let
        variables =
            List.concatMap
                (\( path, token ) ->
                    let
                        varName =
                            "--" ++ String.join "-" path
                    in
                    case Tokens.resolveAliasValue tokens token.value of
                        Tokens.StringValue s ->
                            [ "  " ++ varName ++ ": " ++ s ++ ";" ]
                        Tokens.CompositeValue dict ->
                            Dict.toList dict
                                |> List.map (\(subProp, subVal) -> 
                                    "  " ++ varName ++ "-" ++ subProp ++ ": " ++ subVal ++ ";"
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
                                [ "        '" ++ key ++ "': '" ++ s ++ "'" ]
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
