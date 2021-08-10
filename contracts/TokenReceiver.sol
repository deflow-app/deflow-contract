pragma solidity ^0.8.6;
//SPDX-License-Identifier: MIT

import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenReceiver is Ownable, Pausable {
    using SafeERC20 for IERC20;
    address public flowCallAddress;

    constructor(){

    }

    function setFlowCallAddress(address _flowCallAddress) external onlyOwner{
        flowCallAddress=_flowCallAddress;
    }

    function receiveToken(address sender,uint256 amount,address erc20Token) external whenNotPaused{
        require(msg.sender==flowCallAddress,"TR: invalid caller");
        IERC20(erc20Token).safeTransferFrom(sender,flowCallAddress,amount);
    }
}