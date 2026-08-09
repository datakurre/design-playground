module Route exposing (Route(..), TabRoute(..), parse, toString)

import Url exposing (Url)


type Route
    = Home
    | Repo String TabRoute


type TabRoute
    = TokensTab
    | ComponentsTab (Maybe String)
    | ScreensTab (Maybe String)
    | GitWorkflowsTab
    | ExportPipelineTab


parse : Url -> Maybe Route
parse url =
    let
        segments =
            url.path
                |> String.split "/"
                |> List.filter (\s -> not (String.isEmpty s))
    in
    case List.reverse segments of
        [] ->
            Just Home

        "export" :: rest ->
            Just (Repo (String.join "/" (List.reverse rest)) ExportPipelineTab)

        "branches" :: rest ->
            Just (Repo (String.join "/" (List.reverse rest)) GitWorkflowsTab)

        component :: "components" :: rest ->
            Just (Repo (String.join "/" (List.reverse rest)) (ComponentsTab (Just component)))

        "components" :: rest ->
            Just (Repo (String.join "/" (List.reverse rest)) (ComponentsTab Nothing))

        screen :: "screens" :: rest ->
            Just (Repo (String.join "/" (List.reverse rest)) (ScreensTab (Just screen)))

        "screens" :: rest ->
            Just (Repo (String.join "/" (List.reverse rest)) (ScreensTab Nothing))

        "tokens" :: rest ->
            Just (Repo (String.join "/" (List.reverse rest)) TokensTab)

        -- Fallback: if they just go to /owner/repo, default to tokens
        _ ->
            if List.length segments > 0 then
                Just (Repo (String.join "/" segments) TokensTab)

            else
                Just Home


toString : Route -> String
toString route =
    case route of
        Home ->
            "/"

        Repo path tab ->
            let
                base =
                    "/" ++ path
            in
            case tab of
                TokensTab ->
                    base ++ "/tokens"

                ComponentsTab Nothing ->
                    base ++ "/components"

                ComponentsTab (Just comp) ->
                    base ++ "/components/" ++ comp

                ScreensTab Nothing ->
                    base ++ "/screens"

                ScreensTab (Just scr) ->
                    base ++ "/screens/" ++ scr

                GitWorkflowsTab ->
                    base ++ "/branches"

                ExportPipelineTab ->
                    base ++ "/export"
