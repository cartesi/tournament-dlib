// Copyright (C) 2020 Cartesi Pte. Ltd.

// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.

// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Note: This component currently has dependencies that are licensed under the GNU
// GPL, version 3, and so you should treat this component as a whole as being under
// the GPL version 3. But all Cartesi-written code in this component is licensed
// under the Apache License, version 2, or a compatible permissive license, and can
// be used independently under the Apache v2 license. After this component is
// rewritten, the entire component will be released under the Apache v2 license.

/// @title MatchInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "@cartesi/util/contracts/Decorated.sol";
import "@cartesi/arbitration/contracts/VGInterface.sol";
import "./MatchInterface.sol";

contract MatchInstantiator is MatchInterface, Decorated {

    VGInterface private vg;

    struct MatchCtx {
        address challenger;
        address claimer;
        uint256 epochNumber;
        uint256 matchDuration; // time interval to interact with this contract
        uint256 roundDuration; // time interval to interact with an eventual vg
        uint256 timeOfLastMove;
        address machine; // machine which will run the challenge
        bytes32 logHash; // hash of the log of claimer's move
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
        uint256 _matchDuration,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _logHash,
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
        uint256 _matchDuration,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _logHash,
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
        currentInstance.matchDuration = _matchDuration;
        currentInstance.roundDuration = _roundDuration;
        currentInstance.machine = _machineAddress;
        currentInstance.logHash = _logHash;
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
            _matchDuration,
            _roundDuration,
            _machineAddress,
            _logHash,
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
        onlyAfter(instance[_index].timeOfLastMove + instance[_index].matchDuration)
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

    /// @notice Get the worst case scenario duration for a specific state
    /// @param _roundDuration security parameter, the max time an agent
    //          has to react and submit one simple transaction
    /// @param _timeToDownloadLog time it takes to download the log
    /// @param _timeToStartMachine time to build the machine for the first time
    /// @param _partitionSize size of partition, how many instructions the
    //          will run to reach the necessary hash
    /// @param _maxCycle is the maximum amount of steps a machine can perform
    //          before being forced into becoming halted
    function getMaxStateDuration(
        state _state,
        uint256 _roundDuration,
        uint256 _timeToDownloadLog,
        uint256 _timeToStartMachine,
        uint256 _partitionSize,
        uint256 _maxCycle,
        uint256 _picoSecondsToRunInsn) private view returns (uint256)
    {
        if (_state == state.WaitChallenge) {
            // time to download the log + time to start the machine + time to run it + time to react
            return _timeToDownloadLog + _timeToStartMachine + (_maxCycle * _picoSecondsToRunInsn) / 1e12 + _roundDuration;
        }

        if (_state == state.ChallengeStarted) {
            uint256 partitionInstance;
            (address, partitionInstance) = vg.getSubInstances(instance[_index].vgInstance);

            // TO-DO: 10 as partition size is hardcoded in the VGInstantiator contract, should update this when that change
            return vg.getMaxInstanceDuration(_roundDuration, _timeToStartMachine, 10, _maxCycle, _picoSecondsToRunInsn) + _roundDuration;
        }

        if (_state == state.ClaimerWon || _state == state.ChallengerWon) {
            return 0; // final state
        }
        require(false, "Unrecognized state");
    }

    function getMaxInstanceDuration(
        uint256 _roundDuration,
        uint256 _timeToDownloadLog,
        uint256 _timeToStartMachine,
        uint256 _partitionSize,
        uint256 _maxCycle,
        uint256 _picoSecondsToRunInsn) public view returns (uint256)
    {
        uint256 waitChallengeDuration = getMaxStateDuration(
            state.WaitingQuery,
            _roundDuration,
            _timeToDownloadLog,
            _timeToStartMachine,
            _partitionSize,
            _maxCycle,
            _picoSecondsToRunInsn
        );

        uint256 challengeStartedDuration = getMaxStateDuration(
            state.WaitingHashes,
            _roundDuration,
            _timeToStartMachine,
            _timeToDownloadLog,
            _partitionSize,
            _maxCycle,
            _picoSecondsToRunInsn
        );
        return waitChallengeDuration + challengeStartedDuration;
    }

    function getState(uint256 _index, address) public view returns
    (   address[3] memory _addressValues,
        uint256[4] memory _uintValues,
        bytes32[3] memory _bytesValues,
        bytes32 _currentState
    )
    {

        MatchCtx memory i = instance[_index];

        uint256[4] memory uintValues = [
            i.epochNumber,
            i.matchDuration,
            i.timeOfLastMove,
            i.finalTime
        ];

        address[3] memory addressValues = [
            i.challenger,
            i.claimer,
            i.machine
        ];

        bytes32[3] memory bytesValues = [
            i.logHash,
            i.initialHash,
            i.finalHash
        ];

        return (
            addressValues,
            uintValues,
            bytesValues,
            getCurrentState(_index)
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

   function getSubInstances(uint256 _index, address)
        public view returns (address[] memory, uint256[] memory)
    {
        address[] memory a;
        uint256[] memory i;

        if (instance[_index].currentState == state.ChallengeStarted) {
            a = new address[](1);
            i = new uint256[](1);
            a[0] = address(vg);
            i[0] = instance[_index].vgInstance;
            return (a, i);
        }
        a = new address[](0);
        i = new uint256[](0);
        return (a, i);

    }

    // TO-DO: Clear unuseful information
    function clearInstance(uint256 _index) internal {
        deactivate(_index);
    }
}
