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

/// @title MatchMangerInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "@cartesi/util/contracts/Decorated.sol";
import "./MatchManagerInterface.sol";
import "./MatchInterface.sol";

// TO-DO: This should be DAppInterface
import "./RevealInterface.sol";

contract MatchManagerInstantiator is MatchManagerInterface, Decorated {

    MatchInterface private mi;

    struct MatchManagerCtx {
        uint256 epochDuration;
        uint256 roundDuration;
        uint256 currentEpoch;
        uint256 finalTime;
        uint256 lastEpochStartTime;
        mapping(uint256 => uint256) numberOfMatchesOnEpoch; // epoch index to number of matches
        address unmatchedPlayer;
        mapping(address => uint256) lastMatchIndex; // player address to index of his last played match
        mapping(address => mapping(uint256 => bool)) registered; // player address to true if he is registered
        address machineAddress;
        address parentAddress;
        uint256 parentInstance;

        state currentState;
    }

    mapping(uint256 => MatchManagerCtx) internal instance;

    constructor(address _miAddress) public {
        mi = MatchInterface(_miAddress);
    }

    /// @notice Instantiate a match manager.
    /// @param _roundDuration duration of a round in seconds.
    /// @param _finalTime final time of matches being played.
    /// @param _parentAddress address of parent parent contract
    /// @param _parentInstance parent instance that this contract is interacting with
    /// @param _machineAddress Machine that will run the challenge.
    /// @return Match Manager index.

    function instantiate(
        uint256 _roundDuration,
        uint256 _finalTime,
        address _parentAddress,
        uint256 _parentInstance,
        address _machineAddress) public returns (uint256)
    {
        MatchManagerCtx storage currentInstance = instance[currentIndex];
        // epochDuration is 2 times the max duration of a match plus round durations for reaction
        // it has to be > 2*match duration, otherwise a player can always register in the end of the epoch and never lose a match
        currentInstance.epochDuration = (mi.getMaxInstanceDuration(
            _roundDuration,
            2400, // 40min to download log
            40,  // 10 seconds to start machine
            10, // querySize = 10, hardcoded on VGInstantiator
            _finalTime,
            500 // pico seconds per instruction
        ) + _roundDuration) * 2;

        currentInstance.roundDuration = _roundDuration;
        currentInstance.finalTime = _finalTime;
        currentInstance.machineAddress = _machineAddress;
        currentInstance.parentAddress = _parentAddress;
        currentInstance.parentInstance = _parentInstance;
        currentInstance.unmatchedPlayer = address(0);
        currentInstance.currentEpoch = 0;
        currentInstance.lastEpochStartTime = now;

        currentInstance.currentState = state.WaitingMatches;
        active[currentIndex] = true;

        return currentIndex++;
    }

    /// @notice Advances Epoch if the deadline has been met
    /// @param _index index of matchmanager that youre interacting with
    function advanceEpoch(uint256 _index) public {
        if (now > (instance[_index].lastEpochStartTime + instance[_index].epochDuration)) {
            instance[_index].currentEpoch++;
            instance[_index].lastEpochStartTime = now;
        }
    }

    /// @notice Register for the next Epoch, only doable if you won a match on last one
    /// @param _index index of matchmanager that youre interacting with
    function playNextEpoch(uint256 _index) public {
        require(instance[_index].currentState == state.WaitingMatches, "State has to be WaitingMatches");
        // Advance epoch if deadline has been met
        if (now > (instance[_index].lastEpochStartTime + instance[_index].epochDuration)) {
            instance[_index].currentEpoch++;
            instance[_index].lastEpochStartTime = now;
        }

        // if it is first Epoch:
        // check if player completed the Reveal phase
        // check if player has already registered
        if (instance[_index].currentEpoch == 0) {
            RevealInterface parent = RevealInterface(instance[_index].parentAddress);
            require(!instance[_index].registered[msg.sender][instance[_index].currentEpoch], "Player cannot register twice");
            require(parent.hasRevealed(instance[_index].parentInstance, msg.sender), "Player must have completed parent phase");

            instance[_index].registered[msg.sender][instance[_index].currentEpoch] = true;

        } else {
            uint256 matchIndex = instance[_index].lastMatchIndex[msg.sender];
            require (msg.sender != instance[_index].unmatchedPlayer, "Player is waiting for a opponent");
            require (
                mi.getEpochNumber(matchIndex) + 1 == instance[_index].currentEpoch,
                "Last match played by player has to be compatible with current currentEpoch"
            );

            // TO-DO: find a decent way to format this
            // require player to have won last match
            require (
                (mi.stateIsFinishedChallengerWon(matchIndex) && mi.isChallenger(matchIndex, msg.sender)) ||
                (mi.stateIsFinishedClaimerWon(matchIndex) && mi.isClaimer(matchIndex, msg.sender)),
                "Player must have won last match played"
             );
        }

        if (instance[_index].unmatchedPlayer != address(0)) {
           // there is one unmatched player ready for a match
           createMatch(_index);

           // clears unmatched player
           instance[_index].unmatchedPlayer = address(0);

        } else {
            instance[_index].unmatchedPlayer = msg.sender;
        }

    }

    /// @notice Creates a match with two players
    /// @param _index index of matchmanager that youre interacting with
    function createMatch(uint256 _index) private {

        MatchManagerCtx memory i = instance[_index];
        address[3] memory addressValues;   //claimer
                                            // challenger
                                            // unmatchedAddr
        addressValues[2] = i.unmatchedPlayer;

        RevealInterface parent = RevealInterface(instance[_index].parentAddress);

        // the highest score between both is the claimer, the lowest is the challenger
        if (parent.getScore(i.parentInstance, msg.sender) > parent.getScore(i.parentInstance, addressValues[2])) {
            addressValues[0] = msg.sender;
            addressValues[1] = addressValues[2];
        } else {
            addressValues[1] = msg.sender;
            addressValues[0] = addressValues[2];
        }

        // instantiate new match
        uint256 newMatchIndex = mi.instantiate(
            addressValues[1],
            addressValues[0],
            i.currentEpoch,
            i.roundDuration,
            i.machineAddress,
            parent.getLogHash(i.parentInstance, addressValues[0]),
            parent.getInitialHash(i.parentInstance, addressValues[0]),
            parent.getFinalHash(i.parentInstance, addressValues[0]),
            i.finalTime,
            now
        );

        // add match to both players mapping
        instance[_index].lastMatchIndex[addressValues[1]] = newMatchIndex;
        instance[_index].lastMatchIndex[addressValues[0]] = newMatchIndex;

        // increase matches on epoch counter
        instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch]++;

    }

    /// @notice Claims win on the entire tournament. Only callable if you were unchallenged for an entire epoch
    /// @param _index index of matchmanager that youre interacting with

    function claimWin(uint256 _index) public returns (address) {
        require(instance[_index].currentState != state.MatchesOver, "PLayer cannot claim win multiple times");
        bool isEpochOver = (now > (instance[_index].lastEpochStartTime + instance[_index].epochDuration));
        if (isEpochOver && (instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch] == 0)) {
            instance[_index].currentState = state.MatchesOver;

            deactivate(_index);
            return instance[_index].unmatchedPlayer;
        }
    }

    function getWinner(uint256 _index) public view returns(address) {
        require(instance[_index].currentState == state.MatchesOver, "Matches have to be over");

        return instance[_index].unmatchedPlayer;
    }

    // TO-DO: Remove player from this if he lost. PlayNextEpoch should remove the loser.
    // doing this will make this func stopping being view
    // TO-DO: this function will probably not exist
    function isConcerned(uint256, address) public view returns (bool) {
        return true;
    }

    function getState(uint256 _index, address _user) public view returns
        ( uint256[9] memory _uintValues,
          address[3] memory _addressValues,
          bool registered,
          bytes32 currentState
        ) {

            MatchManagerCtx memory i = instance[_index];
            uint256[9] memory uintValues = [
                i.epochDuration,
                i.roundDuration,
                i.currentEpoch,
                i.finalTime,
                i.lastEpochStartTime,
                instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch - 1],
                instance[_index].lastMatchIndex[_user],
                i.parentInstance,
                mi.getEpochNumber(instance[_index].lastMatchIndex[_user])

            ];

            address[3] memory addressValues = [
                i.unmatchedPlayer,
                i.machineAddress,
                i.parentAddress
            ];

            return (
                uintValues,
                addressValues,
                instance[_index].registered[_user][i.currentEpoch],
                getCurrentState(_index)
            );
        }

        function getSubInstances(uint256 _index, address _user)
            public view returns (address[] memory _addresses,
                uint256[] memory _indices)
        {
            address[] memory a;
            uint256[] memory i;

            if (instance[_index].currentEpoch == 0 && (instance[_index].unmatchedPlayer == _user || !instance[_index].registered[_user][0])) {
                a = new address[](0);
                i = new uint256[](0);
                return (a, i);

            }
            a = new address[](1);
            i = new uint256[](1);
            a[0] = address(mi);
            i[0] = instance[_index].lastMatchIndex[_user];
            return (a, i);

        }

        function getCurrentState(uint256 _index) public view
            onlyInstantiated(_index)
            returns (bytes32)
        {
            if (instance[_index].currentState == state.WaitingMatches) {
                return "WaitingMatches";
            }
            if (instance[_index].currentState == state.MatchesOver) {
                return "MatchesOver";
            }

            require(false, "Unrecognized state");
        }
}

