module RepoPaths exposing
    ( componentFile
    , contractFile
    , exportCss
    , exportTailwind
    , isContractFile
    , nameFromComponentFile
    , nameFromContractFile
    , nameFromScreenFile
    , nameFromThemeFile
    , screenFile
    , themeFile
    , tokensFile
    )

{-| Where a design system lives inside a repository.

This convention — `tokens/tokens.json`, `components/<name>.json`, that
component's `.contract.json` beside it, `layouts/<name>.json` — used to be
spelled out at roughly twenty sites in `Update`, once per save, once per delete
and once per load. It is the sort of duplication that stays correct right up
until one path needs to change, and then stays correct at nineteen of the twenty
places.

The `nameFrom…` direction matters as much as the forward one. Reading a
component's name back out of its filename was done with
`String.replace ".json" ""`, which is a substring replacement rather than a
suffix strip: a component called `My.jsonic` came back as `My.ic`, and every
`.contract.json` came back with a `.contract` still attached unless the caller
happened to strip that first.

-}


tokensFile : String
tokensFile =
    "tokens/tokens.json"


themeFile : String -> String
themeFile name =
    "themes/" ++ name ++ ".json"


componentFile : String -> String
componentFile name =
    "components/" ++ name ++ ".json"


{-| A component's usage contract sits beside the component, not in a directory
of its own, so the two move and delete together.
-}
contractFile : String -> String
contractFile name =
    "components/" ++ name ++ ".contract.json"


screenFile : String -> String
screenFile name =
    "layouts/" ++ name ++ ".json"


exportCss : String
exportCss =
    "exports/variables.css"


exportTailwind : String
exportTailwind =
    "exports/tailwind.config.js"


{-| Both live under `components/` and both end in `.json`, so the contract
suffix is the only thing that tells them apart — and it has to be checked
before the plain `.json` one, or every contract reads as a component.
-}
isContractFile : String -> Bool
isContractFile name =
    String.endsWith ".contract.json" name


{-| Each of these takes either a bare filename or a full repository path, since
a tree listing gives one and a save site has the other.
-}
nameFromThemeFile : String -> String
nameFromThemeFile =
    basename >> dropSuffix ".json"


nameFromComponentFile : String -> String
nameFromComponentFile =
    basename >> dropSuffix ".json"


nameFromContractFile : String -> String
nameFromContractFile =
    basename >> dropSuffix ".contract.json"


nameFromScreenFile : String -> String
nameFromScreenFile =
    basename >> dropSuffix ".json"


basename : String -> String
basename path =
    path |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault path


dropSuffix : String -> String -> String
dropSuffix suffix name =
    if String.endsWith suffix name then
        String.dropRight (String.length suffix) name

    else
        name
