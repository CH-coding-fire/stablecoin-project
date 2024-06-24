// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    function run() external returns(DecentralizedStableCoin, DSCEngine) {
        // I should deploy a contract
        // vm.startbroadcast
        // new contract
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine();
        vm.stopBroadcast();
        //the url of node and private key will be provided in the command
    }

}