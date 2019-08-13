/// @title MatchInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Decorated.sol";
import "../../arbitration-dlib/contracts/VGInterface.sol";
import "./MatchInterface.sol";

contract MatchInstantiator is MatchInterface, Decorated {

    VGInterface private vg;

    struct MatchCtx {
        address challenger;
        address claimer;
        uint256 roundStart;
        uint256 roundDuration; // time interval to interact with this contract
        uint256 timeOfLastMove;
        address machine; // machine which will run the challenge
        bytes32 initialHash;
        bytes32 finalHash;
        uint256 finalTime;
        uint256 vgInstance; // instance of verification game in case of dispute
        state currentState;
    }

    mapping(uint256 => MatchCtx) internal instance;

    event MatchCreated(
        uint256 _index,
        address _challenger,
        address _claimer,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        uint256 _timeOfLastMove
    );

    event ClaimChallenged(uint256 _index);
    event ClaimDefended(uint256 _index);
    event ChallengeStarted(uint256 _index);
    event MatchFinished(uint256 _index, uint8 _state);

    constructor(address _vgInstantiatorAddress) public {
        vg = VGInterface(_vgInstantiatorAddress);
    }

    /// @notice Instantiate a match.
    /// @param _challenger Player with the lowers alleged score.
    /// @param _claimer Player with the higher alleged score.
    /// @param _roundStart Time in which this round started.
    /// @param _roundDuration Duration of the round.
    /// @param _machineAddress Machine that will run the challenge.
    /// @param _initialHash Initial hash of claimer's machine.
    /// @param _finalHash Alleged final hash of claimer's machine.
    /// @param _finalTime Final time of the claimer's machine.
    /// @return Match index.

    function instantiate(
        address _challenger,
        address _claimer,
        uint256 _roundStart,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        uint256 _timeOfLastMove) public returns (uint256)
    {
        require(_challenger != _claimer, "Challenger and Claimer need to differ");
        MatchCtx storage currentInstance = instance[currentIndex];
        currentInstance.challenger = _challenger;
        currentInstance.claimer = _claimer;
        currentInstance.roundDuration = _roundDuration;
        currentInstance.machine = _machineAddress;
        currentInstance.initialHash = _initialHash;
        currentInstance.finalHash = _finalHash;
        currentInstance.finalTime = _finalTime;
        currentInstance.timeOfLastMove = now;

        currentInstance.currentState = state.WaitingChallenge;

        emit MatchCreated(
            currentIndex,
            _challenger,
            _claimer,
            _roundDuration,
            _machineAddress,
            _initialHash,
            _finalHash,
            _finalTime,
            _timeOfLastMove);

        active[currentIndex] = true;
        return currentIndex++;
    }

    /// @notice Challenger can dispute claimer's highscore.
    /// @param _index Current index.
    function challengeHighestScore(uint256 _index) public
        onlyBy(instance[_index].challenger)
        onlyInstantiated(_index)
        increasesNonce(_index)
    {
        require(instance[_index].currentState == state.WaitingChallenge, "State has to be Waiting Challenge");

        // TO-DO: this should become a modifier on Decorated lib.
        require(now < (instance[_index].timeOfLastMove + instance[_index].roundDuration), "Challenger cannot challenge after the round duration window");

        instance[_index].currentState = state.WaitingClaimerDefence;
        emit ClaimChallenged(_index);
    }

    /// @notice Defender can defend his highscore by verification game.
    /// @param _index Current index.
    function defendHighestScore(uint256 _index) public
        onlyBy(instance[_index].claimer)
        onlyInstantiated(_index)
        increasesNonce(_index)
    {
        // TO-DO: this should become a modifier on Decorated lib.
        require(now < (instance[_index].timeOfLastMove + instance[_index].roundDuration), "Claimer cannot defend himself after the round duration window");
        require(instance[_index].currentState == state.WaitingClaimerDefence, "State has to be WaitingClaimerDefence");

        // If claimer defends himself, a Verification Game starts
        instance[_index].vgInstance = vg.instantiate(
            instance[_index].challenger,
            instance[_index].claimer,
            instance[_index].roundDuration,
            instance[_index].machine,
            instance[_index].initialHash,
            instance[_index].finalHash,
            instance[_index].finalTime
        );

        instance[_index].currentState = state.ChallengeStarted;
        emit ChallengeStarted(_index);

    }

    /// @notice In case one of the parties wins the verification game,
    /// then he or she can call this function to claim victory in
    /// this contract as well.
    /// @param _index Current index.
    function winByVG(uint256 _index) public
        onlyInstantiated(_index)
        increasesNonce(_index)
    {
        require(instance[_index].currentState == state.ChallengeStarted, "State is not WaitingChallenge, cannot winByVG");
        uint256 vgIndex = instance[_index].vgInstance;

        if (vg.stateIsFinishedChallengerWon(vgIndex)) {
            challengerWins(_index);
            return;
        }

        if (vg.stateIsFinishedClaimerWon(vgIndex)) {
            claimerWins(_index);
            return;
        }
        require(false, "State of VG is not final");
    }

    /// @notice Claim victory for opponent timeout.
    /// @param _index Current index.
    function claimVictoryByTime(uint256 _index) public
        onlyInstantiated(_index)
        onlyAfter(instance[_index].timeOfLastMove + instance[_index].roundDuration)
        increasesNonce(_index)
    {
        if ((msg.sender == instance[_index].claimer) && (instance[_index].currentState == state.WaitingChallenge)) {
            instance[_index].currentState = state.ChallengerMissedDeadline;
            deactivate(_index);
            emit MatchFinished(_index, uint8(instance[_index].currentState));
            return;
        }
        if ((msg.sender == instance[_index].challenger) && (instance[_index].currentState == state.WaitingClaimerDefence)) {
            instance[_index].currentState = state.ChallengerMissedDeadline;
            deactivate(_index);
            emit MatchFinished(_index, uint8(instance[_index].currentState));
            return;
        }
        revert("Fail to ClaimVictoryByTime in current condition");
    }

    function challengerWins(uint256 _index) private
        onlyInstantiated(_index)
    {
        clearInstance(_index);
        instance[_index].currentState = state.ChallengerWon;
        emit MatchFinished(_index, uint8(instance[_index].currentState));
    }

    function claimerWins(uint256 _index) private
        onlyInstantiated(_index)
    {
        clearInstance(_index);
        instance[_index].currentState = state.ClaimerWon;
        emit MatchFinished(_index, uint8(instance[_index].currentState));
    }

    // TO-DO: Implement clear instance
    function clearInstance(uint256 _index) internal {}
}
