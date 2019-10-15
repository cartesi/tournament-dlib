/// @title DappMock
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "./RevealMock.sol";
import ".//Decorated.sol";
import ".//Instantiator.sol";

contract DAppMock is Decorated, Instantiator{

    RevealMock private rm;

    enum state {
        DAppRunning,
        DAppFinished
    }

    struct DAppMockCtx {
        uint256 revealIndex;
        state currentState;
        mapping(address => bool) playersConcern; //player address to isConcerned
    }

    mapping(uint256 => DAppMockCtx) internal instance;

    constructor(
        address _rmAddress,
        address[] memory _playerAddresses,
        uint256[] memory _scores,
        bytes32[] memory _finalHashes
    ) public {
        require(_playerAddresses.length == _scores.length && _scores.length == _finalHashes.length, "Arrays should have the same length");
        instantiate(_rmAddress, _playerAddresses, _scores, _finalHashes);
    }

    function instantiate(
        address _rmAddress,
        address[] memory _playerAddresses,
        uint256[] memory _scores,
        bytes32[] memory _finalHashes
    ) public returns (uint256) {
        // this also instantiate match manager
        rm = RevealMock(_rmAddress);
        instance[currentIndex].revealIndex = rm.instantiate(
            500, //commit duration
            400, //reveal duration
            5000, //epoch duration
            200, //match duration
            13000, // final time
            bytes32("0x00"), //inital hash
            address(0) //machine address
        );

        // add user to concern
        for (uint256 i = 0; i < _playerAddresses.length; i++) {
            instance[currentIndex].playersConcern[_playerAddresses[i]] = true;
        }

        //// also have to add yourself
        rm.addFakePlayers(instance[currentIndex].revealIndex, _playerAddresses, _scores, _finalHashes);

        instance[currentIndex].currentState = state.DAppRunning;
        active[currentIndex] = true;

        return currentIndex++;
    }

    function claimFinished(uint256 _index) public
        onlyInstantiated(_index)
    {
        require(instance[_index].currentState == state.DAppRunning, "The state is already Finished");

        bytes32 mockRevealState = rm.getCurrentState(instance[_index].revealIndex, msg.sender);

        if (mockRevealState == "TournamentOver") {
            instance[currentIndex].currentState = state.DAppFinished;
        } else {
            revert("The subinstance compute is still active");
        }
    }

    function isConcerned(uint256 _index, address _user) public view returns (bool) {
        return instance[_index].playersConcern[_user];
    }

    function getState(uint256 _index, address _user) public view returns (uint256, bytes32) {
        return (instance[_index].revealIndex, getCurrentState(_index, _user));
    }

    function getCurrentState(uint256 _index, address) public view
        onlyInstantiated(_index)
        returns (bytes32)
    {
        if (instance[_index].currentState == state.DAppRunning) {
            return "DAppRunning";
        }
        if (instance[_index].currentState == state.DAppFinished) {
            return "DAppFinished";
        }

        require(false, "Unrecognized state");
    }

    function getSubInstances(uint256 _index, address)
        public view returns (address[] memory _addresses,
            uint256[] memory _indices)
    {
        address[] memory a = new address[](1);
        uint256[] memory i = new uint256[](1);
        a[0] = address(rm);
        i[0] = instance[_index].revealIndex;

        return (a, i);
    }
}

