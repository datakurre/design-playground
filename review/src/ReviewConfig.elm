module ReviewConfig exposing (config)

import Review.Rule exposing (Rule)
import NoUnused.Variables
import NoUnused.Dependencies
import NoMissingTypeAnnotation

config : List Rule
config =
    [ NoUnused.Variables.rule
    , NoUnused.Dependencies.rule
    , NoMissingTypeAnnotation.rule
    ]
