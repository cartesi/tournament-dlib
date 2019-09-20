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
        uint256 epochNumber;
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
        uint256 _epochNumber,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        uint256 _timeOfLastMove
    );

    event ChallengeStarted(uint256 _index);
    event MatchFinished(uint256 _index, uint8 _state);

    constructor(address _vgInstantiatorAddress) public {
        vg = VGInterface(_vgInstantiatorAddress);
    }

    /// @notice Instantiate a match.
    /// @param _challenger Player with the lowers alleged score.
    /// @param _claimer Player with the higher alleged score.
    /// @param _epochNumber which epoch this match belong to.
    /// @param _roundDuration Duration of the round.
    /// @param _machineAddress Machine that will run the challenge.
    /// @param _initialHash Initial hash of claimer's machine.
    /// @param _finalHash Alleged final hash of claimer's machine.
    /// @param _finalTime Final time of the claimer's machine.
    /// @return Match index.

    function instantiate(
        address _challenger,
        address _claimer,
        uint256 _epochNumber,
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
        currentInstance.epochNumber = _epochNumber;
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
            _epochNumber,
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
        require(instance[_index].currentState == state.ChallengeStarted, "State is not ChallengeStarted, cannot winByVG");
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
            instance[_index].currentState = state.ClaimerWon;
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

    function stateIsFinishedClaimerWon(uint256 _index) public view
        onlyInstantiated(_index)
        returns (bool)
    { return instance[_index].currentState == state.ClaimerWon; }

    function stateIsFinishedChallengerWon(uint256 _index) public view
        onlyInstantiated(_index)
        returns (bool)
    { return instance[_index].currentState == state.ChallengerWon; }

    function getEpochNumber(uint256 _index) public view returns (uint256) { return instance[_index].epochNumber;}

    function isClaimer(uint256 _index, address addr) public view returns (bool) { return instance[_index].claimer == addr;}

    function isChallenger(uint256 _index, address addr) public view returns (bool) { return instance[_index].challenger == addr;}

    function isConcerned(uint256 _index, address _user) public view returns (bool) {
        return isClaimer(_index, _user) || isChallenger(_index, _user);
    }

    function getState(uint256 _index, address) public view returns
    (   address _challenger,
        address _claimer,
        uint256 _epochNumber,
        uint256 _roundDuration,
        uint256 _timeOfLastMove,
        address _machine,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        bytes32 _currentState
   ) {

        MatchCtx memory i = instance[_index];

        return (
            i.challenger,
            i.claimer,
            i.epochNumber,
            i.roundDuration,
            i.timeOfLastMove,
            i.machine,
            i.initialHash,
            i.finalHash,
            i.finalTime,
            "WaitingClaim"
        );

   }

   function getCurrentState(uint256 _index) public view
        onlyInstantiated(_index)
        returns (bytes32)
    {
        if (instance[_index].currentState == state.WaitingChallenge) {
            return "WaitingChallenge";
        }
        if (instance[_index].currentState == state.ChallengeStarted) {
            return "ChallengeStarted";
        }
        if (instance[_index].currentState == state.ChallengerWon) {
            return "ChallengerWon";
        }
        if (instance[_index].currentState == state.ClaimerWon) {
            return "ClaimerWon";
        }
    }

   function getSubInstances(uint256)
        public view returns (address[] memory, uint256[] memory)
    {
        address[] memory a = new address[](0);
        uint256[] memory i = new uint256[](0);
        return (a, i);
    }

    // TO-DO: Implement clear instance
    function clearInstance(uint256 _index) internal {}
}
