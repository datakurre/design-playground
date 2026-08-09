module Help exposing
    ( Topic
    , forTab
    , tokens, themes, tokenFilters, newToken
    , components, componentLayout, usageContract, componentEditor
    , screens, addComponentToScreen, addScreenToScreen, screenEditor
    , gitWorkflows, branch, unsavedChanges, mergeRequests, contractCheck
    , export
    , all
    )

{-| Short, in-place explanations for each tab and its major forms.

Each topic is a plain value, not a runtime lookup — every call site already
knows which topic it wants at compile time, so there's no `Dict`/`Maybe` layer
to thread through (unlike `Templates`, where the *user* picks at runtime).
`Ui.contextHelp` renders any of these as a collapsed "?" disclosure, and
`Ui.tabLede` renders a tab topic's `lede` as the one line that's always on
screen; see there for the widgets themselves.

Everything here describes what the app actually does today, including where
that's less than you'd expect. A topic that promises an affordance we haven't
built is worse than no topic — it sends people hunting for a control that
isn't there. `HelpTest` guards the handful of promises we've already made and
broken once.

@docs Topic

@docs forTab

@docs tokens, themes, tokenFilters, newToken

@docs components, componentLayout, usageContract, componentEditor

@docs screens, addComponentToScreen, addScreenToScreen, screenEditor

@docs gitWorkflows, branch, unsavedChanges, mergeRequests, contractCheck

@docs export

@docs all

-}

import Types exposing (Tab(..))


{-| `lede` is the one sentence shown without anyone asking for it. Only the
five tab topics have one; a section topic sits behind its "?" glyph, where a
reader has already signalled they want the detail.
-}
type alias Topic =
    { id : String
    , title : String
    , lede : Maybe String
    , body : List String
    }


{-| Every tab's topic. Total by construction: a new `Tab` won't compile until
it has something to say for itself, which is the point — the tab bar is the
one place a user cannot avoid, so it's the one place guidance can't be
optional.
-}
forTab : Tab -> Topic
forTab tab =
    case tab of
        TokenStudio ->
            tokens

        ComponentRegistry ->
            components

        ScreenComposer ->
            screens

        GitWorkflows ->
            gitWorkflows

        ExportPipeline ->
            export


{-| -}
tokens : Topic
tokens =
    { id = "tokens"
    , title = "Design tokens"
    , lede = Just "Start here: tokens are the named colors, spacings and font sizes that everything else is built from."
    , body =
        [ "Tokens are the design values everything else is built from — colors, spacing, font sizes — stored as a flat, named list."
        , "Components and screens refer to them by path, so changing a token here changes every place that uses it."
        ]
    }


{-| -}
themes : Topic
themes =
    { id = "themes"
    , title = "Themes"
    , lede = Nothing
    , body =
        [ "A theme is a set of overrides layered on top of the base tokens, so a dark variant only has to state what differs rather than copy the whole list."
        , "With a theme selected, editing a token changes that theme's override and saves to its own file. Every preview in the app renders through whichever theme is active here."
        , "You can only override tokens that already exist: switch back to the base theme to add a new one."
        ]
    }


{-| -}
tokenFilters : Topic
tokenFilters =
    { id = "token-filters"
    , title = "Finding a token"
    , lede = Nothing
    , body =
        [ "Unfiltered, tokens are grouped by their dotted path: open color to find brand, open brand to find its steps. The number beside a group is how many tokens are under it."
        , "Searching replaces the groups with a flat list of everything that matches, in the path or in the value — so \"brand\" also finds whatever is aliased to {color.brand.500}, and a hex finds whatever is set to it."
        , "\"Overridden only\" appears with a theme selected and narrows to what that theme changes. \"Unsaved changes only\" appears on the base theme and narrows to what differs from the last commit."
        ]
    }


{-| -}
newToken : Topic
newToken =
    { id = "new-token"
    , title = "Add a token"
    , lede = Nothing
    , body =
        [ "Give the token a dot-separated path (like color.brand.500) and a value. Its type is inferred from the value you enter."
        , "This form only appears on the base theme. A theme overrides existing tokens rather than introducing new ones."
        ]
    }


{-| -}
components : Topic
components =
    { id = "components"
    , title = "Components"
    , lede = Just "Bundle tokens into reusable pieces — variants, slots and states with a layout — that screens instantiate by name."
    , body =
        [ "A component bundles variants, slots, and states with an optional layout tree, so it can be instantiated the same way on any screen."
        , "Use \"Start from\" to begin from one of the built-in shapes (Button, Card, Input, Badge, Alert) instead of an empty component."
        ]
    }


{-| -}
componentLayout : Topic
componentLayout =
    { id = "component-layout"
    , title = "Layout"
    , lede = Nothing
    , body =
        [ "The layout tree describes how this component renders: Stack and Grid nodes arrange children, Element nodes render text or a slot."
        , "Slots are placeholders a screen can fill in when it instantiates this component."
        ]
    }


{-| -}
usageContract : Topic
usageContract =
    { id = "usage-contract"
    , title = "Usage contract"
    , lede = Nothing
    , body =
        [ "A usage contract is a set of lint rules — like \"only use tokens from these groups\" or \"meet this contrast ratio\" — checked against the component's resolved tokens."
        , "Violations show up here, on the component list, and again as a gate before merging (Contract check, on the Branches & Reviews tab)."
        ]
    }


{-| -}
componentEditor : Topic
componentEditor =
    { id = "component-editor"
    , title = "Editing a component"
    , lede = Nothing
    , body =
        [ "Changes here apply to variants, slots, states, and the layout tree. Nothing is written to the repository until you save."
        , "The preview below renders this component with the active theme's tokens, the same resolution a screen would use."
        ]
    }


{-| -}
screens : Topic
screens =
    { id = "screens"
    , title = "Screens"
    , lede = Just "Compose components into pages. A component you reference has to already exist under exactly that name."
    , body =
        [ "A screen composes component instances (and other screens) into a page, addressed by its path."
        , "Use \"Start from\" to begin from a Login, Dashboard, or Landing skeleton instead of an empty screen. Those skeletons expect components named Button, Input, Card, Badge and Alert — anything you haven't created yet shows as a red placeholder until you do."
        ]
    }


{-| -}
addComponentToScreen : Topic
addComponentToScreen =
    { id = "add-component-to-screen"
    , title = "Add a component"
    , lede = Nothing
    , body =
        [ "Appends an instance of the chosen component to the end of this screen."
        , "Instances are matched by name, so the component has to already exist under exactly that name — a missing one renders as a red placeholder in the preview."
        ]
    }


{-| -}
addScreenToScreen : Topic
addScreenToScreen =
    { id = "add-screen-to-screen"
    , title = "Add another screen"
    , lede = Nothing
    , body =
        [ "Embeds another screen's tree inside this one, so shared layout (like a page shell) only needs to be built once." ]
    }


{-| -}
screenEditor : Topic
screenEditor =
    { id = "screen-editor"
    , title = "Editing a screen"
    , lede = Nothing
    , body =
        [ "A screen is one container with a list of children. The controls below append to the end of that list — an instance of a component, or another screen embedded whole."
        , "Appending is the only edit available here: children can't yet be moved or taken out again from this page. To undo one, edit the screen's file in Git."
        , "The preview renders the list with the active theme's tokens, resolving every component instance it contains."
        ]
    }


{-| -}
gitWorkflows : Topic
gitWorkflows =
    { id = "git-workflows"
    , title = "Branches & reviews"
    , lede = Just "Every save is a commit. Create a branch here before editing if you don't want changes landing on the default branch."
    , body =
        [ "This app has no backend of its own — every save is a commit, and every change set becomes a Git branch and, eventually, a merge request."
        , "Pick or create a branch below, then commit your staged changes and open a merge request when you're ready for review."
        ]
    }


{-| -}
branch : Topic
branch =
    { id = "branch"
    , title = "Branch"
    , lede = Nothing
    , body =
        [ "Everything you save is a commit on the branch selected here. Switching branches reloads tokens, themes, components, screens and contracts from that branch's files."
        , "Switching discards unsaved edits, so save first — or create a branch, which keeps your edits in the browser so you can save them onto the new branch."
        , "Create a branch before you start editing if you don't want changes landing on the project's default branch directly."
        ]
    }


{-| -}
unsavedChanges : Topic
unsavedChanges =
    { id = "unsaved-changes"
    , title = "Unsaved changes"
    , lede = Nothing
    , body =
        [ "Your edits live in this browser tab until you save. There's no staging step: each Save writes that file and commits it to the current branch in one go."
        , "Nothing here survives a reload, a branch switch, or picking a different repository."
        , "This list covers tokens and components only — screen and contract edits won't appear in it even though they're just as unsaved."
        ]
    }


{-| -}
mergeRequests : Topic
mergeRequests =
    { id = "merge-requests"
    , title = "Merge requests"
    , lede = Nothing
    , body =
        [ "Opens a GitLab merge request from your current branch, so changes go through the same review process as any other code change."
        , "You need to be on a branch other than the project's default one — there's nothing to merge otherwise."
        ]
    }


{-| -}
contractCheck : Topic
contractCheck =
    { id = "contract-check"
    , title = "Contract check"
    , lede = Nothing
    , body =
        [ "Re-runs every component's usage contract against its currently resolved tokens and totals the violations, as a gate before you merge."
        , "This mirrors the per-component check on the Components tab — the two can never disagree, since they share the same validator."
        ]
    }


{-| -}
export : Topic
export =
    { id = "export"
    , title = "Export"
    , lede = Just "Write your tokens out as CSS custom properties or a Tailwind config and commit them to the branch you're on."
    , body =
        [ "Writes your tokens out for other projects to consume: CSS custom properties (exports/variables.css) and a Tailwind config (exports/tailwind.config.js)."
        , "Tokens only — components and screens are not exported. The files are committed to the branch you're working on, like any other save."
        ]
    }


{-| Every topic, in the order pages present them. Exists so a test can lock
the catalog's shape the same way `TemplatesTest` locks `Templates`'.
-}
all : List Topic
all =
    [ tokens
    , themes
    , tokenFilters
    , newToken
    , components
    , componentLayout
    , usageContract
    , componentEditor
    , screens
    , addComponentToScreen
    , addScreenToScreen
    , screenEditor
    , gitWorkflows
    , branch
    , unsavedChanges
    , mergeRequests
    , contractCheck
    , export
    ]
