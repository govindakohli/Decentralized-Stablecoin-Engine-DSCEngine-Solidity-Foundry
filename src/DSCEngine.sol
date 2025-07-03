// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
pragma solidity ^0.8.29;

import {DecentrailizedStableCoin} from "./DecentrailizedStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.5/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Govinda
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stableCoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algoritmically Stable
 *
 * It is similar to DAI if DAI hadn no governance , no fees , and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized" . At no point , should the value of all collateral <= the backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system . It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 *
 * @notice This contract is very loosely based on the makerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////
    // Errors    //
    /////////////////

    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressessAndPriceFeedAddressessMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine___TransferFailed();
    error DSCEngine__BreakHealthfactor(uint256 healthFactor);
    error DSCEngine__MintFaild();
    error DSCEngie__HealthFactorOk();
    error DESEngine__HealthFactorNotImproved();

    /////////////////
    // State Variables    //
    /////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcoll
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means a 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentrailizedStableCoin private immutable i_dsc;

    /////////////////
    // Events    //
    /////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom  , address indexed redeemedTo , address  token , uint256  amount);

    /////////////////
    // Modifiers    //
    /////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////
    // Function    //
    /////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddressess, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddressess.length) {
            revert DSCEngine__TokenAddressessAndPriceFeedAddressessMustBeSameLength();
        }
        // for example ETH / USD , BTC / USD , MKR / USD , etc

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddressess[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentrailizedStableCoin(dscAddress);
    }

    /////////////////
    // External Function    //
    /////////////////

    /*
    *@param tokenCollateralAddress The address of the token to depost as collateral
    *@param amountCollateral The amount of collateral to deposit
    *@param amountDscToMint The amount of decentralized stablecoint to mint
    @notice this function will deposit your collateral and mint DSC in one transaction
    */

    function depositCollateralAndmintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
    *@notice follow CEI (check effect interaction)
    @param tokenCollateralAddress The address of the token to deposit as collateral
    @param amountCollateral The Amount of collateral to deposit
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine___TransferFailed();
        }
    }
   /*
   * @param tokenCollateralAddress The collateral address
   * @param amountCollateral The of collateral redeem
   * @param amountDscToBurn The amount of DSC to burn
   * This function burns DSC and redeems underlying collateral in one transaction
   */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral , uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks healthfactor
    }

    // In order to redeem collateral:
    // 1. health factor must be over 1 after collateral pulled.
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
       _redeemCollateral(msg.sender , msg.sender , tokenCollateralAddress , amountCollateral);
        _revertIfHealthFactorisBroken(msg.sender);
    }

    /*
    *@notice follows CEI
    *@param anountDscToMint The amount of decentralized stablecoin to mint
    *@notice they must have more collateral value than the mminimum threshold
    */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorisBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFaild();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
       _burnDsc(amount ,msg.sender, msg.sender);
        _revertIfHealthFactorisBroken(msg.sender); // I don't think this would ever hittt.....

    }

  /*
  * @param collateral The erc20 collateral address to liquidate from the user
  * @param user The user who has broken the health factor. their _healthFactor  should be below MIN_HEALTH_FACTOR
  * @param debtToCover The amount of DSC you want to burn to improve the users health factor
  * @notice You can partiallly liquidate a user 
  * @notice You will get a liquidate bonus for taking the users funds
  * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
  * @notice A known bug would be if the protocol were 100% or less collateralized, then we would't be able to incentive the liquidator.
  * for Example, if the price of the collateral plummeted before anyone could be liquidated.
  * 
  * follow CEI: Checks, Effects , Interactions
  */
    function liquidate(address collateral , address user , uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant{
       // need to check health factor of the user  
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngie__HealthFactorOk();
        }
        // we want to burn their DSC "debt"
        // And take their collateral
        
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral , debtToCover);
        // And give then a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the events the protocol is insolvent
        // And sweep extra amount into a treasury

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user , msg.sender , collateral , totalCollateralToRedeem);
        // We need to burn the DSC
        _burnDsc(debtToCover , user , msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor) {
            revert DESEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorisBroken(msg.sender);

        
    }

    function getHealthFactor() external view {}

    //////////////////////////////////
    // Private & Internal  view Function    //
    //////////////////////////////////

    /*
    *@dev Low-level internal function , do not call unless the function it is checking for health factor being broken
    */

    function _burnDsc(uint256 amountDscToBurn , address onbehalfOf , address dscFrom) private {
            s_DSCMinted[onbehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom , address(this) , amountDscToBurn);
        if(!success) {
            revert DSCEngine___TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

      function _redeemCollateral(address from , address to ,address tokenCollateralAddress , uint256 amountCollateral  ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from , to  , tokenCollateralAddress , amountCollateral);

        // _calculateHealthFactorAfter()

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success) {
            revert DSCEngine___TransferFailed();
        }
    }


    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collatearlValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collatearlValueInUsd = getAccountCollateralValue(user);
    }
    /*
    * Return how close to liquidation a user is 
    * If a user goes below 1 , then they can get liquidated
    */

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collatearlValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collatearlValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $150 ETH / 100 DSC = 1.5
        // 150*50 =7500/100 = (75/100) < 1

        // $1000 ETH / 100 DSC
        // 1000 * 50 = 50000 / 100 = (500 / 100) > 1
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; // (150 / 100)
    }
    //1. check health factor (do they have enough collateral?)
    // 2. Revert if they don't

    function _revertIfHealthFactorisBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthfactor(userHealthFactor);
        }
    }

    //////////////////////////////////
    // Public & External  view Function    //
    //////////////////////////////////

  
    function getTokenAmountFromUsd(address token , uint256 usdAmountInWei) public view returns(uint256){
        // price of ETH (token)
        // $/ETH ETH ??
        // $2000 / ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        
        return (usdAmountInWei * PRECISION) / (uint256(price)* ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to
        // the price , to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The retruned value from CL will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (1000 * 1e8 * (1e10)) *1000 * 1e18;
    }

    function getAccountInformation(address user) external view returns (uint256 totalDscMintes , uint256 collateralvalueInUsd) {
        (totalDscMintes , collateralvalueInUsd) = _getAccountInformation(user);
    }
}
