// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentrailizedStableCoin} from "../../src/DecentrailizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";

contract DESEngineTest is Test {
    // DeployDSC deployer;
    DecentrailizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        // ERC20Mock(weth)._mint(USER,STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    ///Constructor Tests ////////
    ///////////////////////
    
    address[] public priceFeedAddresses;
    address[] public tokenAddresses;

    function testRevertIfTokenLengthDoesntmatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressessAndPriceFeedAddressessMustBeSameLength.selector);
        new DSCEngine(tokenAddresses , priceFeedAddresses , address(dsc));
    }

    ///////////////////////
    ///Price Tests ////////
    ///////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30000e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;

        // $2000 / ETH , $100
        uint256 expectedWth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth , usdAmount);
        assertEq(expectedWth, actualWeth);
    }

    ///////////////////////
    ///depositCollateral  Tests ////////
    ///////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN" , "RAN", USER , AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    
    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
    (uint256 totalDscMinted , uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
    
    uint256 expectedTotalDscMinted = 0;
    uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd);
    assertEq(totalDscMinted , expectedTotalDscMinted);
    assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
