module NoOnClickOnNonInteractiveElement exposing (rule)

{-| Flags `Html.Events.onClick` used on `Html.div`, `Html.span`, `Html.li` or
`Html.ul`. Every click handler elsewhere in this codebase sits on a real
`Html.button` or `Html.a`, which is what makes it keyboard-reachable and
gives assistive tech a native role. This is a regression guard: nothing in
`src/` does this today.

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
    Rule.newModuleRuleSchemaUsingContextCreator "NoOnClickOnNonInteractiveElement" contextCreator
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.fromModuleRuleSchema


type alias Context =
    { lookupTable : ModuleNameLookupTable }


contextCreator : Rule.ContextCreator () Context
contextCreator =
    Rule.initContextCreator (\lookupTable () -> { lookupTable = lookupTable })
        |> Rule.withModuleNameLookupTable


nonInteractiveElements : List String
nonInteractiveElements =
    [ "div", "span", "li", "ul" ]


expressionVisitor : Node Expression -> Context -> ( List (Rule.Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        Expression.Application (function :: attributesArg :: _) ->
            case elementName context function of
                Just name ->
                    case Node.value attributesArg of
                        Expression.ListExpr attributes ->
                            if List.any (ReviewHelpers.isCall context.lookupTable [ "Html", "Events" ] "onClick") attributes then
                                ( [ Rule.error
                                        { message = "onClick on a non-interactive <" ++ name ++ ">"
                                        , details =
                                            [ "Every click handler elsewhere in this app sits on a Html.button or Html.a, which is what makes it keyboard-reachable and gives assistive tech a native role. Use a button or a link here instead of onClick on a " ++ name ++ "."
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

                Nothing ->
                    ( [], context )

        _ ->
            ( [], context )


elementName : Context -> Node Expression -> Maybe String
elementName context function =
    nonInteractiveElements
        |> List.filter (\name -> ReviewHelpers.isCall context.lookupTable [ "Html" ] name function)
        |> List.head
