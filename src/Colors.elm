module Colors exposing (Rgb, contrastRatio, parseHex)


type alias Rgb =
    { r : Int, g : Int, b : Int }


parseHex : String -> Maybe Rgb
parseHex input =
    let
        trimmed =
            String.trim input

        withoutHash =
            if String.startsWith "#" trimmed then
                String.dropLeft 1 trimmed

            else
                trimmed

        isHexChar c =
            Char.isHexDigit c

        allHex =
            String.all isHexChar withoutHash

        len =
            String.length withoutHash
    in
    if not allHex then
        Nothing

    else if len == 3 then
        let
            c1 =
                String.slice 0 1 withoutHash

            c2 =
                String.slice 1 2 withoutHash

            c3 =
                String.slice 2 3 withoutHash

            expanded =
                c1 ++ c1 ++ c2 ++ c2 ++ c3 ++ c3
        in
        parse6 expanded

    else if len == 6 then
        parse6 withoutHash

    else
        Nothing


parse6 : String -> Maybe Rgb
parse6 hexStr =
    let
        rStr =
            String.slice 0 2 hexStr

        gStr =
            String.slice 2 4 hexStr

        bStr =
            String.slice 4 6 hexStr
    in
    Maybe.map3 Rgb
        (hexToInt rStr)
        (hexToInt gStr)
        (hexToInt bStr)


hexToInt : String -> Maybe Int
hexToInt hexStr =
    -- Elm doesn't have a built-in hex-to-int without Regex or Bitwise trickery that is always safe,
    -- but we can write a simple folder.
    let
        charToInt c =
            let
                code =
                    Char.toCode (Char.toLower c)
            in
            if code >= 48 && code <= 57 then
                code - 48

            else if code >= 97 && code <= 102 then
                code - 97 + 10

            else
                0

        -- should be prevented by allHex check
    in
    Just (String.foldl (\c acc -> acc * 16 + charToInt c) 0 hexStr)


luminance : Rgb -> Float
luminance { r, g, b } =
    let
        normalize c =
            let
                cs =
                    toFloat c / 255.0
            in
            if cs <= 0.03928 then
                cs / 12.92

            else
                ((cs + 0.055) / 1.055) ^ 2.4

        nr =
            normalize r

        ng =
            normalize g

        nb =
            normalize b
    in
    0.2126 * nr + 0.7152 * ng + 0.0722 * nb


contrastRatio : Rgb -> Rgb -> Float
contrastRatio c1 c2 =
    let
        l1 =
            luminance c1

        l2 =
            luminance c2

        maxL =
            max l1 l2

        minL =
            min l1 l2
    in
    (maxL + 0.05) / (minL + 0.05)
