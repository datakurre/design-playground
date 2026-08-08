module Contracts exposing (Contract, Rule(..), decoder, encoder)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Tokens exposing (TokenPath)


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
