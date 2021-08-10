var flowCall=artifacts.require("./FlowCall");
var tokenReceiver=artifacts.require("./TokenReceiver");


module.exports = async function(_deployer,_network) {
  if(_network=="bsctestnet"){
    await _deployer.deploy(flowCall);
    const flowCallInstance=await flowCall.deployed();
    await _deployer.deploy(tokenReceiver);
    const tokenReceiverInstance=await tokenReceiver.deployed();
    await flowCallInstance.setTokenReceiver(tokenReceiverInstance.address);
    await tokenReceiverInstance.setFlowCallAddress(flowCallInstance.address);
  }
  else if(_network=="bscmainnet"){
    
  }
  else if(_network=="hecomainnet"){
    await _deployer.deploy(flowCall);
    const flowCallInstance=await flowCall.deployed();
    await _deployer.deploy(tokenReceiver);
    const tokenReceiverInstance=await tokenReceiver.deployed();
    await flowCallInstance.setTokenReceiver(tokenReceiverInstance.address);
    await tokenReceiverInstance.setFlowCallAddress(flowCallInstance.address);
  }
  else{
  
  }
};
