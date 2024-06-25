// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public engine;
    HelperConfig public config;
    address ethUsdPriceFeed;
    address weth;

    function setUp() public returns (DecentralizedStableCoin, DSCEngine) {
        deployer = new DeployerDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, , weth, ) = config.activeNetworkConfig();
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18; //wtf? howcome it assume 1 eth = 2000 usd?
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }
}
