module GitLab.Projects exposing (Project, getProject, listProjects, projectDecoder)

import Http
import Json.Decode as Decode exposing (Decoder)


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


listProjects : String -> Int -> (Result Http.Error (List Project) -> msg) -> Cmd msg
listProjects token page toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/projects?membership=true&order_by=id&sort=desc&per_page=20&page=" ++ String.fromInt page
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (Decode.list projectDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


getProject : String -> String -> (Result Http.Error Project -> msg) -> Cmd msg
getProject token pathWithNamespace toMsg =
    let
        encodedPath =
            pathWithNamespace
                |> String.replace "/" "%2F"
    in
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/projects/" ++ encodedPath
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg projectDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
