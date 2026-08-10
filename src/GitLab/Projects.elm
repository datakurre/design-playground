module GitLab.Projects exposing (Project, getProject, listProjects, projectDecoder)

import GitLab.Request exposing (Body(..), Request)
import Http
import Json.Decode as Decode exposing (Decoder)
import Url


type alias Project =
    { id : Int
    , name : String
    , pathWithNamespace : String
    , defaultBranch : String
    }


projectDecoder : Decoder Project
projectDecoder =
    Decode.map4 Project
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "path_with_namespace" Decode.string)
        (Decode.field "default_branch" Decode.string)


listProjects : String -> Int -> (Result Http.Error (List Project) -> msg) -> Request msg
listProjects token page toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects?membership=true&order_by=id&sort=desc&per_page=20&page=" ++ String.fromInt page
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg (Decode.list projectDecoder)
    }


{-| GitLab takes a project's path in place of its id, provided the whole thing —
slashes and all — arrives as one percent-encoded path segment.
-}
getProject : String -> String -> (Result Http.Error Project -> msg) -> Request msg
getProject token pathWithNamespace toMsg =
    { method = "GET"
    , url = "https://gitlab.com/api/v4/projects/" ++ Url.percentEncode pathWithNamespace
    , headers = GitLab.Request.authorized token
    , body = EmptyBody
    , expect = Http.expectJson toMsg projectDecoder
    }
