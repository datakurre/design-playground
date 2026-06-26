module Screens exposing (Screen, ScreenNode(..), ComponentInstanceProps, ContainerProps, decoder, encoder, screenNodeDecoder, screenNodeEncoder)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


type alias Screen =
    { name : String
    , path : String
    , root : ScreenNode
    }


type ScreenNode
    = ComponentInstance ComponentInstanceProps
    | Container ContainerProps (List ScreenNode)
    | TextNode String


type alias ComponentInstanceProps =
    { componentName : String
    , variant : Maybe String
    , state : Maybe String
    , slots : List ( String, List ScreenNode )
    }


type alias ContainerProps =
    { direction : String
    , padding : Maybe String
    , gap : Maybe String
    }


screenNodeDecoder : Decoder ScreenNode
screenNodeDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "component" ->
                        Decode.map ComponentInstance
                            (Decode.map4 ComponentInstanceProps
                                (Decode.field "componentName" Decode.string)
                                (Decode.maybe (Decode.field "variant" Decode.string))
                                (Decode.maybe (Decode.field "state" Decode.string))
                                (Decode.field "slots"
                                    (Decode.list
                                        (Decode.map2 Tuple.pair
                                            (Decode.field "name" Decode.string)
                                            (Decode.field "children" (Decode.list (Decode.lazy (\_ -> screenNodeDecoder))))
                                        )
                                    )
                                )
                            )

                    "container" ->
                        Decode.map2 Container
                            (Decode.map3 ContainerProps
                                (Decode.field "direction" Decode.string)
                                (Decode.maybe (Decode.field "padding" Decode.string))
                                (Decode.maybe (Decode.field "gap" Decode.string))
                            )
                            (Decode.field "children" (Decode.list (Decode.lazy (\_ -> screenNodeDecoder))))

                    "text" ->
                        Decode.map TextNode
                            (Decode.field "content" Decode.string)

                    _ ->
                        Decode.fail ("Unknown screen node type: " ++ type_)
            )


screenNodeEncoder : ScreenNode -> Value
screenNodeEncoder node =
    case node of
        ComponentInstance props ->
            Encode.object
                [ ( "type", Encode.string "component" )
                , ( "componentName", Encode.string props.componentName )
                , ( "variant", Maybe.withDefault Encode.null (Maybe.map Encode.string props.variant) )
                , ( "state", Maybe.withDefault Encode.null (Maybe.map Encode.string props.state) )
                , ( "slots"
                  , Encode.list
                        (\( name, children ) ->
                            Encode.object
                                [ ( "name", Encode.string name )
                                , ( "children", Encode.list screenNodeEncoder children )
                                ]
                        )
                        props.slots
                  )
                ]

        Container props children ->
            Encode.object
                [ ( "type", Encode.string "container" )
                , ( "direction", Encode.string props.direction )
                , ( "padding", Maybe.withDefault Encode.null (Maybe.map Encode.string props.padding) )
                , ( "gap", Maybe.withDefault Encode.null (Maybe.map Encode.string props.gap) )
                , ( "children", Encode.list screenNodeEncoder children )
                ]

        TextNode content ->
            Encode.object
                [ ( "type", Encode.string "text" )
                , ( "content", Encode.string content )
                ]


decoder : Decoder Screen
decoder =
    Decode.map3 Screen
        (Decode.field "name" Decode.string)
        (Decode.field "path" Decode.string)
        (Decode.field "root" screenNodeDecoder)


encoder : Screen -> Value
encoder screen =
    Encode.object
        [ ( "name", Encode.string screen.name )
        , ( "path", Encode.string screen.path )
        , ( "root", screenNodeEncoder screen.root )
        ]
