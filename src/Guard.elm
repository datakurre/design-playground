module Guard exposing
    ( Writability(..), Reason(..)
    , writability, writableBranch, readOnly, writable
    , describe, refusal
    , action
    , isMutating
    )

{-| Whether the branch you are on may be edited, and which messages count as
editing.

The app has no backend and no draft state: every save is a commit. That makes
the branch you are on the whole safety model, so this module is the one place
that decides it. Nothing else compares a branch name to `defaultBranch` — before
this existed, six copies of `Maybe.withDefault project.defaultBranch
model.currentBranch` each decided the write target on their own, and the answer
they agreed on was "commit to main".

The rule: **the project's default branch and any GitLab-protected branch are
read-only.** Editing requires cutting a branch first.

@docs Writability, Reason
@docs writability, writableBranch, readOnly, writable
@docs describe, refusal
@docs action
@docs isMutating

-}

import Types exposing (Model, Msg(..))
import Ui


{-| -}
type Writability
    = Writable String
    | ReadOnly Reason


{-| Why editing is refused. Each carries what the user needs to know to fix it,
which is why `DefaultBranch` and `ProtectedBranch` carry the name rather than
leaving the caller to dig it back out of the model.
-}
type Reason
    = NoRepository
    | NoBranch
    | BranchesUnknown String
    | DefaultBranch String
    | ProtectedBranch String


{-| The decision, in order. Each rule is a stronger reason than the ones after
it, which is why they are tried rather than combined.

Rules 3 and 5 both catch the default branch, deliberately. Rule 3 can answer
before `GotBranches` has come back, which is exactly the window in which a deep
link lands you somewhere and a Save button is already on screen; rule 5 catches
a repository whose default branch was renamed out from under the project
record.

Rule 4 is the fail-closed clause and the most important line in the module:
a branch this app cannot positively identify as writable is read-only. That is
the same reasoning `Update.clearProjectState` gives for forgetting state by
default — the safe direction to be wrong in.

-}
writability : Model -> Writability
writability model =
    case ( model.selectedProject, model.currentBranch ) of
        ( Nothing, _ ) ->
            ReadOnly NoRepository

        ( Just _, Nothing ) ->
            ReadOnly NoBranch

        ( Just project, Just name ) ->
            if name == project.defaultBranch then
                ReadOnly (DefaultBranch name)

            else
                case find (\branch -> branch.name == name) (Maybe.withDefault [] model.branches) of
                    Nothing ->
                        ReadOnly (BranchesUnknown name)

                    Just branch ->
                        if branch.default then
                            ReadOnly (DefaultBranch name)

                        else if branch.protected then
                            ReadOnly (ProtectedBranch name)

                        else
                            Writable name


{-| The branch a commit may target, for the write paths in `Update`. `Nothing`
is a refusal, so the tuple match at each write site cannot fall through to a
default branch the way `Maybe.withDefault` used to.
-}
writableBranch : Model -> Maybe String
writableBranch model =
    case writability model of
        Writable name ->
            Just name

        ReadOnly _ ->
            Nothing


{-| The view's question: is this branch read-only, and if so why? `Nothing`
means editable.
-}
readOnly : Model -> Maybe Reason
readOnly model =
    case writability model of
        Writable _ ->
            Nothing

        ReadOnly reason ->
            Just reason


{-| The same question as `readOnly`, for the many controls that only need a
`Bool` to decide between `readonly True` and an editable field.
-}
writable : Model -> Bool
writable model =
    readOnly model == Nothing


{-| What a button on an editor page should do: the message, or a refusal
carrying the reason.

Every write control in the four editors goes through this, so a branch that
`update` would refuse cannot be presented as if it would work. It is the view
half of the same decision `update` makes — the button is the affordance, the
guard in `update` is the guarantee.

-}
action : Model -> msg -> Ui.Action msg
action model msg =
    case readOnly model of
        Nothing ->
            Ui.Do msg

        Just reason ->
            Ui.Blocked (refusal reason)


{-| Banner copy: what is going on, in the second person, on the assumption the
reader can see a branch-creation form directly underneath.
-}
describe : Reason -> String
describe reason =
    case reason of
        NoRepository ->
            "No repository open, so there's nothing to edit yet."

        NoBranch ->
            "No branch selected yet, so editing is off until there is one."

        BranchesUnknown name ->
            "This app couldn't confirm that " ++ name ++ " is safe to write to, so it's read-only for now."

        DefaultBranch name ->
            name ++ " is the default branch and is read-only here. Create a branch to make changes."

        ProtectedBranch name ->
            name ++ " is a protected branch and is read-only here. Create a branch to make changes."


{-| The `commitStatus` line when a mutation is refused. Shorter than `describe`,
because it lands in the app bar's status pill next to whatever the user just
clicked — and it names the remedy, the way the merge-request refusal has done
since before any of this was enforced.
-}
refusal : Reason -> String
refusal reason =
    case reason of
        NoRepository ->
            "Open a repository first"

        NoBranch ->
            "Pick a branch first"

        BranchesUnknown name ->
            "Couldn't confirm " ++ name ++ " is writable — reload, or switch to a branch you created"

        DefaultBranch name ->
            "You're on " ++ name ++ ", the default branch — create a branch, then make your changes on it"

        ProtectedBranch name ->
            "You're on " ++ name ++ ", a protected branch — create a branch, then make your changes on it"


{-| Whether running this message can change anything the repository would later
be asked to store.

`isMutating msg` is `True` iff running it can change the bytes a later save
would write — tokens, themes, components, screens or contracts — or issues a
commit itself. Everything else is `False`: responses coming back from GitLab
(they carry the repository's own state _in_, and blocking those would break
loading), draft fields, filters, selections, and navigation.

Two groups are `False` on purpose and should stay that way:

  - **The escape hatch.** `SwitchBranch`, `UpdateNewBranchName`, `CreateBranch`,
    `UpdateMRTitle`, `CreateMergeRequest`, `Logout` and `UnselectProject` all
    have to keep working from inside the read-only state, or the only way out of
    it is a page reload. `GuardTest` names them individually for that reason.
  - **Draft fields.** The view disables their inputs anyway, and leaving the
    messages live means `Naming.clearFailure` still clears a stale refusal when
    the user starts typing somewhere else.

**Do not collapse the tail of this into `_ -> False`.** The exhaustiveness check
is the whole maintenance story: without it a new `Msg` silently defaults to
"harmless" and the guarantee quietly stops covering it. With it, the compiler
refuses to build until someone has classified the new message. The length is the
price of that, and it is worth paying.

-}
isMutating : Msg -> Bool
isMutating msg =
    case msg of
        -- Shell, auth and project selection
        LinkClicked _ ->
            False

        UrlChanged _ ->
            False

        GotProfile _ ->
            False

        GotTokenResult _ ->
            False

        GotRefreshResult _ ->
            False

        DismissLoadErrors ->
            False

        Logout ->
            False

        FetchProjects ->
            False

        GotProjects _ ->
            False

        LoadMoreProjects ->
            False

        GotMoreProjects _ ->
            False

        UpdateProjectSearch _ ->
            False

        SelectProject _ ->
            False

        UnselectProject ->
            False

        GotProject _ ->
            False

        GotTree _ _ _ ->
            False

        GotCommitResult _ _ ->
            False

        GotSchemaValidationResult _ ->
            False

        -- Tokens and themes
        GotTokensFile _ ->
            False

        GotThemesTree _ _ ->
            False

        GotThemeFile _ _ ->
            False

        SelectTheme _ ->
            False

        UpdateNewThemeName _ ->
            False

        UpdateNewThemeTemplate _ ->
            False

        CreateTheme ->
            True

        UpdateToken _ _ ->
            True

        UpdateCompositeToken _ _ _ ->
            True

        AddCompositeProperty _ _ ->
            True

        DeleteCompositeProperty _ _ ->
            True

        RevertToSingleValue _ ->
            True

        UpdateNewCompositePropertyName _ ->
            False

        UpdateNewCompositePropertyValue _ ->
            False

        SaveTokens ->
            True

        UpdateNewTokenPath _ ->
            False

        UpdateNewTokenType _ ->
            False

        UpdateNewTokenValue _ ->
            False

        CreateToken ->
            True

        ApplyStarterTokenScale ->
            True

        UpdateTokenSearch _ ->
            False

        UpdateTokenTypeFilter _ ->
            False

        ToggleTokenOverriddenOnly ->
            False

        ToggleTokenChangedOnly ->
            False

        ClearTokenFilters ->
            False

        SwitchTab _ ->
            False

        -- Components
        GotComponentsTree _ _ ->
            False

        GotComponentFile _ _ ->
            False

        SelectComponent _ ->
            False

        UpdateNewComponentName _ ->
            False

        UpdateNewComponentTemplate _ ->
            False

        CreateComponent ->
            True

        UpdateNewComponentVariant _ ->
            False

        AddComponentVariant ->
            True

        RemoveComponentVariant _ ->
            True

        UpdateNewComponentSlot _ ->
            False

        AddComponentSlot ->
            True

        RemoveComponentSlot _ ->
            True

        UpdateNewComponentState _ ->
            False

        AddComponentState ->
            True

        RemoveComponentState _ ->
            True

        SaveComponent ->
            True

        -- Component layout
        InitComponentLayout _ ->
            True

        UpdateLayoutProperty _ _ _ ->
            True

        RemoveLayoutProperty _ _ ->
            True

        UpdateLayoutText _ _ ->
            True

        DeleteLayoutNode _ ->
            True

        AddLayoutText _ _ ->
            True

        AddLayoutStack _ ->
            True

        AddLayoutGrid _ ->
            True

        AddLayoutWhen _ ->
            True

        AddLayoutSlot _ ->
            True

        ToggleLayoutNodeIsSlot _ _ ->
            True

        UpdateLayoutWhenCondition _ _ _ ->
            True

        UpdateEditingVariant _ ->
            False

        UpdateEditingState _ ->
            False

        ClearEditingContext ->
            False

        UpdateNewLayoutPropertyName _ ->
            False

        UpdateNewLayoutPropertyValue _ ->
            False

        -- Screens
        GotScreensTree _ _ ->
            False

        GotScreenFile _ _ ->
            False

        SelectScreen _ ->
            False

        UpdateNewScreenName _ ->
            False

        UpdateNewScreenTemplate _ ->
            False

        CreateScreen ->
            True

        SaveScreen ->
            True

        AddComponentToScreen _ ->
            True

        AddScreenToScreen _ ->
            True

        RemoveScreenNode _ ->
            True

        -- Branches and merge requests: the escape hatch, never blocked
        SwitchBranch _ ->
            False

        UpdateNewBranchName _ ->
            False

        CreateBranch ->
            False

        GotCreateBranchResult _ ->
            False

        UpdateMRTitle _ ->
            False

        CreateMergeRequest ->
            False

        -- Deletions
        DeleteToken _ ->
            True

        DeleteTheme _ ->
            True

        DeleteComponent _ ->
            True

        DeleteScreen _ ->
            True

        GotBranches _ ->
            False

        GotMRResult _ ->
            False

        GotMergeRequests _ ->
            False

        -- Export: picking targets is a selection, running the pipeline commits
        ToggleExportTarget _ ->
            False

        RunExportPipeline ->
            True

        -- Usage contracts
        GotContractFile _ _ ->
            False

        UpdateNewContractRuleType _ ->
            False

        UpdateNewContractRuleField _ _ ->
            False

        AddContractRule ->
            True

        RemoveContractRule _ ->
            True

        SaveContract ->
            True

        DeleteContract _ ->
            True

        JumpToComponent _ ->
            False


{-| `List.head << List.filter`, without building the intermediate list. There is
no `List.find` in elm/core.
-}
find : (a -> Bool) -> List a -> Maybe a
find predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just first

            else
                find predicate rest
