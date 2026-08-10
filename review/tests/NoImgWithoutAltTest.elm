module NoImgWithoutAltTest exposing (all)

import NoImgWithoutAlt exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "NoImgWithoutAlt"
        [ test "reports an img with no alt" <|
            \() ->
                """module A exposing (..)
import Html exposing (img)
import Html.Attributes exposing (src)

view = img [ src "logo.png" ] []
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Html.img is missing an alt attribute"
                            , details =
                                [ "Every image needs alt text, even if it's empty for a purely decorative image (Html.Attributes.alt \"\"). Without it, a screen reader has nothing to announce for this image."
                                ]
                            , under = "img [ src \"logo.png\" ] []"
                            }
                        ]
        , test "does not report an img with alt" <|
            \() ->
                """module A exposing (..)
import Html exposing (img)
import Html.Attributes exposing (alt, src)

view = img [ src "logo.png", alt "Company logo" ] []
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "does not report an img with an empty alt for a decorative image" <|
            \() ->
                """module A exposing (..)
import Html exposing (img)
import Html.Attributes exposing (alt, src)

view = img [ src "divider.png", alt "" ] []
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        ]
