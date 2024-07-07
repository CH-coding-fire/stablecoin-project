// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "../mocks/Mockv3Aggregator.sol";

//Price Feed
//WETH Token
//WBTC

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled_1;
    uint256 public timesMintIsCalled_2;
    uint256 public timesMintIsCalled_3;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;


    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        if (maxCollateralToRedeem==0){
            return;
        }
        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);
      
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if(usersWithCollateralDeposited.length==0){
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed%usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);

        int256 maxDscToMint = int256(collateralValueInUsd/2)-int256(totalDscMinted);
        console.log("collateralValueInUsd", collateralValueInUsd);
        timesMintIsCalled_1++; 


        if(maxDscToMint<=0){
            return;
        }

        timesMintIsCalled_2++;
        console.log("amount", amount);

        amount = bound(amount,0, uint256(maxDscToMint));
        if(amount ==0){
            return;
        }

        timesMintIsCalled_3++;

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
    }

    //This can break the protocol, e.g. eth price drop to 1 USD
    // function updateCollateralPrice(uint96 newPrice) public{
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

}
