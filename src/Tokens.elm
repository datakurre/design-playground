module Tokens exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder, Value)
import Json.Encode as Encode


type alias TokenPath =
    List String


type TokenValue
    = StringValue String
    | CompositeValue (Dict String String)


type alias DesignToken =
    { value : TokenValue
    , type_ : String
    , description : Maybe String
    }


type alias FlatToken =
    ( TokenPath, DesignToken )


type AstNode
    = TokenNode DesignToken
    | GroupNode (Dict String AstNode)



-- DECODER


tokenValueDecoder : Decoder TokenValue
tokenValueDecoder =
    Decode.oneOf
        [ Decode.string |> Decode.map StringValue
        , Decode.int |> Decode.map (String.fromInt >> StringValue)
        , Decode.float |> Decode.map (String.fromFloat >> StringValue)
        , Decode.dict (Decode.oneOf [ Decode.string, Decode.map String.fromInt Decode.int, Decode.map String.fromFloat Decode.float ]) |> Decode.map CompositeValue
        ]


astDecoder : Decoder AstNode
astDecoder =
    Decode.oneOf
        [ Decode.map TokenNode
            (Decode.map3 DesignToken
                (Decode.field "$value" tokenValueDecoder)
                (Decode.oneOf [ Decode.field "$type" Decode.string, Decode.succeed "unknown" ])
                (Decode.maybe (Decode.field "$description" Decode.string))
            )
        , Decode.dict (Decode.lazy (\_ -> astDecoder))
            |> Decode.map (\dict -> GroupNode (Dict.filter (\k _ -> not (String.startsWith "$" k)) dict))
        ]


flattenAst : AstNode -> List FlatToken
flattenAst node =
    flattenAstHelp [] node


flattenAstHelp : TokenPath -> AstNode -> List FlatToken
flattenAstHelp path node =
    case node of
        TokenNode token ->
            [ ( List.reverse path, token ) ]

        GroupNode dict ->
            Dict.toList dict
                |> List.concatMap (\( k, v ) -> flattenAstHelp (k :: path) v)


decoder : Decoder (List FlatToken)
decoder =
    Decode.map flattenAst astDecoder


{-| Markers for a reference that could not be turned into a value.

They are deliberately shaped like the `{…}` syntax they replace, so anything
downstream that already treats a leftover brace as "not a real value" keeps
working — but they say _why_, which the bare input never did. `isUnresolved`
is the one place that knows the set.

-}
cyclicMarker : String -> String
cyclicMarker value =
    "{[Cyclic: " ++ value ++ "]}"


compositeMarker : String -> String
compositeMarker path =
    "{[Composite: " ++ path ++ "]}"


{-| Whether a resolved value still contains a reference that didn't resolve —
a missing token, a composite used where a string was wanted, or an alias chain
that ran past its depth budget.

Callers need this because `resolveAlias` is total: it always returns a string,
and without asking, a cycle looks exactly like a colour that happens to be
spelled oddly.

-}
isUnresolved : String -> Bool
isUnresolved value =
    String.contains "{[Cyclic:" value
        || String.contains "{[Composite:" value
        || String.contains "{" value


resolveAlias : List FlatToken -> String -> String
resolveAlias tokens value =
    resolveAliasHelp tokens value 10


resolveAliasHelp : List FlatToken -> String -> Int -> String
resolveAliasHelp tokens value depth =
    if depth <= 0 then
        -- Out of budget means an alias chain longer than any real token graph,
        -- which in practice means a cycle. Returning `value` unchanged — what
        -- this used to do — hands back a plausible-looking string that no
        -- caller can tell apart from a resolved one.
        cyclicMarker value

    else
        case String.indexes "{" value |> List.head of
            Just startIdx ->
                let
                    afterBrace =
                        String.dropLeft (startIdx + 1) value
                in
                case String.indexes "}" afterBrace |> List.head of
                    Just endOffset ->
                        let
                            aliasPathStr =
                                String.left endOffset afterBrace

                            aliasPath =
                                String.split "." aliasPathStr

                            resolvedAlias =
                                List.filter (\( p, _ ) -> p == aliasPath) tokens
                                    |> List.head
                                    |> Maybe.map
                                        (\( _, t ) ->
                                            case t.value of
                                                StringValue s ->
                                                    resolveAliasHelp tokens s (depth - 1)

                                                CompositeValue _ ->
                                                    compositeMarker aliasPathStr
                                        )
                                    |> Maybe.withDefault ("{" ++ aliasPathStr ++ "}")

                            before =
                                String.left startIdx value

                            after =
                                String.dropLeft (endOffset + 1) afterBrace
                        in
                        before ++ resolvedAlias ++ resolveAliasHelp tokens after depth

                    Nothing ->
                        value

            Nothing ->
                value



-- ENCODER


buildAst : List FlatToken -> AstNode
buildAst tokens =
    List.foldl insertIntoAst (GroupNode Dict.empty) tokens


insertIntoAst : FlatToken -> AstNode -> AstNode
insertIntoAst ( path, token ) ast =
    case path of
        [] ->
            ast

        [ name ] ->
            case ast of
                GroupNode dict ->
                    GroupNode (Dict.insert name (TokenNode token) dict)

                _ ->
                    ast

        name :: rest ->
            case ast of
                GroupNode dict ->
                    let
                        child =
                            Dict.get name dict |> Maybe.withDefault (GroupNode Dict.empty)

                        newChild =
                            insertIntoAst ( rest, token ) child
                    in
                    GroupNode (Dict.insert name newChild dict)

                _ ->
                    ast


resolveAliasValue : List FlatToken -> TokenValue -> TokenValue
resolveAliasValue tokens tv =
    case tv of
        StringValue s ->
            StringValue (resolveAlias tokens s)

        CompositeValue dict ->
            CompositeValue (Dict.map (\_ v -> resolveAlias tokens v) dict)


tokenValueEncoder : TokenValue -> Value
tokenValueEncoder tv =
    case tv of
        StringValue s ->
            Encode.string s

        CompositeValue dict ->
            Encode.dict identity Encode.string dict


astEncoder : AstNode -> Value
astEncoder node =
    case node of
        TokenNode token ->
            let
                base =
                    [ ( "$value", tokenValueEncoder token.value )
                    , ( "$type", Encode.string token.type_ )
                    ]

                withDesc =
                    case token.description of
                        Just d ->
                            ( "$description", Encode.string d ) :: base

                        Nothing ->
                            base
            in
            Encode.object withDesc

        GroupNode dict ->
            Encode.dict identity astEncoder dict


encoder : List FlatToken -> Value
encoder tokens =
    astEncoder (buildAst tokens)
