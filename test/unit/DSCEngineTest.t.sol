// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public engine;
    HelperConfig public config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    address public USER_2 = makeAddr("user_2");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public returns (DecentralizedStableCoin, DSCEngine) {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , deployerKey) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //constructor test

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertTokenAddressesAndPriceFeedAddressesMustBeSameLength()
        public
    {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //price tests

    function testGetUsdValue() public {
        console.log(deployerKey);
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        //wtf? howcome it assume 1 eth = 2000 usd? This is assuming I am using the anvil chain...
        // ok, test always use anvil chain, correct?
        // maybe I should console.log(msg.sender)
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    //test depositCollateral

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        vm.startPrank(USER);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    modifier depositedCollateralWeth() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        //I want to test, what if not approved? Let me draw a graph
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 balance = ERC20Mock(weth).balanceOf(USER);
        assertEq(balance, STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateralWeth
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(address(USER));

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRevertDepositCollateralAndRedeemExceedBalance()
        public
        depositedCollateralWeth
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(address(USER));
        vm.expectRevert(DSCEngine.DSCEngine__CollateralExceedsBalance.selector);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL * 10);
        vm.stopPrank();
    }

    function testDepositCollateralAndRedeem() public depositedCollateralWeth {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(address(USER));
        uint256 startBalance = ERC20Mock(weth).balanceOf(USER);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        assertEq(STARTING_ERC20_BALANCE, startBalance + AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //for vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor2.selector);, I don't know how to handle a BreakHealthFactor with the specific health number unit
    function testRevertBreaksHealthFactorDepositCollateralAndMintDsc() public {
        uint256 trialDscToMint = 999999999999 ether; // this is supposed to fail, as amount of collateral is 10 ether
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor2.selector);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            trialDscToMint
        );
    }

    function testDepositCollateralAndMintDsc() public {
        uint256 trialDscToMint = 1000 ether; // this is supposed to success, as collaterol is 10 ether, and 1 eth at least = 2000 usd
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            trialDscToMint
        );
        address dscAddress = engine.getDSCAddress();
        assertEq(ERC20Mock(dscAddress).balanceOf(USER), trialDscToMint);
    }

    function testDepositCollateralAndMintDscTheBurn() public {
        uint256 trialDscToMint = 1000 ether; // this is supposed to success, as collaterol is 10 ether, and 1 eth at least = 2000 usd
        uint256 amountToBurnt = 400 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            trialDscToMint
        );
        address dscAddress = engine.getDSCAddress();
        ERC20Mock(dscAddress).approve(address(engine), trialDscToMint);
        assertEq(ERC20Mock(dscAddress).balanceOf(USER), trialDscToMint);
        engine.burnDsc(amountToBurnt);
        assertEq(
            ERC20Mock(dscAddress).balanceOf(USER),
            trialDscToMint - amountToBurnt
        );
    }

    function testGetHealthFactor() public {
        uint256 expectedHealthFactor = 1e18;
        assertEq(engine.getMinHealthFactor(), expectedHealthFactor);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    function testRevertHealthFactorOkLiquidate() public {
        uint256 trialDscToMint = 1000 ether; // this is supposed to success, as collaterol is 10 ether, and 1 eth at least = 2000 usd
        uint256 amountToBurnt = 400 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            trialDscToMint
        );
        address dscAddress = engine.getDSCAddress();
        ERC20Mock(dscAddress).approve(address(engine), trialDscToMint);
        assertEq(ERC20Mock(dscAddress).balanceOf(USER), trialDscToMint);
        engine.burnDsc(amountToBurnt);
        assertEq(
            ERC20Mock(dscAddress).balanceOf(USER),
            trialDscToMint - amountToBurnt
        );
        vm.stopPrank();
        vm.startPrank(USER_2);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, 300);
    }

    function testLiquidate() public {
        uint256 trialDscToMint = 1000 ether; // this is supposed to success, as collaterol is 10 ether, and 1 eth at least = 2000 usd
        uint256 amountToBurnt = 400 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            trialDscToMint
        );
        address dscAddress = engine.getDSCAddress();
        ERC20Mock(dscAddress).approve(address(engine), trialDscToMint);
        assertEq(ERC20Mock(dscAddress).balanceOf(USER), trialDscToMint);
        engine.burnDsc(amountToBurnt);
        assertEq(
            ERC20Mock(dscAddress).balanceOf(USER),
            trialDscToMint - amountToBurnt
        );
        vm.stopPrank();

        ////// now, the eth price DROPS!! and USER_2 want to liquidate USER, that's evil

        //USER_2 mint 3 ether of Dsc
        uint256 STARTING_ERC20_BALANCE2 = 99999999999999999999 ether;
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE2);
        uint256 trialDscToMint2 = 3 ether; // this is supposed to success, as collaterol is 10 ether, and 1 eth at least = 2000 usd
        uint256 collateralOfUser2 = STARTING_ERC20_BALANCE2;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), collateralOfUser2);
        engine.depositCollateralAndMintDsc(
            weth,
            collateralOfUser2,
            trialDscToMint2
        );

        console.log("before", engine.healthFactor(USER));
        int256 resetPrice = 3e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(resetPrice);

        (, int256 answer, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();
        assertEq(answer, resetPrice);
        console.log("after", engine.healthFactor(USER));
        uint256 DscUsedToPayDept = 3 ether;
        ERC20Mock(dscAddress).approve(address(engine), DscUsedToPayDept);

        engine.liquidate(weth, USER, DscUsedToPayDept);
    }

    function testUpdateAnswerInMockV3Aggregator() public {
        int256 resetPrice = 3e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(resetPrice);

        (, int256 answer, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();
        assertEq(answer, resetPrice);
    }

    function testRedeemCollateralForDsc() public {
        uint256 trialDscToMint = 1000 ether; // this is supposed to success, as collaterol is 10 ether, and 1 eth at least = 2000 usd
        uint256 amountToBurnt = 400 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            trialDscToMint
        );
        address dscAddress = engine.getDSCAddress();
        ERC20Mock(dscAddress).approve(address(engine), trialDscToMint);
        assertEq(ERC20Mock(dscAddress).balanceOf(USER), trialDscToMint);
        uint256 amountOfCollateralWantToRedeem = 2 ether;
        engine.redeemCollateralForDsc(
            weth,
            amountOfCollateralWantToRedeem,
            amountToBurnt
        );
        assertEq(
            ERC20Mock(weth).balanceOf(USER),
            STARTING_ERC20_BALANCE -
                AMOUNT_COLLATERAL +
                amountOfCollateralWantToRedeem
        );
        assertEq(
            ERC20Mock(dscAddress).balanceOf(USER),
            trialDscToMint - amountToBurnt
        );
        vm.stopPrank();
    }

    function testGetAccountCollateralValue() public depositedCollateralWeth {
        uint256 expectedCollateralValue = 2000 * AMOUNT_COLLATERAL;
        assertEq(
            engine.getAccountCollateralValue(USER),
            expectedCollateralValue
        );
    }
}
