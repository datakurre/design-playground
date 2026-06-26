module GitLab.Projects exposing (Project, listProjects, projectDecoder)

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


listProjects : String -> (Result Http.Error (List Project) -> msg) -> Cmd msg
listProjects token toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://gitlab.com/api/v4/projects?membership=true&simple=true&order_by=updated_at"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (Decode.list projectDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }
