// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Chris
 *
 * The system is designed to be as minmal as possible, and have the tokens maintain a 1 token == 1 USD peg
 * This stable has the properties:
 * Exogenous Collateral
 * Dollar Pegged
 * Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees,
 * and was only backed WETH and WBTC
 *
 * Our DSC system should always be "overconllateralized". At no point, should the value of all collateral <= the $ backed value of all the DSC
 *
 * @notice This contract is core of DSC System. It handles all the logic for mining
 * and redeeming DSC, as well as depositing #withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__DSCEngineTransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__CollateralExceedsBalance();
    error DSCEngine__TransferFail();
    error DSCEngine__HealthFactorOk();
    error DSEngine__HealthFactorNotImproved();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //this means a 10% bonus

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        //USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH/USD, BTC/USD, MKR/USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @notice this function will deposit collateral and mint dsc in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__DSCEngineTransferFailed();
        }
    }

    /*
     * This function burns DSC and redeems underlying collateral in one
     */

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public payable nonReentrant moreThanZero(amountCollateral) {
        //todo: it should have payable here, correct?
        if (
            amountCollateral >=
            s_collateralDeposited[msg.sender][tokenCollateralAddress]
        ) {
            revert DSCEngine__CollateralExceedsBalance();
        }
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFActorIsBroken(msg.sender);
    }

    /*
     * @param amountDscToMint The amount of the DSC that is wanted to be minted.
     * @notice they must have more collateral value than the minimum threshold
     *
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //if they minted too much, we need to revert
        _revertIfHealthFActorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFActorIsBroken(msg.sender); //this is probably unnecessary
    }

    function _burnDsc(
        uint256 amountToBurn,
        address onBehalf,
        address dscFrom
    ) private moreThanZero(amountToBurn) {
        //this help to pay the debt, as that user's minting record, is canceled, so he does not need to pay any debt for getting his collateral.
        s_DSCMinted[onBehalf] -= amountToBurn;
        // this take away the dsc of the liquiter and burn it (move the dsc to the contract)...
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFail();
        }
        i_dsc.burn(amountToBurn);
    }

    /*
     * @param collateral the erc20 collateral address to liquidate from the user //wtf is that?
     * @param user The user who has broken health factor...
     * @param debtToCover The amount of DSC you want to burn to improve the health factor
     * @notice You can partially liquidate a user
     * @notice You will geet a liquidation bonus for taking the users funds
     * @notice This function working assume the protocol will be roughly 200% overcollateralized in order for this to work
     * @notice a known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentiviise the liquidators
     * For example, fi the price of the collateral plummeted before anyone could be liquidated
     */

    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // We want to burn their DSC "debt"
        // And take their collateral
        // Bad User: $140 ETH, $100DSC
        // debtToCover = $100
        // $100 of DSC == ???
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // And give them a 10% bonus
        // So we are giving liquidator $110 of WETH for 100 DSC..
        //  WTF again? why give the WETH to liquidator? like if give, should it be something like $10? why not $110?
        // we should implement a feature to liquiadate in the vent the protocol is insolvent
        // And sweep extra amounts into a treasury

        //so if tokenAmountFromDebtCovered = 0.5 eth, then the bonus would be 0.5 * 10 / 100 = 0.05
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        /**
         * @dev Low-level internal function, do not call unless the function calling it is
         * checking for health factores being broken
         */
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFActorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /*
     * returns how close a liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    //THIS HAS BUG!!! INSPECT LATER
    function _healthFactor(address user) private view returns (uint256) {
        //total DSC minted
        //total collateral VALUE
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    //private and internal functions
    function _revertIfHealthFActorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //Public and external view functions

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // E.g. 1 ETH = 2000 USD
        // If the usdAmountInWei is 1000,
        // then token collateral (eth) should be usdAmountInWei/usd value of collateral = 1000/2000 = 0.5 eth

        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // ($10e18 * 1e18) / ($2000e8 * 1e10)
        // Where the hell this "10" come out from?

        //I wonder, the correct math should be

        // Let say, the usd worth of dsc we want to burn is $1000, so
        // uint256 usdAmountInWei = 1000e18
        // then, we want to get how much usd does 1 collateral token worth
        // since the "price" returned by Chainlink, is 8 deceimal
        // we need to adjust it to align with wei
        // so priceInWei = uint256(price) * ADDITIONAL_FEED_PRECISION = 2000e8 * 1e10 = 2000e18
        // so howMuchTheCollaterall = useAmountInWei / priceInWei = 1000e18/2000e18 = 0.5
        // but 0.5 is not a validate eth, eth should be e18
        // so collateral in eth = 0.5e18

        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);

        //price of eth (token)
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        //is that necessary?
        //I want to test this syntax, this is so unusal to me
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd; //like is that necessary?
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[token]
        ); //this is the priceFeed address
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION; //okok, why devide, I guess I am not good at math of solidity
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (success) {
            revert DSCEngine__TransferFail();
        }
        //some of the collateral goes to the "from address"
        // the bonus go to "to"
        // the question is
    }
}
