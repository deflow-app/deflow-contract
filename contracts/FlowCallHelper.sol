pragma solidity >=0.4.22 <0.9.0;

import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";

contract FlowCallHelper is Ownable, Pausable {
    address payable manager;

    constructor() {
        manager = payable(msg.sender);
    }

    function kill() external onlyOwner {
        selfdestruct(manager);
    }

    function setManager(address payable mgr) external onlyOwner{
        manager = mgr;
    }

    function getETHBalance(address targetAddress) view public returns (uint) {
        return address(targetAddress).balance;
    }

    fallback () payable external {}
    receive () payable external {}
}