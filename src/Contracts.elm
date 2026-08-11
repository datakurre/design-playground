module Contracts exposing (Contract, Rule(..), Severity(..), Violation, decoder, encoder, validate)

import Colors
import Components
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Tokens exposing (TokenPath)


{-| Whether the rule was broken, or whether it couldn't be checked at all.

`Unverifiable` exists because silence used to mean both. `ContrastThreshold`
can only read hex, so a colour resolving to `rgb(…)`, `hsl(…)` or
`currentColor` produced no violation — indistinguishable from a pairing that
passes. A rule that cannot see its input should say so rather than report
success.

-}
type Severity
    = Broken
    | Unverifiable


{-| Where a rule was broken. `context` is `Nothing` for a component's base
styles and `Just` the variant/state whose style layer introduced the problem —
a hardcoded colour written only for the `danger` variant is still a hardcoded
colour, and the editor has to be able to say which layer to open.
-}
type alias Violation =
    { path : List Int
    , property : Maybe String
    , message : String
    , context : Maybe Components.StyleContext
    , severity : Severity
    }


type Rule
    = AllowedTokenGroups (List TokenPath)
    | NoHardcodedValues (List String)
    | SpacingOnScale (List String) TokenPath
    | ContrastThreshold { foreground : String, background : String, minimumRatio : Float }


type alias Contract =
    { component : String
    , rules : List Rule
    }


tokenPathDecoder : Decoder TokenPath
tokenPathDecoder =
    Decode.string |> Decode.map (String.split ".")


tokenPathEncoder : TokenPath -> Value
tokenPathEncoder path =
    Encode.string (String.join "." path)


ruleDecoder : Decoder Rule
ruleDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "allowedTokenGroups" ->
                        Decode.map AllowedTokenGroups
                            (Decode.field "groups" (Decode.list tokenPathDecoder))

                    "noHardcodedValues" ->
                        Decode.map NoHardcodedValues
                            (Decode.field "properties" (Decode.list Decode.string))

                    "spacingOnScale" ->
                        Decode.map2 SpacingOnScale
                            (Decode.field "properties" (Decode.list Decode.string))
                            (Decode.field "scale" tokenPathDecoder)

                    "contrastThreshold" ->
                        Decode.map ContrastThreshold
                            (Decode.map3 (\fg bg ratio -> { foreground = fg, background = bg, minimumRatio = ratio })
                                (Decode.field "foreground" Decode.string)
                                (Decode.field "background" Decode.string)
                                (Decode.field "minimumRatio" Decode.float)
                            )

                    _ ->
                        Decode.fail ("Unknown rule type: " ++ type_)
            )


ruleEncoder : Rule -> Value
ruleEncoder rule =
    case rule of
        AllowedTokenGroups groups ->
            Encode.object
                [ ( "type", Encode.string "allowedTokenGroups" )
                , ( "groups", Encode.list tokenPathEncoder groups )
                ]

        NoHardcodedValues properties ->
            Encode.object
                [ ( "type", Encode.string "noHardcodedValues" )
                , ( "properties", Encode.list Encode.string properties )
                ]

        SpacingOnScale properties scale ->
            Encode.object
                [ ( "type", Encode.string "spacingOnScale" )
                , ( "properties", Encode.list Encode.string properties )
                , ( "scale", tokenPathEncoder scale )
                ]

        ContrastThreshold { foreground, background, minimumRatio } ->
            Encode.object
                [ ( "type", Encode.string "contrastThreshold" )
                , ( "foreground", Encode.string foreground )
                , ( "background", Encode.string background )
                , ( "minimumRatio", Encode.float minimumRatio )
                ]


decoder : Decoder Contract
decoder =
    Decode.map2 Contract
        (Decode.field "component" Decode.string)
        (Decode.field "rules" (Decode.list ruleDecoder))


encoder : Contract -> Value
encoder contract =
    Encode.object
        [ ( "component", Encode.string contract.component )
        , ( "rules", Encode.list ruleEncoder contract.rules )
        ]


{-| What the rules need to look values up with, computed once per `validate`
rather than per node.
-}
type alias Resolver =
    { tokens : Tokens.Index
    , scales : Dict String (List String)
    }


{-| The resolved values of every scale any `SpacingOnScale` rule names, keyed by
the dotted path that named it.
-}
scalesFor : List Tokens.FlatToken -> Contract -> Dict String (List String)
scalesFor tokens contract =
    let
        indexed =
            Tokens.index tokens

        valuesUnder scale =
            tokens
                |> List.filter (\( tp, _ ) -> isPrefixOf scale tp)
                |> List.filterMap
                    (\( _, t ) ->
                        case Tokens.resolveAliasValueWith indexed t.value of
                            Tokens.StringValue s ->
                                Just s

                            _ ->
                                Nothing
                    )
    in
    contract.rules
        |> List.filterMap
            (\rule ->
                case rule of
                    SpacingOnScale _ scale ->
                        Just ( String.join "." scale, valuesUnder scale )

                    _ ->
                        Nothing
            )
        |> Dict.fromList


{-| Every rule, against every node, in every context the component actually
styles.

Checking the base styles alone would let anything written for a variant through,
which is most of what a design system's colour decisions are. The contexts come
from the layers the author wrote rather than from every combination of the
component's variant and state lists — four variants and five states is twenty
combinations and almost none of them exist.

-}
validate : List Tokens.FlatToken -> Contract -> Components.Component -> List Violation
validate tokens contract component =
    case component.layout of
        Nothing ->
            []

        Just layout ->
            let
                nodes =
                    styleNodes layout

                -- Indexed once for the whole component, and each
                -- `SpacingOnScale` rule's scale resolved once with it. Both
                -- used to be rebuilt inside `applyRule`, which runs per node
                -- per context.
                resolver =
                    { tokens = Tokens.index tokens
                    , scales = scalesFor tokens contract
                    }

                violationsIn context =
                    List.concatMap (\( path, node ) -> checkNode resolver contract path context node) nodes

                baseViolations =
                    violationsIn Components.baseContext

                -- A problem in the base styles is one problem, however many
                -- variants inherit it.
                alreadyReported violation =
                    List.any
                        (\base ->
                            base.path
                                == violation.path
                                && base.property
                                == violation.property
                                && base.message
                                == violation.message
                        )
                        baseViolations
            in
            baseViolations
                ++ (Components.styleContexts layout
                        |> List.filter (\context -> context /= Components.baseContext)
                        |> List.concatMap (violationsIn >> List.filter (not << alreadyReported))
                   )


{-| One node, in one context.

The property-scoped rules look only at what this context _changes_, so a
hardcoded base value isn't re-reported under every variant that inherits it.
`ContrastThreshold` can't work that way — a variant that overrides only the
background still changes the pairing — so it reads the fully resolved styles,
and the caller drops whatever that duplicates from the base.

-}
checkNode : Resolver -> Contract -> List Int -> Components.StyleContext -> Components.Styling -> List Violation
checkNode resolver contract path context node =
    let
        resolved =
            Components.resolveStyles context node

        scoped =
            if context == Components.baseContext then
                resolved

            else
                let
                    inherited =
                        Components.resolveStyles Components.baseContext node
                in
                Dict.filter (\property value -> Dict.get property inherited /= Just value) resolved

        tag =
            if context == Components.baseContext then
                Nothing

            else
                Just context
    in
    List.concatMap (applyRule resolver path tag { scoped = scoped, resolved = resolved }) contract.rules


applyRule : Resolver -> List Int -> Maybe Components.StyleContext -> { scoped : Dict String String, resolved : Dict String String } -> Rule -> List Violation
applyRule resolver path context nodeStyles rule =
    let
        styles =
            nodeStyles.scoped
    in
    case rule of
        AllowedTokenGroups groups ->
            -- The one rule that deliberately does _not_ resolve aliases, where
            -- the other three do. It governs what a component is allowed to
            -- reference, so it reads the path as written: if `color.brand.primary`
            -- is permitted, a component naming it stays legal no matter what
            -- that token is later re-pointed at. Following the chain here would
            -- turn "which vocabulary may this component use" into "what value
            -- does it end up with", which is what the other rules are for.
            styles
                |> Dict.toList
                |> List.concatMap
                    (\( property, value ) ->
                        extractAliasPaths value
                            |> List.filterMap
                                (\aliasPath ->
                                    if List.any (\grp -> isPrefixOf grp aliasPath) groups then
                                        Nothing

                                    else
                                        Just
                                            { path = path
                                            , property = Just property
                                            , message = "Token path '" ++ String.join "." aliasPath ++ "' is not in allowed groups."
                                            , context = context
                                            , severity = Broken
                                            }
                                )
                    )

        NoHardcodedValues properties ->
            styles
                |> Dict.toList
                |> List.filterMap
                    (\( property, value ) ->
                        case ( propertyMatches properties property, hardcodedPart value ) of
                            ( True, "" ) ->
                                Nothing

                            ( True, literal ) ->
                                -- Naming the literal is the difference between
                                -- "something here is wrong" and knowing which
                                -- part of `1px solid {core.border}` to replace.
                                Just
                                    { path = path
                                    , property = Just property
                                    , message = "Hardcoded value: " ++ literal
                                    , context = context
                                    , severity = Broken
                                    }

                            ( False, _ ) ->
                                Nothing
                    )

        SpacingOnScale properties scale ->
            let
                scaleValues =
                    Dict.get (String.join "." scale) resolver.scales
                        |> Maybe.withDefault []
            in
            styles
                |> Dict.toList
                |> List.filterMap
                    (\( property, value ) ->
                        if propertyMatches properties property then
                            let
                                resolved =
                                    Tokens.resolveAliasWith resolver.tokens value
                            in
                            if Tokens.isUnresolved resolved then
                                -- A reference that didn't resolve isn't off the
                                -- scale; it's a value we never got to see.
                                Just
                                    { path = path
                                    , property = Just property
                                    , message = "Couldn't check: '" ++ value ++ "' does not resolve to a value."
                                    , context = context
                                    , severity = Unverifiable
                                    }

                            else if not (List.member resolved scaleValues) then
                                Just
                                    { path = path
                                    , property = Just property
                                    , message = "Resolved value '" ++ resolved ++ "' is not part of the required scale."
                                    , context = context
                                    , severity = Broken
                                    }

                            else
                                Nothing

                        else
                            Nothing
                    )

        ContrastThreshold { foreground, background, minimumRatio } ->
            -- The one rule that reads the whole node rather than what this
            -- context changed: overriding just the background in a variant
            -- still changes what the unchanged text colour sits on.
            case ( Dict.get foreground nodeStyles.resolved, Dict.get background nodeStyles.resolved ) of
                ( Just fg, Just bg ) ->
                    let
                        fgRes =
                            Tokens.resolveAliasWith resolver.tokens fg

                        bgRes =
                            Tokens.resolveAliasWith resolver.tokens bg

                        unverifiable why =
                            [ { path = path
                              , property = Nothing
                              , message = "Couldn't check contrast: " ++ why
                              , context = context
                              , severity = Unverifiable
                              }
                            ]
                    in
                    case ( Colors.parseHex fgRes, Colors.parseHex bgRes ) of
                        ( Just fgColor, Just bgColor ) ->
                            let
                                ratio =
                                    Colors.contrastRatio fgColor bgColor
                            in
                            if ratio < minimumRatio then
                                let
                                    ratioRounded =
                                        toFloat (round (ratio * 100)) / 100
                                in
                                [ { path = path
                                  , property = Nothing
                                  , message = "Contrast ratio " ++ String.fromFloat ratioRounded ++ " is below minimum " ++ String.fromFloat minimumRatio
                                  , context = context
                                  , severity = Broken
                                  }
                                ]

                            else
                                []

                        ( Nothing, Just _ ) ->
                            unverifiable (foreground ++ " resolves to '" ++ fgRes ++ "', which isn't a hex colour.")

                        ( Just _, Nothing ) ->
                            unverifiable (background ++ " resolves to '" ++ bgRes ++ "', which isn't a hex colour.")

                        ( Nothing, Nothing ) ->
                            unverifiable ("neither " ++ foreground ++ " ('" ++ fgRes ++ "') nor " ++ background ++ " ('" ++ bgRes ++ "') is a hex colour.")

                -- Only one of the pair being styled is a component that hasn't
                -- made the decision yet, not a rule that failed to run.
                _ ->
                    []


styleNodes : Components.Layout -> List ( List Int, Components.Styling )
styleNodes layout =
    styleNodesHelp [] layout


styleNodesHelp : List Int -> Components.Layout -> List ( List Int, Components.Styling )
styleNodesHelp path layout =
    let
        -- `When` carries no styles of its own, so `Components.styling` gives it
        -- nothing and it contributes only its children.
        here =
            case Components.styling layout of
                Just node ->
                    [ ( path, node ) ]

                Nothing ->
                    []

        nested children =
            List.concat (List.indexedMap (\i child -> styleNodesHelp (path ++ [ i ]) child) children)
    in
    case layout of
        Components.Stack _ children ->
            here ++ nested children

        Components.Grid _ children ->
            here ++ nested children

        Components.When _ children ->
            here ++ nested children

        Components.Element _ _ ->
            here


{-| A style value split into the `{token.path}` references it makes and the
literal text around them: `"1px solid {core.border}"` is the alias
`core.border` and the literal `"1px solid "`.

Two rules read a value, and they want opposite halves of the same reading — one
asks what it points at, the other what it states outright — so the scan happens
once, here. An unclosed `{` isn't a reference, so it stays literal.

-}
type alias ValueParts =
    { aliases : List String
    , literal : String
    }


valueParts : String -> ValueParts
valueParts value =
    let
        go s acc =
            case String.indexes "{" s |> List.head of
                Nothing ->
                    { acc | literal = acc.literal ++ s }

                Just startIdx ->
                    let
                        afterBrace =
                            String.dropLeft (startIdx + 1) s
                    in
                    case String.indexes "}" afterBrace |> List.head of
                        Nothing ->
                            { acc | literal = acc.literal ++ s }

                        Just endOffset ->
                            go (String.dropLeft (endOffset + 1) afterBrace)
                                { aliases = acc.aliases ++ [ String.left endOffset afterBrace ]
                                , literal = acc.literal ++ String.left startIdx s
                                }
    in
    go value { aliases = [], literal = "" }


extractAliasPaths : String -> List Tokens.TokenPath
extractAliasPaths value =
    (valueParts value).aliases
        |> List.map (String.split ".")


{-| Whatever a value says on its own account, once its token references are
taken out. Empty means the value is made of tokens and nothing else.
-}
hardcodedPart : String -> String
hardcodedPart value =
    (valueParts value).literal
        |> String.trim


isPrefixOf : List a -> List a -> Bool
isPrefixOf prefix list =
    case ( prefix, list ) of
        ( [], _ ) ->
            True

        ( _, [] ) ->
            False

        ( p :: ps, l :: ls ) ->
            if p == l then
                isPrefixOf ps ls

            else
                False


propertyMatches : List String -> String -> Bool
propertyMatches patterns property =
    List.any (\pattern -> matchPattern pattern property) patterns


matchPattern : String -> String -> Bool
matchPattern pattern property =
    case String.split "*" pattern of
        [] ->
            property == ""

        [ exact ] ->
            exact == property

        first :: rest ->
            if not (String.startsWith first property) then
                False

            else
                matchRest rest (String.dropLeft (String.length first) property)


matchRest : List String -> String -> Bool
matchRest parts property =
    case parts of
        [] ->
            True

        [ last ] ->
            String.endsWith last property

        next :: rest ->
            case String.indexes next property |> List.head of
                Nothing ->
                    False

                Just idx ->
                    matchRest rest (String.dropLeft (idx + String.length next) property)
