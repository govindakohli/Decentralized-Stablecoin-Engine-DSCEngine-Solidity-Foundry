// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {AggregatorV3Interface} from
    "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Govinda
 * @notice This Library is used to check the chainlink Oracle for stale data.
 * If a price is stale , the function will revert, and render the DSCEngine unusable - this is by design
 * We want the DSCEngine to freeze if price become stale.
 *
 * if the chainlink network explodes and you have a lot of money locked in the protocol.. too bad.
 *
 *
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondSince = block.timestamp - updatedAt;
        if (secondSince > TIMEOUT) {
            revert OracleLib__StalePrice();
            return (roundId, answer, startedAt, updatedAt, answeredInRound);
        }
    }
}
