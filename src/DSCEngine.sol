// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregaotrV3Interface.sol";

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

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

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

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
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

    function depositCollateralAndMintDsc() external {}

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__DSCEngineTransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /*
    * @param amountDscToMint The amount of the DSC that is wanted to be minted.
    * @notice they must have more collateral value than the minimum threshold
    * 
    */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //if they minted too much, we need to revert
        revertIfHleathFActorIsBroken(msg.sender)
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /*
    * returns how close a liquidation a user is
    * If a user goes below 1, then they can get liquidated
    */

   function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd){
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);        
   }

    function _healthFactor(address user) private view returns (uint256){
        //total DSC minted
        //total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    }

    //private and internal functions
    function revertIfHleathFActorIsBroken(address user) internal view{
        //1. check if they enough collaral?
        //2. revert
    }

    function getAccountCollateralValue(address user) public view returns(uint256){
        for(uint256 i = 0; i<s_tokenAddresses.length; i++){
            address token = s_tokenAddresses[i];
            uint256 amount = s_collateralDeposited[user][token];
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){

    }


}