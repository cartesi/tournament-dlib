/// @title MatchInstantiator
pragma solidity ^0.5.0;

import "./Decorated.sol";
import "./MatchInterface.sol";
import "./VGInterface.sol";

contract MatchInstantiator is MatchInstantiator, Decorated {

    VGInterface private vg;

    struct MachineCtx {
        address challenger;
        address claimer;
        uint256 roundStart; 
        uint256 roundDuration; // time interval to interact with this contract
        address machine; // machine which will run the challenge
        bytes32 initialHash;
        bytes32 finalHash;
        uint256 finalTime;
        uint256 vgInstance; // instance of verification game in case of dispute
        state currentState;
    }

    mapping(uint256 => MachineCtx) internal instance;
   
    constructor(address _vgInstantiatorAddress) public {
        vg = VGInterface(_vgInstantiatorAddress);
    }

    function instantiate(
        address _challenger,
        address _claimer,
        uint256 _roundStart,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime) public returns (uint256)
    {
        require(_challenger != _claimer, "Challenger and Claimer need to differ");
        MatchCtx storage currentInstance = instance[currentIndex];
        currentInstance.challenger = _challenger;
        currentInstance.claimer = _claimer;
        currentInstance.roundDuration = _roundDuration;
        currentInstance.machine = _machineAddress;
        currentInstance.initialHash = _initialHash;
        currentInstance.finalTime = _finalTime;
        currentInstance.timeOfLastMove = now;

        emit MatchCreated(
            currentIndex,
            _challenger,
            _claimer,
            _roundDuration,
            _machineAddress,
            _initialHash,
            _finalTime);

        active[currentIndex] = true;
        return currentIndex++;
    }

}
