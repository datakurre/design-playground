module Types exposing (..)

import Auth
import Browser
import Browser.Navigation as Nav
import Components exposing (Component)
import Contracts
import Dict exposing (Dict)
import GitLab.Branches exposing (Branch)
import GitLab.Commits
import GitLab.Files exposing (TreeItem)
import GitLab.MergeRequests exposing (MergeRequest)
import GitLab.Projects exposing (Project)
import Http
import Screens exposing (Screen)
import Themes exposing (Theme)
import Tokens
import Url exposing (Url)


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
    { key : Nav.Key
    , url : Url
    , token : Maybe String
    , user : Maybe Auth.User
    , error : Maybe String
    , projects : Maybe (List Project)
    , projectsPage : Int
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
    , newLayoutPropertyName : String
    , newLayoutPropertyValue : String
    , screens : Maybe (List Screen)
    , selectedScreenName : Maybe String
    , newScreenName : String
    , newScreenTemplate : String
    , branches : Maybe (List Branch)
    , currentBranch : Maybe String
    , newBranchName : String
    , commitMessage : String
    , stagedActions : List GitLab.Commits.Action
    , mrTitle : String
    , mergeRequests : Maybe (List MergeRequest)
    , exportTargets : List String
    , pkceChallenge : String
    , pkceVerifier : String
    , contracts : Maybe (List Contracts.Contract)
    , existingContracts : List String
    , newContractRuleType : String
    , newContractRuleFields : Dict String String
    }


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
    | SelectProject Project
    | UnselectProject
    | GotTree (Result Http.Error (List TreeItem))
    | GotCommitResult CommitContext (Result Http.Error ())
    | FetchTokens
    | GotTokensFile (Result Http.Error String)
    | GotThemesTree (Result Http.Error (List TreeItem))
    | GotThemeFile String (Result Http.Error String)
    | SelectTheme (Maybe String)
    | UpdateNewThemeName String
    | UpdateNewThemeTemplate String
    | CreateTheme
    | UpdateToken Tokens.TokenPath String
    | UpdateCompositeToken Tokens.TokenPath String String
    | AddCompositeProperty Tokens.TokenPath String
    | DeleteCompositeProperty Tokens.TokenPath String
    | UpdateNewCompositePropertyName String
    | UpdateNewCompositePropertyValue String
    | SaveTokens
    | UpdateNewTokenPath String
    | UpdateNewTokenType String
    | UpdateNewTokenValue String
    | CreateToken
    | ApplyStarterTokenScale
    | SwitchTab Tab
    | GotComponentsTree (Result Http.Error (List TreeItem))
    | GotComponentFile String (Result Http.Error String)
    | SelectComponent (Maybe String)
    | UpdateNewComponentName String
    | UpdateNewComponentTemplate String
    | CreateComponent
    | UpdateNewComponentVariant String
    | AddComponentVariant
    | UpdateNewComponentSlot String
    | AddComponentSlot
    | UpdateNewComponentState String
    | AddComponentState
    | SaveComponent
    | InitComponentLayout
    | UpdateLayoutProperty (List Int) String String
    | RemoveLayoutProperty (List Int) String
    | UpdateLayoutText (List Int) String
    | DeleteLayoutNode (List Int)
    | AddLayoutText (List Int) String
    | AddLayoutStack (List Int)
    | AddLayoutGrid (List Int)
    | UpdateNewLayoutPropertyName String
    | UpdateNewLayoutPropertyValue String
    | GotScreensTree (Result Http.Error (List TreeItem))
    | GotScreenFile String (Result Http.Error String)
    | SelectScreen (Maybe String)
    | UpdateNewScreenName String
    | UpdateNewScreenTemplate String
    | CreateScreen
    | SaveScreen
    | AddComponentToScreen String
    | AddScreenToScreen String
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
