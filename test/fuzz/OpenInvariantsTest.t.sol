// // Have our invariant aka properties

// // What are our invariants?

// // 1. The total supply of DSC should be less than the total value of collateral
// // 2. Getter view function should never revert <- evergreen invariant

// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.29;

// import {Test , console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentrailizedStableCoin} from "../../src/DecentrailizedStableCoin.sol";
// import{HelperConfig} from "../../script/HelperConfig.s.sol";
// import{IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant , Test {
//  DeployDSC deployer;
//      DSCEngine dsce;
//      DecentrailizedStableCoin dsc;
//      HelperConfig config;
//      address weth;
//      address wbtc;

//     function setUp() external {
//       deployer = new DeployDSC();
//       (dsc , dsce , config) = deployer.run();
//       (,, weth , wbtc ,)= config.activeNetworkConfig();
//       targetContract(address(dsce));

//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//     // get the value of all the collateral in the protocol
//     // compare it to all the debt (dsc)

//     uint256 totalSupply = dsc.totalSupply();
//     uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
//     uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

//     uint256 wethValue = dsce.getUsdValue(weth , totalWethDeposited);
//     uint256 wbtcValue = dsce.getUsdValue(wbtc , totalBtcDeposited);

//    console.log("weth Value:" , wethValue);
//    console.log("wbtc Value:" , wbtcValue);
//    console.log("total Supply:" , totalSupply);

//     assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
