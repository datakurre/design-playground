module Export exposing (generateCssVariables, generateTailwindConfig)

import Dict exposing (Dict)
import Tokens exposing (FlatToken, resolveAlias)


generateCssVariables : List FlatToken -> String
generateCssVariables tokens =
    let
        variables =
            List.map
                (\( path, token ) ->
                    let
                        varName =
                            "--" ++ String.join "-" path

                        resolvedValue =
                            Tokens.resolveAlias tokens token.value
                    in
                    "  " ++ varName ++ ": " ++ resolvedValue ++ ";"
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
                |> List.map
                    (\( path, token ) ->
                        let
                            -- remove "color" from path
                            keyPath =
                                List.drop 1 path
                            
                            key =
                                String.join "-" keyPath
                            
                            resolvedValue =
                                Tokens.resolveAlias tokens token.value
                        in
                        "        '" ++ key ++ "': '" ++ resolvedValue ++ "'"
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
