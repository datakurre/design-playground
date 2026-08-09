module Components exposing (Component, decoder, encoder, Layout(..), StackProps, GridProps, ElementProps, layoutDecoder, layoutEncoder)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


type Layout
    = Stack StackProps (List Layout)
    | Grid GridProps (List Layout)
    | Element ElementProps String
    | When WhenProps (List Layout)

type alias WhenProps =
    { variant : Maybe String
    , state : Maybe String
    }

type alias StackProps =
    { direction : String
    , styles : Dict String String
    }

type alias GridProps =
    { columns : Int
    , styles : Dict String String
    }

type alias ElementProps =
    { isSlot : Bool
    , styles : Dict String String
    }

type alias Component =
    { name : String
    , description : Maybe String
    , variants : List String
    , slots : List String
    , states : List String
    , layout : Maybe Layout
    }

layoutDecoder : Decoder Layout
layoutDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "stack" ->
                        Decode.map2 Stack
                            (Decode.map2 StackProps
                                (Decode.field "direction" Decode.string)
                                (Decode.field "styles" (Decode.dict Decode.string) |> Decode.map (\d -> d) |> orElse (Decode.succeed Dict.empty))
                            )
                            (Decode.field "children" (Decode.list (Decode.lazy (\_ -> layoutDecoder))))

                    "grid" ->
                        Decode.map2 Grid
                            (Decode.map2 GridProps
                                (Decode.field "columns" Decode.int)
                                (Decode.field "styles" (Decode.dict Decode.string) |> Decode.map (\d -> d) |> orElse (Decode.succeed Dict.empty))
                            )
                            (Decode.field "children" (Decode.list (Decode.lazy (\_ -> layoutDecoder))))

                    "element" ->
                        Decode.map2 Element
                            (Decode.map2 ElementProps
                                (Decode.field "isSlot" Decode.bool)
                                (Decode.field "styles" (Decode.dict Decode.string) |> Decode.map (\d -> d) |> orElse (Decode.succeed Dict.empty))
                            )
                            (Decode.field "content" Decode.string)

                    "when" ->
                        Decode.map2 When
                            (Decode.map2 WhenProps
                                (Decode.maybe (Decode.field "variant" Decode.string))
                                (Decode.maybe (Decode.field "state" Decode.string))
                            )
                            (Decode.field "children" (Decode.list (Decode.lazy (\_ -> layoutDecoder))))

                    _ ->
                        Decode.fail ("Unknown layout type: " ++ type_)
            )

orElse : Decoder a -> Decoder a -> Decoder a
orElse fallback decoder2 =
    Decode.oneOf [ decoder2, fallback ]

layoutEncoder : Layout -> Value
layoutEncoder layout =
    case layout of
        Stack props children ->
            Encode.object
                [ ( "type", Encode.string "stack" )
                , ( "direction", Encode.string props.direction )
                , ( "styles", Encode.dict identity Encode.string props.styles )
                , ( "children", Encode.list layoutEncoder children )
                ]

        Grid props children ->
            Encode.object
                [ ( "type", Encode.string "grid" )
                , ( "columns", Encode.int props.columns )
                , ( "styles", Encode.dict identity Encode.string props.styles )
                , ( "children", Encode.list layoutEncoder children )
                ]

        Element props content ->
            Encode.object
                [ ( "type", Encode.string "element" )
                , ( "isSlot", Encode.bool props.isSlot )
                , ( "styles", Encode.dict identity Encode.string props.styles )
                , ( "content", Encode.string content )
                ]

        When props children ->
            let
                baseFields =
                    [ ( "type", Encode.string "when" )
                    , ( "children", Encode.list layoutEncoder children )
                    ]
                
                variantFields =
                    case props.variant of
                        Just v -> [ ( "variant", Encode.string v ) ]
                        Nothing -> []
                        
                stateFields =
                    case props.state of
                        Just s -> [ ( "state", Encode.string s ) ]
                        Nothing -> []
            in
            Encode.object (baseFields ++ variantFields ++ stateFields)

decoder : Decoder Component
decoder =
    Decode.map6 Component
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "description" Decode.string))
        (Decode.field "variants" (Decode.list Decode.string))
        (Decode.field "slots" (Decode.list Decode.string))
        (Decode.field "states" (Decode.list Decode.string))
        (Decode.maybe (Decode.field "layout" layoutDecoder))

encoder : Component -> Value
encoder component =
    let
        baseFields =
            [ ( "name", Encode.string component.name )
            , ( "variants", Encode.list Encode.string component.variants )
            , ( "slots", Encode.list Encode.string component.slots )
            , ( "states", Encode.list Encode.string component.states )
            ]

        allFields =
            case component.description of
                Just desc ->
                    baseFields ++ [ ( "description", Encode.string desc ) ]

                Nothing ->
                    baseFields

        finalFields =
            case component.layout of
                Just l ->
                    allFields ++ [ ( "layout", layoutEncoder l ) ]

                Nothing ->
                    allFields
    in
    Encode.object finalFields
