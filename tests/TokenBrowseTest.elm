module TokenBrowseTest exposing (..)

import Dict
import Expect
import Set
import Test exposing (..)
import TokenBrowse exposing (Node(..))
import Tokens


tok : String -> String -> Tokens.FlatToken
tok path value =
    ( String.split "." path
    , { value = Tokens.StringValue value, type_ = "color", description = Nothing }
    )


typed : String -> String -> String -> Tokens.FlatToken
typed path type_ value =
    ( String.split "." path
    , { value = Tokens.StringValue value, type_ = type_, description = Nothing }
    )


{-| The shape of a tree, as nested labels, so the assertions read as the
outline the user is meant to see rather than as record literals.
-}
outline : List Node -> List String
outline nodes =
    List.concatMap
        (\node ->
            case node of
                Leaf ( path, _ ) ->
                    [ String.join "." path ]

                Group group ->
                    (group.label ++ " (" ++ String.fromInt group.count ++ ")")
                        :: List.map (\line -> "  " ++ line) (outline group.children)
        )
        nodes


noMarks : TokenBrowse.Marks
noMarks =
    { overridden = Set.empty, changed = Set.empty }


suite : Test
suite =
    describe "TokenBrowse"
        [ describe "tree"
            [ test "an empty list has no nodes" <|
                \_ ->
                    Expect.equal [] (TokenBrowse.tree [])
            , test "single-segment paths stay as leaves" <|
                \_ ->
                    Expect.equal [ "background", "foreground" ]
                        (outline (TokenBrowse.tree [ tok "foreground" "#000", tok "background" "#fff" ]))
            , test "groups by segment, counting the leaves beneath" <|
                \_ ->
                    Expect.equal
                        [ "color (3)"
                        , "  brand (2)"
                        , "    color.brand.50"
                        , "    color.brand.500"
                        , "  gray (1)"
                        , "    color.gray.50"
                        , "spacing (1)"
                        , "  spacing.4"
                        ]
                        (outline
                            (TokenBrowse.tree
                                [ tok "color.brand.500" "#3b82f6"
                                , tok "color.gray.50" "#f8fafc"
                                , tok "color.brand.50" "#eff6ff"
                                , tok "spacing.4" "1rem"
                                ]
                            )
                        )
            , test "a single-child chain collapses into one header" <|
                \_ ->
                    Expect.equal
                        [ "color.brand (2)"
                        , "  color.brand.50"
                        , "  color.brand.500"
                        ]
                        (outline
                            (TokenBrowse.tree
                                [ tok "color.brand.500" "#3b82f6", tok "color.brand.50" "#eff6ff" ]
                            )
                        )
            , test "a path that is both a token and a prefix yields both" <|
                \_ ->
                    Expect.equal
                        [ "color (2)"
                        , "  color.brand"
                        , "  brand (1)"
                        , "    color.brand.500"
                        ]
                        (outline
                            (TokenBrowse.tree
                                [ tok "color.brand" "#3b82f6", tok "color.brand.500" "#3b82f6" ]
                            )
                        )
            , test "leaves keep their full path, not the remaining segments" <|
                \_ ->
                    case TokenBrowse.tree [ tok "color.brand.500" "#3b82f6" ] of
                        [ Group group ] ->
                            Expect.equal [ Leaf (tok "color.brand.500" "#3b82f6") ] group.children

                        other ->
                            Expect.fail ("expected one group, got " ++ String.join ", " (outline other))
            , test "a group carries the full prefix as its path" <|
                \_ ->
                    case TokenBrowse.tree [ tok "color.brand.500" "#1", tok "color.gray.50" "#2" ] of
                        [ Group group ] ->
                            Expect.equal [ "color" ] group.path

                        other ->
                            Expect.fail ("expected one group, got " ++ String.join ", " (outline other))
            ]
        , describe "compareNatural"
            [ test "orders a numeric ramp by value, not by digit" <|
                \_ ->
                    Expect.equal [ "50", "100", "900" ]
                        (List.sortWith TokenBrowse.compareNatural [ "900", "50", "100" ])
            , test "orders spacing steps by value" <|
                \_ ->
                    Expect.equal [ "0", "2", "4", "12" ]
                        (List.sortWith TokenBrowse.compareNatural [ "12", "4", "0", "2" ])
            , test "compares the text around the digits" <|
                \_ ->
                    Expect.equal [ "step2", "step10", "stepA" ]
                        (List.sortWith TokenBrowse.compareNatural [ "stepA", "step10", "step2" ])
            , test "is case-insensitive before falling back to raw order" <|
                \_ ->
                    Expect.equal [ "alpha", "Beta" ]
                        (List.sortWith TokenBrowse.compareNatural [ "Beta", "alpha" ])
            , test "the ramp shows up sorted inside a tree" <|
                \_ ->
                    Expect.equal
                        [ "color.gray (3)"
                        , "  color.gray.50"
                        , "  color.gray.100"
                        , "  color.gray.900"
                        ]
                        (outline
                            (TokenBrowse.tree
                                [ tok "color.gray.100" "#2", tok "color.gray.900" "#3", tok "color.gray.50" "#1" ]
                            )
                        )
            ]
        , describe "matches"
            [ test "an empty query matches everything" <|
                \_ ->
                    Expect.equal True (TokenBrowse.matches "" (tok "color.brand.500" "#3b82f6"))
            , test "matches part of the path, case-insensitively" <|
                \_ ->
                    Expect.equal True (TokenBrowse.matches "BRAND" (tok "color.brand.500" "#3b82f6"))
            , test "matches the value" <|
                \_ ->
                    Expect.equal True (TokenBrowse.matches "3b82f6" (tok "color.brand.500" "#3b82f6"))
            , test "matches inside an alias body" <|
                \_ ->
                    Expect.equal True (TokenBrowse.matches "brand" (tok "color.primary" "{color.brand.500}"))
            , test "matches a composite value's parts" <|
                \_ ->
                    Expect.equal True
                        (TokenBrowse.matches "700"
                            ( [ "typography", "heading" ]
                            , { value = Tokens.CompositeValue (Dict.fromList [ ( "fontWeight", "700" ) ])
                              , type_ = "typography"
                              , description = Nothing
                              }
                            )
                        )
            , test "says no when nothing contains the query" <|
                \_ ->
                    Expect.equal False (TokenBrowse.matches "spacing" (tok "color.brand.500" "#3b82f6"))
            ]
        , describe "filtersActive"
            [ test "is False for no filters" <|
                \_ ->
                    Expect.equal False (TokenBrowse.filtersActive TokenBrowse.noFilters)
            , test "is False for a whitespace-only search" <|
                \_ ->
                    Expect.equal False
                        (TokenBrowse.filtersActive { noFilters | search = "   " })
            , test "is True once a type is chosen" <|
                \_ ->
                    Expect.equal True (TokenBrowse.filtersActive { noFilters | type_ = "color" })
            , test "is True once a checkbox is ticked" <|
                \_ ->
                    Expect.equal True (TokenBrowse.filtersActive { noFilters | changedOnly = True })
            ]
        , describe "apply"
            [ test "no filters keeps every token, in order" <|
                \_ ->
                    Expect.equal sample (TokenBrowse.apply noMarks TokenBrowse.noFilters sample)
            , test "search narrows to matching tokens" <|
                \_ ->
                    Expect.equal [ "color.brand.500" ]
                        (paths (TokenBrowse.apply noMarks { noFilters | search = "brand" } sample))
            , test "type narrows to one type" <|
                \_ ->
                    Expect.equal [ "spacing.4" ]
                        (paths (TokenBrowse.apply noMarks { noFilters | type_ = "dimension" } sample))
            , test "search and type compose" <|
                \_ ->
                    Expect.equal []
                        (paths (TokenBrowse.apply noMarks { noFilters | search = "brand", type_ = "dimension" } sample))
            , test "overriddenOnly keeps the marked paths" <|
                \_ ->
                    Expect.equal [ "color.gray.50" ]
                        (paths
                            (TokenBrowse.apply
                                { noMarks | overridden = Set.fromList [ "color.gray.50" ] }
                                { noFilters | overriddenOnly = True }
                                sample
                            )
                        )
            , test "changedOnly keeps the marked paths" <|
                \_ ->
                    Expect.equal [ "spacing.4" ]
                        (paths
                            (TokenBrowse.apply
                                { noMarks | changed = Set.fromList [ "spacing.4" ] }
                                { noFilters | changedOnly = True }
                                sample
                            )
                        )
            ]
        , describe "changedPaths"
            [ test "an untouched list has changed nothing" <|
                \_ ->
                    Expect.equal Set.empty (TokenBrowse.changedPaths sample sample)
            , test "an edited value is changed" <|
                \_ ->
                    Expect.equal (Set.fromList [ "color.brand.500" ])
                        (TokenBrowse.changedPaths sample
                            [ tok "color.brand.500" "#ff0000", tok "color.gray.50" "#f8fafc", typed "spacing.4" "dimension" "1rem" ]
                        )
            , test "a token that isn't in the original is changed" <|
                \_ ->
                    Expect.equal (Set.fromList [ "color.new" ])
                        (TokenBrowse.changedPaths sample (sample ++ [ tok "color.new" "#fff" ]))
            ]
        , describe "pathSet"
            [ test "is the dotted paths of the tokens" <|
                \_ ->
                    Expect.equal (Set.fromList [ "color.brand.500", "color.gray.50", "spacing.4" ])
                        (TokenBrowse.pathSet sample)
            ]
        , describe "groupPaths"
            [ test "collects proper prefixes only, deduplicated" <|
                \_ ->
                    Expect.equal [ "color", "color.brand", "color.gray", "spacing" ]
                        (TokenBrowse.groupPaths
                            [ tok "color.brand.500" "#1", tok "color.brand.50" "#2", tok "color.gray.50" "#3", tok "spacing.4" "1rem" ]
                        )
            , test "a single-segment path contributes no group" <|
                \_ ->
                    Expect.equal [] (TokenBrowse.groupPaths [ tok "background" "#fff" ])
            ]
        ]


noFilters : TokenBrowse.Filters
noFilters =
    TokenBrowse.noFilters


sample : List Tokens.FlatToken
sample =
    [ tok "color.brand.500" "#3b82f6"
    , tok "color.gray.50" "#f8fafc"
    , typed "spacing.4" "dimension" "1rem"
    ]


paths : List Tokens.FlatToken -> List String
paths tokens =
    List.map (\( p, _ ) -> String.join "." p) tokens
