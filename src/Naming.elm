module Naming exposing (Problem(..), check, clearFailure, describe)

{-| The one place that decides whether a name the user typed can be used.

Every "Add" form in the app used to answer this inline with a bare
`if name /= "" && not (List.any ...)` whose else-branch was `( model, Cmd.none )`.
Seven forms that did nothing, silently, and never said why — the single worst
thing the app did for a first-time user. Pulling the decision out here gets it
under test (`Model` carries a `Nav.Key`, so nothing in `update` can be), and
leaves each `Msg` branch as two lines of glue.

@docs Problem, check, clearFailure, describe

-}

import Types exposing (Status, StatusLevel(..))


{-| -}
type Problem
    = Blank
    | Duplicate String


{-| Returns the trimmed name on success, so callers store what was validated
rather than the raw field value.
-}
check : String -> List String -> Result Problem String
check raw existing =
    let
        trimmed =
            String.trim raw
    in
    if trimmed == "" then
        Err Blank

    else if List.member trimmed existing then
        Err (Duplicate trimmed)

    else
        Ok trimmed


{-| `noun` is the singular thing being named — "token", "component", "screen",
"theme", "branch". `hint` is an example to offer when the field is empty, or
`""` when there isn't a useful one.
-}
describe : String -> String -> Problem -> String
describe noun hint problem =
    case problem of
        Blank ->
            if hint == "" then
                "Give the " ++ noun ++ " a name"

            else
                "Give the " ++ noun ++ " a name, like " ++ hint

        Duplicate name ->
            "There's already a " ++ noun ++ " called " ++ name


{-| Clears a validation failure once the user edits the field it complained
about. Successes and in-progress messages stay — those aren't the user's to
dismiss by typing.
-}
clearFailure : Maybe Status -> Maybe Status
clearFailure status =
    case status of
        Just ( Failed, _ ) ->
            Nothing

        other ->
            other
