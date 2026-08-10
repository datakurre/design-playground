module ReviewHelpers exposing (isCall)

import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)


{-| True if `expr` is a bare reference to `name` from `moduleName` (like
`Ui.iconButton`) or an application of it (like `onClick msg` or
`Html.Attributes.alt "..."`), resolved through the lookup table so it matches
regardless of whether the call site qualified the name or exposed it
unqualified.
-}
isCall : ModuleNameLookupTable -> ModuleName -> String -> Node Expression -> Bool
isCall lookupTable moduleName name expr =
    let
        head : Node Expression
        head =
            case Node.value expr of
                Expression.Application (function :: _) ->
                    function

                _ ->
                    expr
    in
    case Node.value head of
        Expression.FunctionOrValue _ actualName ->
            actualName == name && ModuleNameLookupTable.moduleNameFor lookupTable head == Just moduleName

        _ ->
            False
