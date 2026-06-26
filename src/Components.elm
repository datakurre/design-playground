module Components exposing (Component, decoder, encoder, Layout(..), StackProps, GridProps, ElementProps, layoutDecoder, layoutEncoder)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


type Layout
    = Stack StackProps (List Layout)
    | Grid GridProps (List Layout)
    | Element ElementProps String

type alias StackProps =
    { direction : String
    , padding : Maybe String
    , gap : Maybe String
    , backgroundColor : Maybe String
    }

type alias GridProps =
    { columns : Int
    , gap : Maybe String
    , backgroundColor : Maybe String
    }

type alias ElementProps =
    { isSlot : Bool
    , color : Maybe String
    , typography : Maybe String
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
                            (Decode.map4 StackProps
                                (Decode.field "direction" Decode.string)
                                (Decode.maybe (Decode.field "padding" Decode.string))
                                (Decode.maybe (Decode.field "gap" Decode.string))
                                (Decode.maybe (Decode.field "backgroundColor" Decode.string))
                            )
                            (Decode.field "children" (Decode.list (Decode.lazy (\_ -> layoutDecoder))))

                    "grid" ->
                        Decode.map2 Grid
                            (Decode.map3 GridProps
                                (Decode.field "columns" Decode.int)
                                (Decode.maybe (Decode.field "gap" Decode.string))
                                (Decode.maybe (Decode.field "backgroundColor" Decode.string))
                            )
                            (Decode.field "children" (Decode.list (Decode.lazy (\_ -> layoutDecoder))))

                    "element" ->
                        Decode.map2 Element
                            (Decode.map3 ElementProps
                                (Decode.field "isSlot" Decode.bool)
                                (Decode.maybe (Decode.field "color" Decode.string))
                                (Decode.maybe (Decode.field "typography" Decode.string))
                            )
                            (Decode.field "content" Decode.string)

                    _ ->
                        Decode.fail ("Unknown layout type: " ++ type_)
            )

layoutEncoder : Layout -> Value
layoutEncoder layout =
    case layout of
        Stack props children ->
            Encode.object
                [ ( "type", Encode.string "stack" )
                , ( "direction", Encode.string props.direction )
                , ( "padding", case props.padding of
                                    Just p -> Encode.string p
                                    Nothing -> Encode.null )
                , ( "gap", case props.gap of
                                    Just g -> Encode.string g
                                    Nothing -> Encode.null )
                , ( "backgroundColor", case props.backgroundColor of
                                    Just bg -> Encode.string bg
                                    Nothing -> Encode.null )
                , ( "children", Encode.list layoutEncoder children )
                ]

        Grid props children ->
            Encode.object
                [ ( "type", Encode.string "grid" )
                , ( "columns", Encode.int props.columns )
                , ( "gap", case props.gap of
                                    Just g -> Encode.string g
                                    Nothing -> Encode.null )
                , ( "backgroundColor", case props.backgroundColor of
                                    Just bg -> Encode.string bg
                                    Nothing -> Encode.null )
                , ( "children", Encode.list layoutEncoder children )
                ]

        Element props content ->
            Encode.object
                [ ( "type", Encode.string "element" )
                , ( "isSlot", Encode.bool props.isSlot )
                , ( "color", case props.color of
                                    Just c -> Encode.string c
                                    Nothing -> Encode.null )
                , ( "typography", case props.typography of
                                    Just t -> Encode.string t
                                    Nothing -> Encode.null )
                , ( "content", Encode.string content )
                ]

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
