
pragma solidity ^0.8.6;
//SPDX-License-Identifier: MIT
interface ITokenReceiver{
     function receiveToken(address sender,uint256 amount,address erc20Token) external;
}