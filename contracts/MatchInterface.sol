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

/// @title MatchInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "@cartesi/util/contracts/Instantiator.sol";

contract MatchInterface is Instantiator {

    enum state {
        WaitingChallenge,
        ChallengeStarted,
        ChallengerWon,
        ClaimerWon
    }

    function instantiate(
        address _challenger,
        address _claimer,
        uint256 _epochNumber,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _logHash,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        uint256 _timeOfLastMove) public returns (uint256);

    function getMaxInstanceDuration(
        uint256 _roundDuration,
        uint256 _timeToDownloadLog,
        uint256 _timeToStartMachine,
        uint256 _partitionSize,
        uint256 _maxCycle,
        uint256 _picoSecondsToRunInsn) public view returns (uint256);

    function challengeHighestScore(uint256 _index) public;
    function winByVG(uint256 _index) public;
    function claimVictoryByTime(uint256 _index) public;
    function stateIsFinishedClaimerWon(uint256 _index) public view returns (bool);
    function stateIsFinishedChallengerWon(uint256 _index) public view returns (bool);
    function getEpochNumber(uint256 _index) public view returns (uint256);
    function isClaimer(uint256 _index, address addr) public view returns (bool);
    function isChallenger(uint256 _index, address addr) public view returns (bool);
    function isConcerned(uint256 _index, address _user) public view returns (bool);
    function getState(uint256 _index, address) public view returns
    (   address[3] memory _addressValues,
        uint256[3] memory _uintValues,
        bytes32[3] memory _bytesValues,
        bytes32 _currentState
   );

}

