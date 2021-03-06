module SecureVote.SPAs.SwarmMVP.Web3Handler exposing (..)

import Json.Decode as D exposing (Value, int)
import Json.Decode.Pipeline exposing (decode, required)
import RemoteData exposing (RemoteData(Failure, Success))
import SecureVote.Ballots.Types exposing (BallotSCDetails)
import SecureVote.Eth.Types exposing (..)
import SecureVote.Eth.Web3 exposing (..)
import SecureVote.SPAs.SwarmMVP.Msg exposing (FromWeb3Msg(..), Msg(..))


handleResponse : (RemoteData String a -> FromWeb3Msg) -> Result String a -> Msg
handleResponse msg res =
    case res of
        Ok s ->
            FromWeb3 <| msg <| Success s

        Err err ->
            MultiMsg [ LogErr err, FromWeb3 <| msg <| Failure err ]


readOptsErr : String -> Msg
readOptsErr errMsg =
    MultiMsg [ LogErr errMsg ]


democNVotesSub : Sub Msg
democNVotesSub =
    democNBallots
        (\val ->
            let
                decoder =
                    decode (\democHash n -> { democHash = democHash, n = n })
                        |> required "democHash" D.string
                        |> required "n" D.int
            in
            case D.decodeValue decoder val of
                Ok ballotCount ->
                    FromWeb3 <| GotBallotCount (Success ballotCount)

                Err err ->
                    MultiMsg [ LogErr err, FromWeb3 <| GotBallotCount (Failure err) ]
        )


gotBallotInfoSub : Sub Msg
gotBallotInfoSub =
    gotBallotInfo
        (\val ->
            let
                decoder =
                    decode BallotInfo
                        |> required "democHash" D.string
                        |> required "i" D.int
                        |> required "specHash" D.string
                        |> required "extraData" D.string
                        |> required "votingContract" D.string
                        |> required "startTs" D.int
            in
            handleResponse GotBallotInfo <| D.decodeValue decoder val
        )


gotErc20AbrvHandler : Sub Msg
gotErc20AbrvHandler =
    let
        decoder =
            decode Erc20Abrv
                |> required "erc20Addr" D.string
                |> required "abrv" D.string
                |> required "bHash" D.string
    in
    gotErc20Abrv
        (\v ->
            case D.decodeValue decoder v of
                Ok o ->
                    FromWeb3 <| GotErc20Abrv o

                Err e ->
                    LogErr e
        )


ballotInfoExtraHandler : Sub Msg
ballotInfoExtraHandler =
    let
        decoder =
            decode BallotSCDetails
                |> required "bHash" D.string
                |> required "startingBlockEst" D.int
    in
    ballotInfoExtra
        (\v ->
            case D.decodeValue decoder v of
                Ok deets ->
                    FromWeb3 <| GotBallotSCDeets deets

                Err e ->
                    LogErr e
        )
