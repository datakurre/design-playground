module Types exposing (..)

import Auth
import Browser
import Components exposing (Component)
import Contracts
import Dict exposing (Dict)
import GitLab.Branches exposing (Branch)
import GitLab.Files exposing (TreeItem)
import GitLab.MergeRequests exposing (MergeRequest)
import GitLab.Projects exposing (Project)
import Http
import Json.Decode
import Screens exposing (Screen)
import Themes exposing (Theme)
import Tokens
import Url exposing (Url)


type StartupStatus
    = Booting
    | Ready


type alias Flags =
    { token : Maybe String
    , pkceChallenge : String
    , pkceVerifier : String
    }


type Tab
    = TokenStudio
    | ComponentRegistry
    | ScreenComposer
    | GitWorkflows
    | ExportPipeline


{-| How a status message should read. This used to be inferred in the view by
comparing the message text to "Success!" and "Writing...", which meant every
other message — "Saving theme...", "Branch created!" — fell through to red and
looked like a failure.
-}
type StatusLevel
    = Working
    | Done
    | Failed


type alias Status =
    ( StatusLevel, String )


type alias Model =
    { url : Url
    , token : Maybe String
    , user : Maybe Auth.User
    , startupStatus : StartupStatus
    , error : Maybe String
    , projects : Maybe (List Project)
    , projectsPage : Int
    , projectSearch : String
    , selectedProject : Maybe Project
    , repositoryTree : Maybe (List TreeItem)
    , commitStatus : Maybe Status
    , originalTokens : Maybe (List Tokens.FlatToken)
    , tokensFileExists : Bool
    , tokens : Maybe (List Tokens.FlatToken)
    , themes : List Theme
    , existingThemes : List String
    , existingComponents : List String
    , existingScreens : List String
    , activeThemeName : Maybe String
    , newThemeName : String
    , newThemeTemplate : String
    , newTokenPath : String
    , newTokenType : String
    , newTokenValue : String

    -- How the token list is narrowed. A real design system runs to hundreds of
    -- tokens, so the list is grouped and searchable rather than flat; see
    -- `TokenBrowse`. `tokenOverriddenOnly` only means anything with a theme
    -- active, and `tokenChangedOnly` only on the base theme, since
    -- `originalTokens` snapshots the base file and nothing else.
    , tokenSearch : String
    , tokenTypeFilter : String
    , tokenOverriddenOnly : Bool
    , tokenChangedOnly : Bool
    , newCompositePropertyName : String
    , newCompositePropertyValue : String
    , activeTab : Tab
    , originalComponents : Maybe (List Component)
    , components : Maybe (List Component)
    , selectedComponentName : Maybe String
    , newComponentName : String
    , newComponentTemplate : String
    , newComponentVariant : String
    , newComponentSlot : String
    , newComponentState : String

    -- Which variant and state the Components tab is looking at. Not a preview
    -- setting: it also decides which style layer an edit to a node lands in, so
    -- that what you are changing and what you are looking at are the same thing.
    -- `Nothing` in either position is the component's base styling.
    , editingVariant : Maybe String
    , editingState : Maybe String
    , newLayoutPropertyName : String
    , newLayoutPropertyValue : String
    , screens : Maybe (List Screen)
    , selectedScreenName : Maybe String
    , newScreenName : String
    , newScreenTemplate : String
    , branches : Maybe (List Branch)
    , currentBranch : Maybe String
    , newBranchName : String
    , mrTitle : String
    , mergeRequests : Maybe (List MergeRequest)
    , exportTargets : List String
    , pkceChallenge : String
    , pkceVerifier : String
    , contracts : Maybe (List Contracts.Contract)
    , existingContracts : List String
    , newContractRuleType : String
    , newContractRuleFields : Dict String String
    , pendingCommit : Maybe PendingCommit
    }


type alias PendingCommit =
    { commitContext : CommitContext
    , actionType : String
    , filePath : String
    , commitMessage : String
    , jsonString : String
    }


{-| The model with nothing open. `Main.init` builds the app from it, and
`Update.clearProjectState` rebuilds from it every time a repository is left,
carrying over the handful of fields that outlive one — see the note there for
why the list runs that way round.
-}
initial : Url -> Flags -> Model
initial url flags =
    { url = url
    , token = flags.token
    , user = Nothing
    , startupStatus = Booting
    , error = Nothing
    , projects = Nothing
    , projectsPage = 1
    , projectSearch = ""
    , selectedProject = Nothing
    , repositoryTree = Nothing
    , commitStatus = Nothing
    , originalTokens = Nothing
    , tokensFileExists = False
    , tokens = Nothing
    , themes = []
    , existingThemes = []
    , existingComponents = []
    , existingScreens = []
    , activeThemeName = Nothing
    , newThemeName = ""
    , newThemeTemplate = "empty"
    , newTokenPath = ""
    , newTokenType = "color"
    , newTokenValue = ""
    , tokenSearch = ""
    , tokenTypeFilter = ""
    , tokenOverriddenOnly = False
    , tokenChangedOnly = False
    , newCompositePropertyName = ""
    , newCompositePropertyValue = ""
    , activeTab = TokenStudio
    , originalComponents = Nothing
    , components = Nothing
    , selectedComponentName = Nothing
    , newComponentName = ""
    , newComponentTemplate = "empty"
    , newComponentVariant = ""
    , newComponentSlot = ""
    , newComponentState = ""
    , editingVariant = Nothing
    , editingState = Nothing
    , newLayoutPropertyName = ""
    , newLayoutPropertyValue = ""
    , screens = Nothing
    , selectedScreenName = Nothing
    , newScreenName = ""
    , newScreenTemplate = "empty"
    , branches = Nothing
    , currentBranch = Nothing
    , newBranchName = ""
    , mrTitle = ""
    , mergeRequests = Nothing
    , exportTargets = [ "css", "tailwind" ]
    , pkceChallenge = flags.pkceChallenge
    , pkceVerifier = flags.pkceVerifier
    , contracts = Nothing
    , existingContracts = []
    , newContractRuleType = "allowedTokenGroups"
    , newContractRuleFields = Dict.empty
    , pendingCommit = Nothing
    }


{-| Which variant and state the Components tab is looking at, in the form
`Components` asks about. Both the editor and `update` need it — the editor to
decide what a style row shows, `update` to decide which layer an edit lands in —
and they have to agree, so there is one of it.
-}
editingContext : Model -> Components.StyleContext
editingContext model =
    { variant = model.editingVariant, state = model.editingState }


type CommitContext
    = CommitTokens
    | CommitTheme String
    | CommitComponent String
    | CommitScreen String
    | CommitDeleteTheme String
    | CommitDeleteComponent String
    | CommitDeleteScreen String
    | CommitContract String
    | CommitDeleteContract String
    | CommitOther


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | GotProfile (Result Http.Error Auth.User)
    | GotTokenResult (Result Http.Error String)
    | Logout
    | FetchProjects
    | GotProjects (Result Http.Error (List Project))
    | LoadMoreProjects
    | GotMoreProjects (Result Http.Error (List Project))
    | UpdateProjectSearch String
    | SelectProject Project
    | UnselectProject
    | GotProject (Result Http.Error Project)
    | GotTree (Result Http.Error (List TreeItem))
    | GotCommitResult CommitContext (Result Http.Error ())
    | GotSchemaValidationResult { valid : Bool, errors : List String, context : Json.Decode.Value }
    | GotTokensFile (Result Http.Error String)
      -- The three tree listings carry the git ref they were listed from, so the
      -- per-file fetches they fan out into read the same branch. They used to
      -- reach for `project.defaultBranch`, which meant switching branches
      -- showed you the default branch's contents under the new branch's name.
    | GotThemesTree String (Result Http.Error (List TreeItem))
    | GotThemeFile String (Result Http.Error String)
    | SelectTheme (Maybe String)
    | UpdateNewThemeName String
    | UpdateNewThemeTemplate String
    | CreateTheme
    | UpdateToken Tokens.TokenPath String
    | UpdateCompositeToken Tokens.TokenPath String String
    | AddCompositeProperty Tokens.TokenPath String
    | DeleteCompositeProperty Tokens.TokenPath String
    | RevertToSingleValue Tokens.TokenPath
    | UpdateNewCompositePropertyName String
    | UpdateNewCompositePropertyValue String
    | SaveTokens
    | UpdateNewTokenPath String
    | UpdateNewTokenType String
    | UpdateNewTokenValue String
    | CreateToken
    | ApplyStarterTokenScale
    | UpdateTokenSearch String
    | UpdateTokenTypeFilter String
    | ToggleTokenOverriddenOnly
    | ToggleTokenChangedOnly
    | ClearTokenFilters
    | SwitchTab Tab
    | GotComponentsTree String (Result Http.Error (List TreeItem))
    | GotComponentFile String (Result Http.Error String)
    | SelectComponent (Maybe String)
    | UpdateNewComponentName String
    | UpdateNewComponentTemplate String
    | CreateComponent
    | UpdateNewComponentVariant String
    | AddComponentVariant
    | RemoveComponentVariant String
    | UpdateNewComponentSlot String
    | AddComponentSlot
    | RemoveComponentSlot String
    | UpdateNewComponentState String
    | AddComponentState
    | RemoveComponentState String
    | SaveComponent
    | InitComponentLayout Components.Layout
    | UpdateLayoutProperty (List Int) String String
    | RemoveLayoutProperty (List Int) String
    | UpdateLayoutText (List Int) String
    | DeleteLayoutNode (List Int)
    | AddLayoutText (List Int) String
    | AddLayoutStack (List Int)
    | AddLayoutGrid (List Int)
    | AddLayoutWhen (List Int)
    | AddLayoutSlot (List Int)
    | ToggleLayoutNodeIsSlot (List Int) Bool
    | UpdateLayoutWhenCondition (List Int) String String
    | UpdateEditingVariant (Maybe String)
    | UpdateEditingState (Maybe String)
    | ClearEditingContext
    | UpdateNewLayoutPropertyName String
    | UpdateNewLayoutPropertyValue String
    | GotScreensTree String (Result Http.Error (List TreeItem))
    | GotScreenFile String (Result Http.Error String)
    | SelectScreen (Maybe String)
    | UpdateNewScreenName String
    | UpdateNewScreenTemplate String
    | CreateScreen
    | SaveScreen
    | AddComponentToScreen String
    | AddScreenToScreen String
    | RemoveScreenNode Int
    | SwitchBranch String
    | UpdateNewBranchName String
    | CreateBranch
    | GotCreateBranchResult (Result Http.Error Branch)
    | UpdateMRTitle String
    | CreateMergeRequest
    | DeleteToken Tokens.TokenPath
    | DeleteTheme String
    | DeleteComponent String
    | DeleteScreen String
    | GotBranches (Result Http.Error (List Branch))
    | GotMRResult (Result Http.Error MergeRequest)
    | GotMergeRequests (Result Http.Error (List MergeRequest))
    | ToggleExportTarget String
    | RunExportPipeline
    | GotContractFile String (Result Http.Error String)
    | UpdateNewContractRuleType String
    | UpdateNewContractRuleField String String
    | AddContractRule
    | RemoveContractRule Int
    | SaveContract
    | DeleteContract String
    | JumpToComponent String
