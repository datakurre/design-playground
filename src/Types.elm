module Types exposing (..)

import Auth
import Browser
import Browser.Navigation as Nav
import Components exposing (Component)
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
    , commitStatus : Maybe String
    , originalTokens : Maybe (List Tokens.FlatToken)
    , tokensFileExists : Bool
    , tokens : Maybe (List Tokens.FlatToken)
    , themes : List Theme
    , existingThemes : List String
    , existingComponents : List String
    , existingScreens : List String
    , activeThemeName : Maybe String
    , newThemeName : String
    , newTokenPath : String
    , newTokenType : String
    , newTokenValue : String
    , activeTab : Tab
    , originalComponents : Maybe (List Component)
    , components : Maybe (List Component)
    , selectedComponentName : Maybe String
    , newComponentName : String
    , newComponentVariant : String
    , newComponentSlot : String
    , newComponentState : String
    , screens : Maybe (List Screen)
    , selectedScreenName : Maybe String
    , newScreenName : String
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
    }


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
    | GotTree (Result Http.Error (List TreeItem))
    | WriteTestFile
    | GotCommitResult (Result Http.Error ())
    | FetchTokens
    | GotTokensFile (Result Http.Error String)
    | GotThemesTree (Result Http.Error (List TreeItem))
    | GotThemeFile String (Result Http.Error String)
    | SelectTheme (Maybe String)
    | UpdateNewThemeName String
    | CreateTheme
    | UpdateToken Tokens.TokenPath String
    | SaveTokens
    | UpdateNewTokenPath String
    | UpdateNewTokenType String
    | UpdateNewTokenValue String
    | CreateToken
    | SwitchTab Tab
    | GotComponentsTree (Result Http.Error (List TreeItem))
    | GotComponentFile String (Result Http.Error String)
    | SelectComponent (Maybe String)
    | UpdateNewComponentName String
    | CreateComponent
    | UpdateNewComponentVariant String
    | AddComponentVariant
    | UpdateNewComponentSlot String
    | AddComponentSlot
    | UpdateNewComponentState String
    | AddComponentState
    | SaveComponent
    | InitComponentLayout
    | UpdateLayoutPadding String
    | UpdateLayoutBackgroundColor String
    | AddLayoutText String
    | GotScreensTree (Result Http.Error (List TreeItem))
    | GotScreenFile String (Result Http.Error String)
    | SelectScreen (Maybe String)
    | UpdateNewScreenName String
    | CreateScreen
    | SaveScreen
    | AddComponentToScreen String
    | SwitchBranch String
    | UpdateNewBranchName String
    | CreateBranch
    | GotCreateBranchResult (Result Http.Error Branch)
    | UpdateMRTitle String
    | CreateMergeRequest
    | GotBranches (Result Http.Error (List Branch))
    | GotMRResult (Result Http.Error MergeRequest)
    | ToggleExportTarget String
    | RunExportPipeline
