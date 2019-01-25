var Exchange = artifacts.require("Exchange");
var BK = artifacts.require("BK");

module.exports = function (deployer) {
  deployer.deploy(Exchange);
  deployer.deploy(BK);
};