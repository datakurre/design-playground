module Components exposing (Component, decoder, encoder)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


type alias Component =
    { name : String
    , description : Maybe String
    , variants : List String
    , slots : List String
    , states : List String
    }


decoder : Decoder Component
decoder =
    Decode.map5 Component
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "description" Decode.string))
        (Decode.field "variants" (Decode.list Decode.string))
        (Decode.field "slots" (Decode.list Decode.string))
        (Decode.field "states" (Decode.list Decode.string))


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
                    baseFields ++ [ ( "description", Encode.null ) ]
    in
    Encode.object allFields
