// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {Script} from "../lib/forge-std/src/Script.sol";
import {DecentrailizedStableCoin} from "../src/DecentrailizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentrailizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentrailizedStableCoin dsc = new DecentrailizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();
        return (dsc, engine, config);
    }
}
