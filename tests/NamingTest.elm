module NamingTest exposing (suite)

import Expect
import Naming
import Test exposing (Test, describe, test)
import Types exposing (StatusLevel(..))


suite : Test
suite =
    describe "Naming"
        [ describe "check"
            [ test "accepts a fresh name" <|
                \_ ->
                    Expect.equal (Ok "Button") (Naming.check "Button" [ "Card" ])
            , test "trims before accepting, so the name that gets stored is the trimmed one" <|
                \_ ->
                    Expect.equal (Ok "Button") (Naming.check "  Button  " [])
            , test "rejects an empty name" <|
                \_ ->
                    Expect.equal (Err Naming.Blank) (Naming.check "" [])
            , test "rejects a whitespace-only name" <|
                \_ ->
                    Expect.equal (Err Naming.Blank) (Naming.check "   " [])
            , test "rejects a name already taken" <|
                \_ ->
                    Expect.equal (Err (Naming.Duplicate "Card")) (Naming.check "Card" [ "Button", "Card" ])
            , test "rejects a name that only collides once trimmed" <|
                \_ ->
                    Expect.equal (Err (Naming.Duplicate "Card")) (Naming.check " Card " [ "Card" ])
            , test "is case-sensitive, matching how the files are named" <|
                \_ ->
                    Expect.equal (Ok "card") (Naming.check "card" [ "Card" ])
            ]

        -- These are user-facing copy, so lock them verbatim: a silent reword is
        -- the same class of regression as the help text that described a tree
        -- editor the app never had.
        , describe "describe"
            [ test "blank, with an example" <|
                \_ ->
                    Expect.equal "Give the component a name, like Button"
                        (Naming.describe "component" "Button" Naming.Blank)
            , test "blank, with no example to offer" <|
                \_ ->
                    Expect.equal "Give the theme a name"
                        (Naming.describe "theme" "" Naming.Blank)
            , test "duplicate names the collision" <|
                \_ ->
                    Expect.equal "There's already a component called Button"
                        (Naming.describe "component" "Button" (Naming.Duplicate "Button"))
            , test "duplicate ignores the example" <|
                \_ ->
                    Expect.equal "There's already a token called color.brand.500"
                        (Naming.describe "token" "color.gray.100" (Naming.Duplicate "color.brand.500"))
            ]
        , describe "clearFailure"
            [ test "drops a failure, so it doesn't outlive the input that caused it" <|
                \_ ->
                    Expect.equal Nothing (Naming.clearFailure (Just ( Failed, "Give the token a name" )))
            , test "keeps work in progress" <|
                \_ ->
                    Expect.equal (Just ( Working, "Saving..." ))
                        (Naming.clearFailure (Just ( Working, "Saving..." )))
            , test "keeps a success, which the user still wants to see" <|
                \_ ->
                    Expect.equal (Just ( Done, "Branch created" ))
                        (Naming.clearFailure (Just ( Done, "Branch created" )))
            , test "leaves an empty status alone" <|
                \_ ->
                    Expect.equal Nothing (Naming.clearFailure Nothing)
            ]
        ]
