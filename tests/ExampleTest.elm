module ExampleTest exposing (..)

import Expect
import Test exposing (..)

suite : Test
suite =
    describe "Example Test Suite"
        [ test "Hello World test" <|
            \_ ->
                Expect.equal "Hello World" "Hello World"
        ]
