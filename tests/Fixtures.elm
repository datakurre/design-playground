module Fixtures exposing (component, contract, screen, tokens)

{-| One file of each kind, written out exactly as the app writes it.

These exist because the Elm codecs and the JSON Schemas in `schemas/` are two
descriptions of the same file format that nothing compared. `ComponentsTest`
and `ContractsTest` check the codecs against Elm values; `tests/schemas.test.js`
checked the schemas against JavaScript literals; the two suites never met. So
`contracts.schema.json` could type `rules` as a bare array of objects, and a
malformed rule would validate, commit, and then fail to decode on load — where
the failure was swallowed and the contract vanished.

`FixturesTest` asserts that each of these is exactly what the Elm encoder
produces, and `tests/schemas.test.js` reads these same strings out of this file
and validates them against the schemas. An encoder that gains a field breaks the
first; a schema that hasn't kept up breaks the second.

**Keep them exhaustive.** A field that appears in no fixture is a field neither
check covers — which is how `overrides`, `when` nodes and three of the four rule
types went unvalidated in the first place.

Extraction is by triple-quoted string, so the shape below is load-bearing: one
top-level `name : String` per fixture, assigned a `"""…"""` literal.

-}


tokens : String
tokens =
    """{
    "color": {
        "brand": {
            "$description": "The one red",
            "$value": "#ff0000",
            "$type": "color"
        },
        "primary": {
            "$value": "{color.brand}",
            "$type": "color"
        }
    },
    "spacing": {
        "small": {
            "$value": "8px",
            "$type": "dimension"
        }
    },
    "typography": {
        "body": {
            "$value": {
                "fontFamily": "Inter",
                "fontSize": "16px"
            },
            "$type": "typography"
        }
    }
}"""


component : String
component =
    """{
    "name": "Button",
    "variants": [
        "primary",
        "danger"
    ],
    "slots": [
        "label"
    ],
    "states": [
        "hover"
    ],
    "description": "The one button",
    "layout": {
        "type": "stack",
        "direction": "row",
        "styles": {
            "padding": "{spacing.small}"
        },
        "overrides": [
            {
                "variant": "danger",
                "styles": {
                    "background-color": "{color.brand}"
                }
            },
            {
                "state": "hover",
                "styles": {
                    "opacity": "0.9"
                }
            }
        ],
        "children": [
            {
                "type": "grid",
                "columns": 2,
                "styles": {},
                "children": [
                    {
                        "type": "element",
                        "isSlot": true,
                        "styles": {
                            "color": "{color.primary}"
                        },
                        "content": "label"
                    }
                ]
            },
            {
                "type": "when",
                "children": [
                    {
                        "type": "element",
                        "isSlot": false,
                        "styles": {},
                        "content": "!"
                    }
                ],
                "variant": "danger"
            }
        ]
    }
}"""


screen : String
screen =
    """{
    "name": "Home",
    "path": "/",
    "root": {
        "type": "container",
        "direction": "column",
        "styles": {
            "gap": "{spacing.small}"
        },
        "children": [
            {
                "type": "component",
                "componentName": "Button",
                "variant": "primary",
                "state": null,
                "slots": [
                    {
                        "name": "label",
                        "children": [
                            {
                                "type": "text",
                                "content": "Sign in"
                            }
                        ]
                    }
                ]
            },
            {
                "type": "screen",
                "screenName": "Footer"
            }
        ]
    }
}"""


contract : String
contract =
    """{
    "component": "Button",
    "rules": [
        {
            "type": "allowedTokenGroups",
            "groups": [
                "color.brand",
                "spacing"
            ]
        },
        {
            "type": "noHardcodedValues",
            "properties": [
                "color",
                "background-*"
            ]
        },
        {
            "type": "spacingOnScale",
            "properties": [
                "padding",
                "margin"
            ],
            "scale": "spacing"
        },
        {
            "type": "contrastThreshold",
            "foreground": "color",
            "background": "background-color",
            "minimumRatio": 4.5
        }
    ]
}"""
