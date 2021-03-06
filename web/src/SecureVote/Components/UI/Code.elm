module SecureVote.Components.UI.Code exposing (..)

import Element exposing (Element, html, paragraph)
import Element.Attributes exposing (xScrollbar)
import Html as Html
import SecureVote.Components.UI.CommonStyles exposing (..)


codeWScroll : (CommonStyle -> s) -> String -> Element s o v
codeWScroll sWrap txt =
    paragraph (sWrap CodeStyle) [ xScrollbar ] [ html <| Html.pre [] [ Html.text txt ] ]


codesWScroll : (CommonStyle -> s) -> List String -> Element s o v
codesWScroll sWrap codes =
    paragraph (sWrap CodeStyle) [ xScrollbar ] [ html <| Html.pre [] <| List.map Html.text codes ]
