module Help exposing
    ( Topic
    , tokens, newToken
    , components, componentLayout, usageContract, componentEditor
    , screens, addComponentToScreen, addScreenToScreen, screenEditor
    , gitWorkflows, branch, mergeRequests, contractCheck
    , export
    , all
    )

{-| Short, in-place explanations for each tab and its major forms.

Each topic is a plain value, not a runtime lookup — every call site already
knows which topic it wants at compile time, so there's no `Dict`/`Maybe` layer
to thread through (unlike `Templates`, where the *user* picks at runtime).
`Ui.contextHelp` renders any of these as a collapsed "?" disclosure; see there
for the widget itself.

@docs Topic

@docs tokens, newToken

@docs components, componentLayout, usageContract, componentEditor

@docs screens, addComponentToScreen, addScreenToScreen, screenEditor

@docs gitWorkflows, branch, mergeRequests, contractCheck

@docs export

@docs all

-}


{-| -}
type alias Topic =
    { id : String
    , title : String
    , body : List String
    }


{-| -}
tokens : Topic
tokens =
    { id = "tokens"
    , title = "Design tokens"
    , body =
        [ "Tokens are the design values everything else is built from — colors, spacing, font sizes — stored as a flat, named list."
        , "Switch to a theme above to layer overrides on top of the base tokens instead of duplicating them."
        ]
    }


{-| -}
newToken : Topic
newToken =
    { id = "new-token"
    , title = "Add a token"
    , body =
        [ "Give the token a dot-separated path (like color.brand.500) and a value. Its type is inferred from the value you enter."
        , "If a theme is active, this adds an override instead of a new base token — the base token must already exist."
        ]
    }


{-| -}
components : Topic
components =
    { id = "components"
    , title = "Components"
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
    , body =
        [ "A screen composes component instances (and other screens) into a page, addressed by its path."
        , "Use \"Start from\" to begin from a Login, Dashboard, or Landing skeleton instead of an empty screen."
        ]
    }


{-| -}
addComponentToScreen : Topic
addComponentToScreen =
    { id = "add-component-to-screen"
    , title = "Add a component"
    , body =
        [ "Appends an instance of the chosen component to the top level of this screen. Rearranging or nesting happens in the tree below." ]
    }


{-| -}
addScreenToScreen : Topic
addScreenToScreen =
    { id = "add-screen-to-screen"
    , title = "Add another screen"
    , body =
        [ "Embeds another screen's tree inside this one, so shared layout (like a page shell) only needs to be built once." ]
    }


{-| -}
screenEditor : Topic
screenEditor =
    { id = "screen-editor"
    , title = "Editing a screen"
    , body =
        [ "The tree below is this screen's root container and its children. Add components or nested screens with the controls beneath it."
        , "The preview renders the tree with the active theme's tokens, resolving every component instance it contains."
        ]
    }


{-| -}
gitWorkflows : Topic
gitWorkflows =
    { id = "git-workflows"
    , title = "Branches & reviews"
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
    , body =
        [ "Switching branches reloads tokens, components, screens, and contracts from that branch's files."
        , "Create a new branch before making changes you don't want to land on the default branch directly."
        ]
    }


{-| -}
mergeRequests : Topic
mergeRequests =
    { id = "merge-requests"
    , title = "Merge requests"
    , body =
        [ "Opens a GitLab merge request from your current branch, so changes go through the same review process as any other code change." ]
    }


{-| -}
contractCheck : Topic
contractCheck =
    { id = "contract-check"
    , title = "Contract check"
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
    , body =
        [ "Generates tokens (and, depending on the target, components) in a format other projects can consume — CSS custom properties or a Tailwind config."
        , "This is for downstream consumers; it doesn't affect what's committed to this repository."
        ]
    }


{-| Every topic, in the order pages present them. Exists so a test can lock
the catalog's shape the same way `TemplatesTest` locks `Templates`'.
-}
all : List Topic
all =
    [ tokens
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
    , mergeRequests
    , contractCheck
    , export
    ]
