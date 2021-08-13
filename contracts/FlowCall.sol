pragma solidity ^0.8.6;
pragma abicoder v2;
//SPDX-License-Identifier: MIT

import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";
import "../node_modules/solidity-bytes-utils/contracts/BytesLib.sol";
import "./utils/Equation.sol";
import "./interface/ITokenReceiver.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FlowCall is Ownable, Pausable {
    using BytesLib for bytes;
    using Equation for Equation.Node[];
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public constant MAX_CALL_SEQ = 100;
    uint256 public constant PARAMETER_ID_FOR_TARGET_CONTRACT = 9999999999;
    uint256 public constant PARAMETER_ID_FOR_SEND_ETH_VALUE = 9999999998;
    uint256 public constant PARAMETER_ID_FOR_TOKEN_AMOUNT = 9999999997;
    address public tokenReceiver;

    enum CallType {
        callContract,
        execRevert,
        safeReceive
    }

    struct CallInfo {
        CallType callType;
        address targetContract;
        bytes callData;
        uint256 sendEthValue;
        uint256 seq;
        ParameterFromVariable[] variableParameters;
        uint256 returnValuesCount;
        uint256[] callCondition;
        uint256 tokenAmount; //only used for safeReceive
    }

    struct ParameterFromVariable {
        uint256 parameterId; //refer to target contract if it equals PARAMETER_ID_FOR_TARGET_CONTRACT or PARAMETER_ID_FOR_SEND_ETH_VALUE
        uint256 variableId;
    }

    struct DataValue {
        //only support bytes32 fixed length variable type
        bool isValueSet;
        bytes32 value;
    }

    enum TriggerType {
        afterCall,
        afterSetVariableOperation
    }

    struct SetVariableOperation {
        uint256 variableIdToSet;
        TriggerType triggerType;
        uint256 triggerId; //callId or operationId according to the trigger type
        uint256[] valueExpression;
    }

    event ExternalCall(
        address indexed targetContract,
        uint256 sendValue,
        bytes callData,
        bytes returnData
    );

    event SafeReceiveCall(address indexed targetContract, uint256 tokenAmount);

    event SetVariable(uint256 indexed variableId, bytes32 value);

    constructor() {}

    receive() external payable {}

    function flowCall(
        CallInfo[] calldata callList,
        uint256 variableCount,
        SetVariableOperation[] calldata setVariableOperationList
    ) external payable whenNotPaused {
        _flowCall(callList, variableCount, setVariableOperationList);
    }

    function _flowCall(
        CallInfo[] calldata callList,
        uint256 variableCount,
        SetVariableOperation[] calldata setVariableOperationList
    ) private {
        require(callList.length > 0, "FC: at least one call needed");

        DataValue[] memory variableList = new DataValue[](variableCount);

        for (uint256 i = 0; i <= MAX_CALL_SEQ; i++) {
            for (uint256 j = 0; j < callList.length; j++) {
                if (callList[j].seq == i) {
                    //check call condition
                    if (callList[j].callCondition.length > 0) {
                        Equation.Node[] memory equation = Equation.init(
                            callList[j].callCondition
                        );
                        bool t = equation.calculateBool(
                            toXValues(variableList)
                        );
                        if (!t) continue;
                    }

                    if (callList[j].callType == CallType.execRevert) {
                        revert("FC: execute revert call");
                    } else if (callList[j].callType == CallType.safeReceive) {
                         (,address target,,uint256 tokenAmount) = buildCallData(callList[j], variableList);
                         require(
                            tokenAmount > 0,
                            "FC: amount missed"
                        );
                        safeReceive(
                            target,
                            tokenAmount
                        );
                        emit SafeReceiveCall(
                            target,
                            tokenAmount
                        );
                    } else if (callList[j].callType == CallType.callContract) {
                        checkContractCall(callList[j]);

                        (
                            bytes memory callData,
                            address target,
                            uint256 sendEthValue,
                        ) = buildCallData(callList[j], variableList);
                        (bool success, bytes memory returnData) = target.call{
                            value: sendEthValue
                        }(callData);
                        require(success, "FC: external call failed");
                        emit ExternalCall(
                            target,
                            sendEthValue,
                            callData,
                            returnData
                        );
                        //set after call
                        for (
                            uint256 k = 0;
                            k < setVariableOperationList.length;
                            k++
                        ) {
                            if (
                                setVariableOperationList[k].triggerType ==
                                TriggerType.afterCall &&
                                j == setVariableOperationList[k].triggerId
                            ) {
                                //build return values
                                require(
                                    setVariableOperationList[k]
                                    .valueExpression
                                    .length > 0,
                                    "FC: invalid value expression"
                                );
                                require(
                                    returnData.length >=
                                        callList[j].returnValuesCount * 32,
                                    "FC: invalid return values count"
                                );
                                require(
                                    setVariableOperationList[k]
                                    .variableIdToSet < variableCount,
                                    "FC: invalid variableIdToSet"
                                );
                                uint256[] memory returnValues = new uint256[](
                                    callList[j].returnValuesCount
                                );
                                for (
                                    uint256 ridx = 0;
                                    ridx < callList[j].returnValuesCount;
                                    ridx++
                                ) {
                                    returnValues[ridx] = returnData.toUint256(
                                        ridx * 32
                                    );
                                }
                                Equation.Node[] memory equation = Equation.init(
                                    setVariableOperationList[k].valueExpression
                                );
                                variableList[
                                    setVariableOperationList[k].variableIdToSet
                                ] = DataValue(
                                    true,
                                    bytes32(equation.calculate(returnValues))
                                );
                                emit SetVariable(
                                    setVariableOperationList[k].variableIdToSet,
                                    variableList[
                                        setVariableOperationList[k]
                                            .variableIdToSet
                                    ]
                                        .value
                                );
                                variableList = afterSetVariable(
                                    k,
                                    variableList,
                                    setVariableOperationList
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    function flowCallSafe(
        CallInfo[] calldata callList,
        uint256 variableCount,
        SetVariableOperation[] calldata setVariableOperationList,
        address[] calldata approvedTokens
    ) external payable whenNotPaused {
        uint256[] memory balanceBefore=fetchBalance(approvedTokens);
        uint256 ethBalanceBefore=address(this).balance.sub(msg.value);
        _flowCall(callList,variableCount,setVariableOperationList);
        uint256[] memory balanceAfter=fetchBalance(approvedTokens);
        uint256 ethBalanceAfter=address(this).balance;
        for(uint256 i=0;i<balanceBefore.length;i++){
            if(balanceAfter[i]>balanceBefore[i]){
                IERC20(approvedTokens[i]).safeTransfer(msg.sender,balanceAfter[i].sub(balanceBefore[i]));
            }
        }
        if(ethBalanceAfter>ethBalanceBefore){
            payable(msg.sender).transfer(ethBalanceAfter.sub(ethBalanceBefore));
        }
    }

    function fetchBalance(address[] calldata tokens) private view returns (uint256[] memory){
        uint256[] memory balanceList=new uint256[](tokens.length);
        for(uint256 i=0;i<tokens.length;i++){
            balanceList[i]=IERC20(tokens[i]).balanceOf(address(this));
        }
        return balanceList;
    }

    function checkContractCall(CallInfo calldata call) private view {
        require(call.targetContract != tokenReceiver, "FC: forbidden contract");
        require(call.targetContract != address(this), "FC: can't call self");
        require(call.callData.length >= 4, "FC: invalid call data");
        bytes memory callData = call.callData;
        bytes4 methodId;
        assembly {
            // 32 bytes is the length of the bytes array
            methodId := mload(add(callData, 32))
        }
        if (methodId == 0x23b872dd) {
            //transferFrom
            address sender;
            assembly {
                // 32 bytes is the length of the bytes array
                sender := mload(add(callData, 36))
            }
            require(sender == msg.sender, "FC: transfer sender limit");
        }
    }

    function afterSetVariable(
        uint256 operationId,
        DataValue[] memory variableList,
        SetVariableOperation[] calldata setVariableOperationList
    ) private returns (DataValue[] memory) {
        //set after opertion
        for (uint256 i = 0; i < setVariableOperationList.length; i++) {
            if (
                setVariableOperationList[i].triggerType ==
                TriggerType.afterSetVariableOperation &&
                setVariableOperationList[i].triggerId == operationId
            ) {
                Equation.Node[] memory equation = Equation.init(
                    setVariableOperationList[i].valueExpression
                );
                uint256[] memory xValues = toXValues(variableList);
                variableList[
                    setVariableOperationList[i].variableIdToSet
                ] = DataValue(true, bytes32(equation.calculate(xValues)));
                emit SetVariable(
                    setVariableOperationList[i].variableIdToSet,
                    variableList[setVariableOperationList[i].variableIdToSet]
                        .value
                );
                variableList = afterSetVariable(
                    i,
                    variableList,
                    setVariableOperationList
                );
            }
        }
        return variableList;
    }

    function toXValues(DataValue[] memory variableList)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory xValues = new uint256[](variableList.length);
        for (uint256 j = 0; j < variableList.length; j++) {
            xValues[j] = uint256(variableList[j].value);
        }
        return xValues;
    }

    function buildCallData(
        CallInfo calldata call,
        DataValue[] memory variableList
    )
        private
        pure
        returns (
            bytes memory,
            address,
            uint256,
            uint256
        )
    {
        bytes memory callData = call.callData;
        address targetContract = call.targetContract;
        uint256 sendEthValue = call.sendEthValue;
        uint256 tokenAmount = call.tokenAmount;
        if (call.variableParameters.length == 0) {
            return (callData, targetContract, sendEthValue, tokenAmount);
        }

        for (uint256 i = 0; i < call.variableParameters.length; i++) {
            require(
                call.variableParameters[i].variableId >= 0 &&
                    call.variableParameters[i].variableId < variableList.length,
                "FC: variableId illegal"
            );
            DataValue memory v = variableList[
                call.variableParameters[i].variableId
            ];
            require(v.isValueSet, "FC: this variable value hasn't be set");
            if (
                call.variableParameters[i].parameterId ==
                PARAMETER_ID_FOR_TARGET_CONTRACT
            ) {
                targetContract = address(uint160(uint256(v.value)));
            } else if (
                call.variableParameters[i].parameterId ==
                PARAMETER_ID_FOR_SEND_ETH_VALUE
            ) {
                sendEthValue = uint256(v.value);
            } else if (
                call.variableParameters[i].parameterId ==
                PARAMETER_ID_FOR_TOKEN_AMOUNT
            ) {
                tokenAmount = uint256(v.value);
            } else {
                uint256 start = call.variableParameters[i].parameterId * 32 + 4;
                uint256 length = callData.length;
                require(length - start - 32 >= 0, "FC: parameterId illegal");
                bytes32 value = v.value;
                assembly {
                    mstore(add(add(callData, 32), start), value)
                }
            }
        }
        return (callData, targetContract, sendEthValue, tokenAmount);
    }

    function kill(address payable fundTaker) external onlyOwner {
        selfdestruct(fundTaker);
    }

    function setTokenReceiver(address _tokenReceiver) external onlyOwner {
        tokenReceiver = _tokenReceiver;
    }

    function safeReceive(address erc20Token, uint256 amount) private {
        ITokenReceiver(tokenReceiver).receiveToken(
            msg.sender,
            amount,
            erc20Token
        );
    }
}
