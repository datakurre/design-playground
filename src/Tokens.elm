module Tokens exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder, Value)
import Json.Encode as Encode


type alias TokenPath =
    List String


type alias DesignToken =
    { value : String
    , type_ : String
    , description : Maybe String
    }


type alias FlatToken =
    ( TokenPath, DesignToken )


type AstNode
    = TokenNode DesignToken
    | GroupNode (Dict String AstNode)



-- DECODER


astDecoder : Decoder AstNode
astDecoder =
    Decode.oneOf
        [ Decode.map TokenNode
            (Decode.map3 DesignToken
                (Decode.field "$value" Decode.string)
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


resolveAlias : List FlatToken -> String -> String
resolveAlias tokens value =
    if String.startsWith "{" value && String.endsWith "}" value then
        let
            aliasPathStr =
                String.dropLeft 1 value |> String.dropRight 1

            aliasPath =
                String.split "." aliasPathStr

            maybeToken =
                List.filter (\( p, _ ) -> p == aliasPath) tokens |> List.head
        in
        case maybeToken of
            Just ( _, token ) ->
                -- Recursively resolve in case the alias points to another alias
                resolveAlias tokens token.value

            Nothing ->
                value

    else
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


astEncoder : AstNode -> Value
astEncoder node =
    case node of
        TokenNode token ->
            let
                base =
                    [ ( "$value", Encode.string token.value )
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
