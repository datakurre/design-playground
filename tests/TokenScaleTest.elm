module TokenScaleTest exposing (..)

import Dict
import Expect
import Set
import Test exposing (..)
import TokenScale exposing (mergeStarterScale, seed)
import Tokens exposing (TokenValue(..))


suite : Test
suite =
    describe "TokenScale"
        [ test "seed has 40 tokens" <|
            \_ ->
                Expect.equal 40 (List.length seed)
        , test "seed has no duplicate paths" <|
            \_ ->
                let
                    paths =
                        List.map Tuple.first seed

                    uniquePaths =
                        Set.fromList paths
                in
                Expect.equal (List.length paths) (Set.size uniquePaths)
        , test "anchor points exist" <|
            \_ ->
                let
                    dict =
                        Dict.fromList seed

                    getVal path d =
                        Dict.get path d
                            |> Maybe.map
                                (\t ->
                                    case t.value of
                                        StringValue v ->
                                            v

                                        _ ->
                                            ""
                                )
                in
                Expect.all
                    [ \d -> Expect.equal (Just "#f9fafb") (getVal [ "color", "gray", "50" ] d)
                    , \d -> Expect.equal (Just "#111827") (getVal [ "color", "gray", "900" ] d)
                    , \d -> Expect.equal (Just "#3b82f6") (getVal [ "color", "brand", "500" ] d)
                    , \d -> Expect.equal (Just "0rem") (getVal [ "spacing", "0" ] d)
                    , \d -> Expect.equal (Just "3rem") (getVal [ "spacing", "12" ] d)
                    , \d -> Expect.equal (Just "1rem") (getVal [ "fontSize", "base" ] d)
                    , \d -> Expect.equal (Just "1.875rem") (getVal [ "fontSize", "3xl" ] d)
                    ]
                    dict
        , test "format consistency" <|
            \_ ->
                let
                    isConsistent ( path, token ) =
                        case token.value of
                            StringValue v ->
                                if List.head path == Just "color" then
                                    String.startsWith "#" v && String.length v == 7

                                else
                                    String.endsWith "rem" v

                            _ ->
                                False
                in
                Expect.equal True (List.all isConsistent seed)
        , test "merging into empty list yields the seed" <|
            \_ ->
                let
                    sorted mergeRes =
                        List.sortBy (\( p, _ ) -> String.join "." p) mergeRes
                in
                Expect.equal (sorted seed) (sorted (mergeStarterScale []))
        , test "non-destructive merge retains existing tokens on collision" <|
            \_ ->
                let
                    existingToken =
                        ( [ "color", "gray", "500" ]
                        , { value = StringValue "#custom"
                          , type_ = "color"
                          , description = Nothing
                          }
                        )

                    merged =
                        mergeStarterScale [ existingToken ]

                    dict =
                        Dict.fromList merged
                in
                Expect.equal
                    (Just (StringValue "#custom"))
                    (Dict.get [ "color", "gray", "500" ] dict |> Maybe.map .value)
        , test "unrelated existing tokens pass through untouched" <|
            \_ ->
                let
                    existingToken =
                        ( [ "color", "special" ]
                        , { value = StringValue "#123456"
                          , type_ = "color"
                          , description = Nothing
                          }
                        )

                    merged =
                        mergeStarterScale [ existingToken ]

                    dict =
                        Dict.fromList merged
                in
                Expect.equal
                    (Just (StringValue "#123456"))
                    (Dict.get [ "color", "special" ] dict |> Maybe.map .value)
        ]
