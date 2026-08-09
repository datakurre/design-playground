module Contracts exposing (Contract, Rule(..), Violation, decoder, encoder, validate)

import Colors
import Components
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Tokens exposing (TokenPath)


type alias Violation =
    { path : List Int
    , property : Maybe String
    , message : String
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


validate : List Tokens.FlatToken -> Contract -> Components.Component -> List Violation
validate tokens contract component =
    case component.layout of
        Nothing ->
            []

        Just layout ->
            styleNodes layout
                |> List.concatMap (\( path, styles ) -> List.concatMap (applyRule tokens path styles) contract.rules)


applyRule : List Tokens.FlatToken -> List Int -> Dict String String -> Rule -> List Violation
applyRule tokens path styles rule =
    case rule of
        AllowedTokenGroups groups ->
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
                                            }
                                )
                    )

        NoHardcodedValues properties ->
            styles
                |> Dict.toList
                |> List.filterMap
                    (\( property, value ) ->
                        if List.member property properties && hasHardcodedValues value then
                            Just
                                { path = path
                                , property = Just property
                                , message = "Hardcoded value found."
                                }

                        else
                            Nothing
                    )

        SpacingOnScale properties scale ->
            let
                scaleValues =
                    tokens
                        |> List.filter (\( tp, _ ) -> isPrefixOf scale tp)
                        |> List.filterMap
                            (\( _, t ) ->
                                case Tokens.resolveAliasValue tokens t.value of
                                    Tokens.StringValue s ->
                                        Just s

                                    _ ->
                                        Nothing
                            )
            in
            styles
                |> Dict.toList
                |> List.filterMap
                    (\( property, value ) ->
                        if List.member property properties then
                            let
                                resolved =
                                    Tokens.resolveAlias tokens value
                            in
                            if not (List.member resolved scaleValues) then
                                Just
                                    { path = path
                                    , property = Just property
                                    , message = "Resolved value '" ++ resolved ++ "' is not part of the required scale."
                                    }

                            else
                                Nothing

                        else
                            Nothing
                    )

        ContrastThreshold { foreground, background, minimumRatio } ->
            case ( Dict.get foreground styles, Dict.get background styles ) of
                ( Just fg, Just bg ) ->
                    let
                        fgRes =
                            Tokens.resolveAlias tokens fg

                        bgRes =
                            Tokens.resolveAlias tokens bg
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
                                  }
                                ]

                            else
                                []

                        _ ->
                            []

                _ ->
                    []


styleNodes : Components.Layout -> List ( List Int, Dict String String )
styleNodes layout =
    styleNodesHelp [] layout


styleNodesHelp : List Int -> Components.Layout -> List ( List Int, Dict String String )
styleNodesHelp path layout =
    case layout of
        Components.Stack props children ->
            ( path, props.styles ) :: List.concat (List.indexedMap (\i child -> styleNodesHelp (path ++ [ i ]) child) children)

        Components.Grid props children ->
            ( path, props.styles ) :: List.concat (List.indexedMap (\i child -> styleNodesHelp (path ++ [ i ]) child) children)

        Components.Element props _ ->
            [ ( path, props.styles ) ]

        Components.When _ children ->
            List.concat (List.indexedMap (\i child -> styleNodesHelp (path ++ [ i ]) child) children)


extractAliasPaths : String -> List Tokens.TokenPath
extractAliasPaths value =
    let
        go s acc =
            case String.indexes "{" s |> List.head of
                Just startIdx ->
                    let
                        afterBrace =
                            String.dropLeft (startIdx + 1) s
                    in
                    case String.indexes "}" afterBrace |> List.head of
                        Just endOffset ->
                            let
                                aliasPathStr =
                                    String.left endOffset afterBrace

                                aliasPath =
                                    String.split "." aliasPathStr

                                after =
                                    String.dropLeft (endOffset + 1) afterBrace
                            in
                            go after (aliasPath :: acc)

                        Nothing ->
                            acc

                Nothing ->
                    acc
    in
    go value [] |> List.reverse


hasHardcodedValues : String -> Bool
hasHardcodedValues value =
    let
        go s =
            case String.indexes "{" s |> List.head of
                Just startIdx ->
                    let
                        before =
                            String.left startIdx s

                        afterBrace =
                            String.dropLeft (startIdx + 1) s
                    in
                    case String.indexes "}" afterBrace |> List.head of
                        Just endOffset ->
                            let
                                after =
                                    String.dropLeft (endOffset + 1) afterBrace
                            in
                            before ++ go after

                        Nothing ->
                            s

                Nothing ->
                    s
    in
    String.trim (go value) /= ""


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
