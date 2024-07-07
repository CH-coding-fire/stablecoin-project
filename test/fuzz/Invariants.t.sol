// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        // targetContract(address(dsce)); //tell foundry go wild on this!!
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_mustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);
        console.log("totalSupply",totalSupply);
        console.log("wethValue", wethValue);
        console.log("wbtcValue", wbtcValue);
        console.log("Times mint1 called ", handler.timesMintIsCalled_1());
        console.log("Times mint2 called ", handler.timesMintIsCalled_2());
        console.log("Times mint3 called ", handler.timesMintIsCalled_3());
        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view{
        //this is lay up test that 100% should have
        dsce.getMinHealthFactor();
        dsce.getDSCAddress();
        dsce.getCollateralTokens();
    }


}

