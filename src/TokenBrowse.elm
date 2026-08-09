module TokenBrowse exposing
    ( Node(..), GroupInfo, tree
    , Filters, Marks, noFilters, filtersActive, apply, matches
    , changedPaths, pathSet
    , groupPaths, properPrefixes, compareNatural
    )

{-| How a large token list is presented for browsing.

Token paths are already hierarchical (`color.brand.500`), but the editor showed
them as one flat list with no way to search. That is fine for the forty-token
starter scale and unusable for a real design system, where the question is
almost always "where is this one token" rather than "show me all of them".

Everything here is pure list arithmetic, so the view stays a rendering function
and the behaviour is unit-testable without a DOM.


# Grouping

@docs Node, GroupInfo, tree


# Filtering

@docs Filters, Marks, noFilters, filtersActive, apply, matches


# Marking tokens

@docs changedPaths, pathSet


# Paths

@docs groupPaths, properPrefixes, compareNatural

-}

import Dict
import Set exposing (Set)
import Tokens



-- GROUPING


{-| One line of the browsable outline: either a token or a heading over more of
them.
-}
type Node
    = Leaf Tokens.FlatToken
    | Group GroupInfo


{-| `label` is what the heading reads — usually one path segment, but a chain of
single-child groups collapses into `color.brand` so the user isn't made to open
two disclosures that always travel together.

`path` is the full prefix, which stays the more specific one through a collapse,
so it can key the node. `count` is the number of tokens beneath, recursively.

-}
type alias GroupInfo =
    { label : String
    , path : List String
    , count : Int
    , children : List Node
    }


{-| Group a flat token list into an outline, splitting on every path segment.

Leaves keep their full path — the row still edits `color.brand.500`, not `500`.

-}
tree : List Tokens.FlatToken -> List Node
tree tokens =
    build [] (List.map (\token -> ( Tuple.first token, token )) tokens)


{-| Each entry pairs the path segments still to be consumed with the whole
token, so recursion can descend without losing what the row needs.
-}
build : List String -> List ( List String, Tokens.FlatToken ) -> List Node
build prefix entries =
    let
        ( here, deeper ) =
            List.partition (\( rest, _ ) -> List.length rest <= 1) entries

        keyedLeaves =
            List.map
                (\( rest, token ) -> ( Maybe.withDefault "" (List.head rest), Leaf token ))
                here

        keyedGroups =
            List.map
                (\( segment, subEntries ) -> ( segment, makeGroup (prefix ++ [ segment ]) segment subEntries ))
                (byHead deeper)
    in
    (keyedLeaves ++ keyedGroups)
        |> List.sortWith (\( a, _ ) ( b, _ ) -> compareNatural a b)
        |> List.map Tuple.second


makeGroup : List String -> String -> List ( List String, Tokens.FlatToken ) -> Node
makeGroup path segment entries =
    let
        children =
            build path (List.map (\( rest, token ) -> ( List.drop 1 rest, token )) entries)
    in
    case children of
        [ Group only ] ->
            -- A group whose whole content is one further group reads as one
            -- heading, not two: `color.brand`, opened once.
            Group { only | label = segment ++ "." ++ only.label }

        _ ->
            Group
                { label = segment
                , path = path
                , count = List.length entries
                , children = children
                }


byHead : List ( List String, Tokens.FlatToken ) -> List ( String, List ( List String, Tokens.FlatToken ) )
byHead entries =
    entries
        |> List.foldr
            (\entry acc ->
                let
                    head =
                        Maybe.withDefault "" (List.head (Tuple.first entry))
                in
                Dict.update head (\existing -> Just (entry :: Maybe.withDefault [] existing)) acc
            )
            Dict.empty
        |> Dict.toList



-- FILTERING


{-| The state of the filter row. `type_` is `""` for "every type".
-}
type alias Filters =
    { search : String
    , type_ : String
    , overriddenOnly : Bool
    , changedOnly : Bool
    }


{-| The two filters that can't be answered from a token alone: which paths the
active theme overrides, and which differ from the last commit. Both are dotted
paths, so a caller can build them from whatever it happens to hold.
-}
type alias Marks =
    { overridden : Set String
    , changed : Set String
    }


{-| -}
noFilters : Filters
noFilters =
    { search = "", type_ = "", overriddenOnly = False, changedOnly = False }


{-| Whether the user has narrowed the list at all. The view switches on this:
unfiltered it shows the collapsible outline, filtered it shows a flat result
list.
-}
filtersActive : Filters -> Bool
filtersActive filters =
    String.trim filters.search /= "" || filters.type_ /= "" || filters.overriddenOnly || filters.changedOnly


{-| -}
apply : Marks -> Filters -> List Tokens.FlatToken -> List Tokens.FlatToken
apply marks filters tokens =
    let
        keep (( path, token ) as flat) =
            matches filters.search flat
                && (filters.type_ == "" || token.type_ == filters.type_)
                && (not filters.overriddenOnly || Set.member (String.join "." path) marks.overridden)
                && (not filters.changedOnly || Set.member (String.join "." path) marks.changed)
    in
    List.filter keep tokens


{-| Case-insensitive search over the dotted path and the value, so `brand`
finds `color.brand.500` and everything aliased to `{color.brand.500}`, and a hex
finds whatever is set to it.
-}
matches : String -> Tokens.FlatToken -> Bool
matches query ( path, token ) =
    let
        needle =
            String.toLower (String.trim query)
    in
    needle
        == ""
        || String.contains needle (String.toLower (String.join "." path ++ " " ++ valueText token.value))


valueText : Tokens.TokenValue -> String
valueText value =
    case value of
        Tokens.StringValue string ->
            string

        Tokens.CompositeValue parts ->
            String.join " " (Dict.values parts)



-- MARKING TOKENS


{-| The paths whose value differs from the last committed list, plus any that
aren't in it at all.

`Pages.GitWorkflows` asks a richer version of this question — it needs the old
and new values to render a diff — and keeps its own `diffTokens` for that. This
is only the membership, which is all a filter needs.

-}
changedPaths : List Tokens.FlatToken -> List Tokens.FlatToken -> Set String
changedPaths original current =
    let
        originalValues =
            Dict.fromList (List.map (\( path, token ) -> ( String.join "." path, token.value )) original)
    in
    current
        |> List.filterMap
            (\( path, token ) ->
                let
                    key =
                        String.join "." path
                in
                if Dict.get key originalValues == Just token.value then
                    Nothing

                else
                    Just key
            )
        |> Set.fromList


{-| The dotted paths of a token list — a theme's overrides, in practice.
-}
pathSet : List Tokens.FlatToken -> Set String
pathSet tokens =
    tokens |> List.map (\( path, _ ) -> String.join "." path) |> Set.fromList



-- PATHS


{-| The unique group prefixes of every token path, e.g. `color.primary.500`
contributes `color` and `color.primary` (but not the full leaf path).

`Pages.TokenStudio` suggests these when naming a new token, and
`Pages.ComponentRegistry` suggests them for the contract rule fields that name a
group rather than a specific token. Both used to carry their own copy.

-}
groupPaths : List Tokens.FlatToken -> List String
groupPaths tokens =
    tokens
        |> List.concatMap (\( path, _ ) -> properPrefixes path)
        |> List.map (String.join ".")
        |> Set.fromList
        |> Set.toList


{-| -}
properPrefixes : List String -> List (List String)
properPrefixes path =
    List.range 1 (List.length path - 1)
        |> List.map (\n -> List.take n path)


{-| Compare two path segments with runs of digits read as numbers, so a ramp
reads 50, 100, 900 rather than 100, 50, 900 — which is the order the flat list
showed, because the token file is a JSON object and its keys sort as strings.
-}
compareNatural : String -> String -> Order
compareNatural a b =
    compareChunks (chunks a) (chunks b)


compareChunks : List String -> List String -> Order
compareChunks xs ys =
    case ( xs, ys ) of
        ( [], [] ) ->
            EQ

        ( [], _ ) ->
            LT

        ( _, [] ) ->
            GT

        ( x :: xRest, y :: yRest ) ->
            case compareChunk x y of
                EQ ->
                    compareChunks xRest yRest

                order ->
                    order


compareChunk : String -> String -> Order
compareChunk x y =
    case ( String.toInt x, String.toInt y ) of
        ( Just nx, Just ny ) ->
            -- Equal numbers can still be different text ("07" vs "7"), and a
            -- sort has to be a total order or `List.sortWith` may drop the tie
            -- somewhere unhelpful.
            case compare nx ny of
                EQ ->
                    compare x y

                order ->
                    order

        _ ->
            case compare (String.toLower x) (String.toLower y) of
                EQ ->
                    compare x y

                order ->
                    order


{-| Split a string into alternating runs of digits and non-digits.
-}
chunks : String -> List String
chunks string =
    string
        |> String.toList
        |> List.foldl
            (\char acc ->
                case acc of
                    [] ->
                        [ String.fromChar char ]

                    current :: rest ->
                        if startsWithDigit current == Char.isDigit char then
                            (current ++ String.fromChar char) :: rest

                        else
                            String.fromChar char :: current :: rest
            )
            []
        |> List.reverse


startsWithDigit : String -> Bool
startsWithDigit string =
    String.uncons string
        |> Maybe.map (Tuple.first >> Char.isDigit)
        |> Maybe.withDefault False
