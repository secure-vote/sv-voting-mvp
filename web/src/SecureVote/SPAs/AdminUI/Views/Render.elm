module SecureVote.SPAs.AdminUI.Views.Render exposing (..)

import Element exposing (Element, column, el, paragraph, row, text)
import Element.Attributes exposing (fill, height, maxWidth, minWidth, padding, paddingBottom, paddingRight, percent, px, spacing, vary, width, xScrollbar)
import Json.Encode exposing (encode)
import SecureVote.Components.UI.Code exposing (codeWScroll)
import SecureVote.Components.UI.CommonStyles exposing (cmnPad)
import SecureVote.SPAs.AdminUI.Model exposing (Model)
import SecureVote.SPAs.AdminUI.Msg exposing (Msg)
import SecureVote.SPAs.AdminUI.Views.Styles exposing (AdminStyles(..), UiElem)


renderScrollable : UiElem -> UiElem
renderScrollable elem =
    paragraph NoS [ width fill, padding 20, paddingRight 20, xScrollbar ] [ elem ]


renderBallotSpec : Model -> UiElem
renderBallotSpec model =
    column BallotPreview
        [ padding 20 ]
        [ el BallotRender [ maxWidth fill ] (text model.jsonBallot) ]


renderBallotHash : Model -> UiElem
renderBallotHash model =
    row BallotHash
        []
        [ renderScrollable <| text model.hash
        ]


renderTxInfo : Model -> UiElem
renderTxInfo model =
    row BallotHash
        [ width fill, padding cmnPad ]
        [ codeWScroll CS model.web3.txInfo ]


renderEventLog : Model -> UiElem
renderEventLog model =
    let
        drawRow str =
            paragraph LogEntry [ paddingBottom 3, xScrollbar ] [ text str ]

        logToDraw =
            if List.isEmpty model.log then
                [ "No log messages yet." ]
            else
                model.log
    in
    column EventLogBox
        [ spacing 10, padding 20 ]
    <|
        List.map
            drawRow
            logToDraw
