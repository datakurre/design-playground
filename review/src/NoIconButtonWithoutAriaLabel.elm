module NoIconButtonWithoutAriaLabel exposing (rule)

{-| Flags any `Html.button` whose attributes include `Ui.iconButton` but no
`aria-label`. `Ui.iconButton`'s own doc comment says callers must pass one —
"the glyph alone says nothing to a screen reader" — but nothing enforced that
before this rule.

Only literal attribute lists (`[ ... ]`) are inspected. An attribute list
built via `++`, a helper function, or a bound variable is invisible to this
rule; nothing in this codebase does that today, but it's a real blind spot,
not a hypothetical one.

-}

import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Rule)
import ReviewHelpers


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "NoIconButtonWithoutAriaLabel" contextCreator
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.fromModuleRuleSchema


type alias Context =
    { lookupTable : ModuleNameLookupTable }


contextCreator : Rule.ContextCreator () Context
contextCreator =
    Rule.initContextCreator (\lookupTable () -> { lookupTable = lookupTable })
        |> Rule.withModuleNameLookupTable


expressionVisitor : Node Expression -> Context -> ( List (Rule.Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        Expression.Application (function :: attributesArg :: _) ->
            if ReviewHelpers.isCall context.lookupTable [ "Html" ] "button" function then
                case Node.value attributesArg of
                    Expression.ListExpr attributes ->
                        if hasIconButton context attributes && not (hasAriaLabel context attributes) then
                            ( [ Rule.error
                                    { message = "Icon-only button is missing an aria-label"
                                    , details =
                                        [ "This button uses Ui.iconButton, a bare glyph with no visible text. Its doc comment requires callers to pass an aria-label, because the glyph alone says nothing to a screen reader. Add Html.Attributes.attribute \"aria-label\" \"...\" to this button's attributes."
                                        ]
                                    }
                                    (Node.range node)
                              ]
                            , context
                            )

                        else
                            ( [], context )

                    _ ->
                        ( [], context )

            else
                ( [], context )

        _ ->
            ( [], context )


hasIconButton : Context -> List (Node Expression) -> Bool
hasIconButton context attributes =
    List.any (ReviewHelpers.isCall context.lookupTable [ "Ui" ] "iconButton") attributes


hasAriaLabel : Context -> List (Node Expression) -> Bool
hasAriaLabel context attributes =
    List.any (isAriaLabelAttribute context) attributes


isAriaLabelAttribute : Context -> Node Expression -> Bool
isAriaLabelAttribute context node =
    case Node.value node of
        Expression.Application (_ :: nameArg :: _) ->
            ReviewHelpers.isCall context.lookupTable [ "Html", "Attributes" ] "attribute" node
                && isStringLiteral "aria-label" nameArg

        _ ->
            False


isStringLiteral : String -> Node Expression -> Bool
isStringLiteral expected node =
    case Node.value node of
        Expression.Literal value ->
            value == expected

        _ ->
            False
