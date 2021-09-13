var flowCallHelper=artifacts.require("./FlowCallHelper");

module.exports = async function(_deployer,_network) {
  if(_network=="bsctestnet"){
    await _deployer.deploy(flowCallHelper);
    const flowCallHelperInstance = await flowCallHelper.deployed();
  }
  else if(_network=="bscmainnet"){
    await _deployer.deploy(flowCallHelper);
    const flowCallHelperInstance = await flowCallHelper.deployed();
  }
  else if(_network=="hecomainnet"){
    await _deployer.deploy(flowCallHelper);
    const flowCallHelperInstance = await flowCallHelper.deployed();
  }
  else{
  
  }
};
