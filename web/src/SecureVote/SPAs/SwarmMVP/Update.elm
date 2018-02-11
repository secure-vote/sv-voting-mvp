module SecureVote.SPAs.SwarmMVP.Update exposing (..)

import Dict
import Dom.Scroll exposing (toTop)
import Material
import Material.Helpers as MHelp exposing (map1st, map2nd)
import Material.Snackbar as Snackbar
import Maybe.Extra exposing ((?))
import RemoteData exposing (RemoteData(Failure, Loading, NotAsked, Success))
import SecureVote.Crypto.Curve25519 exposing (encryptBytes)
import SecureVote.Eth.Types exposing (AuditDoc)
import SecureVote.Eth.Web3 exposing (..)
import SecureVote.SPAs.SwarmMVP.Ballot exposing (doBallotOptsMatch)
import SecureVote.SPAs.SwarmMVP.Ballots.ReleaseSchedule exposing (doBallotOptsMatchRSched, voteOptionsRSched)
import SecureVote.SPAs.SwarmMVP.Helpers exposing (ballotValToBytes, defaultDelegate, getDelegateAddress, getUserErc20Addr)
import SecureVote.SPAs.SwarmMVP.Model exposing (LastPageDirection(PageBack, PageForward), Model, resetAllBallotFields)
import SecureVote.SPAs.SwarmMVP.Msg exposing (FromCurve25519Msg(..), FromWeb3Msg(..), Msg(..), ToCurve25519Msg(..), ToWeb3Msg(..))
import SecureVote.SPAs.SwarmMVP.Routes exposing (defaultRoute)
import SecureVote.SPAs.SwarmMVP.Types exposing (TxidCheckStatus(TxidFail, TxidInProgress, TxidSuccess))
import SecureVote.SPAs.SwarmMVP.VotingCrypto.RangeVoting exposing (constructBallot, orderedBallotBits)
import Task exposing (attempt)


scrollToTop : String -> Cmd Msg
scrollToTop id =
    attempt (\_ -> NoOp) (toTop id)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            model ! []

        SetTime time ->
            { model | now = time } ! []

        SetElevation id isOn ->
            { model | elevations = Dict.insert id isOn model.elevations } ! []

        SetField fieldName value ->
            { model | fields = Dict.insert fieldName value model.fields } ! []

        PageGoForward route ->
            { model | route = route, history = model.route :: model.history, lastPageDirection = PageForward, lastRoute = Nothing } ! [ scrollToTop "sv-main" ]

        PageGoBack ->
            { model
                | route = List.head model.history ? defaultRoute
                , history = List.tail model.history ? []
                , lastPageDirection = PageBack
                , lastRoute = Just model.route
            }
                ! [ scrollToTop "sv-main" ]

        SetDialog title route ->
            { model | dialogHtml = { title = title, route = route } } ! [ scrollToTop "dialog-container" ]

        SetBallotRange id value ->
            let
                val =
                    round value
            in
            { model
                | ballotRange = Dict.insert id val model.ballotRange
                , ballotBits = Dict.insert id (ballotValToBytes val) model.ballotBits
            }
                ! []

        SetBallot b ->
            let
                ( m_, cmds_ ) =
                    update (ToWeb3 ReInit) <| resetAllBallotFields { model | currentBallot = b } b

                doAuditIfBallotEnded =
                    if b.endTime < model.now then
                        [ getBallotResults { ethUrl = model.ethNode, ethRPCAuth = "", votingAddr = b.contractAddr, erc20Addr = b.erc20Addr } ]
                    else
                        []
            in
            m_ ! ([ cmds_ ] ++ doAuditIfBallotEnded)

        ConstructBallotPlaintext ->
            let
                plainBytesM =
                    orderedBallotBits model model.ballotBits
                        |> Maybe.andThen
                            (flip constructBallot <|
                                getDelegateAddress model
                                    ? defaultDelegate
                            )

                skM =
                    Maybe.map .hexSk model.keypair

                remotePkM =
                    model.remoteHexPk

                encCmds =
                    case ( skM, remotePkM, plainBytesM ) of
                        ( Just sk, Just pk, Just bs ) ->
                            [ encryptBytes { hexSk = sk, hexRemotePk = pk, bytesToSign = bs } ]

                        _ ->
                            []
            in
            { model | ballotPlaintext = plainBytesM } ! encCmds

        MultiMsg msgs ->
            multiUpdate msgs model []

        SetCandidateTx f ->
            { model | candidateTx = f model.candidateTx } ! []

        SetEthNode addr ->
            { model | ethNode = addr } ! []

        -- Errors
        LogErr err ->
            addSnack err model

        Snackbar msg_ ->
            Snackbar.update msg_ model.snack
                |> map1st (\s -> { model | snack = s })
                |> map2nd (Cmd.map Snackbar)

        -- PORTS
        ToWeb3 msg ->
            updateToWeb3 msg model

        FromWeb3 msg ->
            updateFromWeb3 msg model

        FromCurve25519 msg ->
            updateFromCurve25519 msg model

        FromAuditor msg ->
            { model | auditMsgs = msg :: model.auditMsgs } ! []

        -- ToCurve25519 msg ->
        --     updateToCurve25519 msg model
        -- Boilerplate: Mdl action handler.
        Mdl msg_ ->
            Material.update Mdl msg_ model


addSnack : String -> Model -> ( Model, Cmd Msg )
addSnack err model =
    let
        ( snackbar_, effect ) =
            Snackbar.add (Snackbar.toast "some payload" err) model.snack
                |> map2nd (Cmd.map Snackbar)

        model_ =
            { model | snack = snackbar_, errors = err :: model.errors }
    in
    ( model_, Cmd.batch [ effect ] )


multiUpdate : List Msg -> Model -> List (Cmd Msg) -> ( Model, Cmd Msg )
multiUpdate msgs model cmds =
    case msgs of
        msg :: msgs_ ->
            let
                ( model_, cmd ) =
                    update msg model

                cmds_ =
                    cmds ++ [ cmd ]
            in
            multiUpdate msgs_ model_ cmds_

        [] ->
            ( model, Cmd.batch cmds )


updateToWeb3 : ToWeb3Msg -> Model -> ( Model, Cmd Msg )
updateToWeb3 web3msg model =
    case web3msg of
        SetProvider ->
            model ! [ setWeb3Provider model.ethNode, getEncryptionPublicKey model.currentBallot.contractAddr ]

        GetErc20Balance ->
            let
                addr =
                    -- probs okay because it will return 0
                    getUserErc20Addr model ? "0x00"
            in
            model ! [ getErc20Balance <| GetErc20BalanceReq model.currentBallot.erc20Addr addr ]

        CheckTxid txid ->
            { model | txidCheck = TxidInProgress } ! [ checkTxid txid ]

        ReInit ->
            model ! [ getInit model.currentBallot.contractAddr, getEncryptionPublicKey model.currentBallot.contractAddr ]


updateFromWeb3 : FromWeb3Msg -> Model -> ( Model, Cmd Msg )
updateFromWeb3 msg model =
    case msg of
        GotBalance bal ->
            let
                cBallot =
                    model.currentBallot
            in
            { model | currentBallot = { cBallot | erc20Balance = Just bal } } ! []

        GotDataParam data ->
            let
                candTx =
                    model.candidateTx
            in
            { model | ballotAllDone = True, candidateTx = { candTx | data = Just data } } ! []

        GotEncPubkey encPk ->
            { model | remoteHexPk = Just encPk } ! []

        Web3Init init ->
            { model | miniVotingAbi = init.miniAbi } ! []

        GetBallotOptsLegacy resp ->
            case resp of
                Success opts ->
                    let
                        optCheck =
                            model.currentBallot.voteOptions == voteOptionsRSched && doBallotOptsMatchRSched opts
                    in
                    ballotOptSuccess model optCheck

                _ ->
                    ballotOptElse model resp

        GetBallotOpts resp ->
            case resp of
                Success opts ->
                    ballotOptSuccess model (doBallotOptsMatch model.currentBallot.voteOptions opts)

                _ ->
                    ballotOptElse model resp

        GetBallotPeriod resp ->
            { model | ballotOpen = resp } ! []

        GotTxidStatus txidE ->
            case txidE of
                Ok { data, confirmed, gas, logMsg } ->
                    if confirmed then
                        -- gas should be around 100,000 for a successful vote
                        if gas < 75000 then
                            let
                                errMsg =
                                    "Warning! "
                                        ++ (if String.length logMsg > 0 then
                                                "Voting contract returned error: " ++ logMsg
                                            else
                                                "Gas seems low, vote likely failed to be recorded. Check ethereum transaction log & manual verification; unable to find an error message."
                                           )
                            in
                            { model | txidCheck = TxidFail errMsg } ! []
                        else if Just data == model.candidateTx.data then
                            { model | txidCheck = TxidSuccess } ! []
                        else
                            { model | txidCheck = TxidFail "Warning! Data mismatch!" } ! []
                    else
                        { model | txidCheck = TxidFail "Transaction not yet confirmed" } ! []

                Err msg ->
                    { model | txidCheck = TxidFail msg } ! []


updateFromCurve25519 : FromCurve25519Msg -> Model -> ( Model, Cmd Msg )
updateFromCurve25519 msg model =
    case msg of
        GotKey kp ->
            { model | keypair = Just kp } ! []

        GotEncBytes bs ->
            let
                model_ =
                    { model | encBytes = Just bs }
            in
            case ( model_.encBytes, model_.keypair, model_.candidateTx.to ) of
                ( Just encBytes, Just keypair, Just voteCAddr ) ->
                    model_ ! [ constructDataParam { encBallot = encBytes, voterPubkey = keypair.hexPk, votingContractAddr = voteCAddr } ]

                _ ->
                    update (LogErr "Unable to create Ethereum tx data parameter - missing encrypted ballot, keypair, or voting contract address.") model_



-- updateToCurve25519 : ToCurve25519Msg -> Model -> ( Model, Cmd Msg )
-- updateToCurve25519 msg model =
--     case msg of
--         GenerateSignedBallot ->
--             case ( model.ballotPlaintext, model.keypair, model.remoteHexPk ) of
--                 ( Just bytes, Just keypair, Just hexRemotePk ) ->
--                     model ! [ encryptBytes { bytesToSign = bytes, hexSk = keypair.hexSk, hexRemotePk = hexRemotePk } ]
--                 _ ->
--                     update (LogErr "App does not have all of: ballot plaintext, keypair, and encryption public key. Unable to generate encrypted ballot.") model


mFail : Model -> String -> Model
mFail model errMsg =
    { model
        | ballotVerificationPassed = Failure errMsg
    }


ballotOptSuccess : Model -> Bool -> ( Model, Cmd Msg )
ballotOptSuccess model b =
    if b then
        { model | ballotVerificationPassed = Success True } ! []
    else
        mFail model "Release schedule options in voting front end do not match smart contract!" ! []


ballotOptElse : Model -> RemoteData String a -> ( Model, Cmd Msg )
ballotOptElse model resp =
    case resp of
        Success _ ->
            mFail model "Response from Web3 successful but not handled by correct function. This error should never happen." ! []

        Failure errMsg ->
            mFail model errMsg ! []

        Loading ->
            { model | ballotVerificationPassed = Loading } ! []

        NotAsked ->
            { model | ballotVerificationPassed = NotAsked } ! []
