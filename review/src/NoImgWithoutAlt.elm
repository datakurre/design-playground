module NoImgWithoutAlt exposing (rule)

{-| Flags `Html.img` calls with no `alt` attribute. There is no `Html.img`
anywhere in this codebase today — this is a regression guard for whenever
the app adds its first image, not a fix for an existing gap.

Only literal attribute lists (`[ ... ]`) are inspected — see
`NoIconButtonWithoutAriaLabel` for why that's a real, if currently unused,
blind spot.

-}

import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node)
import Review.ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Rule)
import ReviewHelpers


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "NoImgWithoutAlt" contextCreator
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
            if ReviewHelpers.isCall context.lookupTable [ "Html" ] "img" function then
                case Node.value attributesArg of
                    Expression.ListExpr attributes ->
                        if List.any (ReviewHelpers.isCall context.lookupTable [ "Html", "Attributes" ] "alt") attributes then
                            ( [], context )

                        else
                            ( [ Rule.error
                                    { message = "Html.img is missing an alt attribute"
                                    , details =
                                        [ "Every image needs alt text, even if it's empty for a purely decorative image (Html.Attributes.alt \"\"). Without it, a screen reader has nothing to announce for this image."
                                        ]
                                    }
                                    (Node.range node)
                              ]
                            , context
                            )

                    _ ->
                        ( [], context )

            else
                ( [], context )

        _ ->
            ( [], context )
