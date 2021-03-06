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

/// @title RevealInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "@cartesi/util/contracts/Instantiator.sol";

contract RevealMockInterface is Instantiator {

    enum state {
        CommitPhase,
        RevealPhase,
        MatchManagerPhase,
        TournamentOver
    }

    function instantiate(
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _matchManagerEpochDuration,
        uint256 _matchManagerMatchDuration,
        uint256 _matchManagerRoundDuration,
        uint256 _finalTime,
        bytes32 _initialHash,
        address _machineAddress) public returns (uint256);

    function addFakePlayers(uint256 _index, address[] memory _playerAddresses, uint256[] memory _scores, bytes32[] memory _logHashes, bytes32[] memory _initialHash, bytes32[] memory _finalHashes) public; 

    function getLogHash(uint256 _index, address _playerAddr) public returns (bytes32);
    function getInitialHash(uint256 _index, address _playerAddr) public returns (bytes32);

    function getScore(uint256 _index, address _playerAddr) public returns (uint256);
    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32);
    function playerExist(uint256 _index, address _playerAddr) public returns (bool);
    function getCurrentState(uint256 _index, address concernedAddress) public view returns (bytes32);

}
