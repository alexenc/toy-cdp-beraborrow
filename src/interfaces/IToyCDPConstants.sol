// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ToyCDPConstants {
    /**
     * @notice Minimum Collateralization Ratio (MCR) - 110% represented with 3 decimal precision
     * A position must maintain this ratio to avoid liquidation
     */
    uint256 constant MCR = 1100;

    /**
     * @notice Precision used for ratio calculations (3 decimals)
     */
    uint256 constant RATIO_PRECISION = 1000;

    /**
     * @notice Base interest rate of 5% annually
     */
    uint256 constant BASE_INTEREST_RATE = 5;

    /**
     * @notice Initial interest index value with 18 decimals precision
     */
    uint256 constant INITIAL_INTEREST_INDEX = 1e18;

    /**
     * @notice Number of seconds in a year, used for interest calculations
     */
    uint256 constant SECONDS_PER_YEAR = 365 days;

    /**
     * @notice Interest calculation precision
     */
    uint256 constant INTEREST_PRECISION = 1e18;
}
