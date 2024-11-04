// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToyCDPEngine} from "../../src/ToyCDPEngine.sol";
import {STABLE} from "../../src/STABLE.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockEthOracle} from "../../src/libraries/MockEthOracle.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract CdpEngineHandler is Test {
    ToyCDPEngine public cdpEngine;
    STABLE public stablecoin;
    ERC20Mock public weth;
    MockEthOracle public ethOracle;

    address[] public operators;
    uint256 constant NUM_OPERATORS = 5;
    address LIQUIDATOR = makeAddr("liquidator");

    mapping(address => bool) public hasPosition;
    address[] public users;

    constructor(
        ToyCDPEngine _toyCdpEngine,
        STABLE _stable,
        ERC20Mock _weth,
        MockEthOracle oracle
    ) {
        cdpEngine = _toyCdpEngine;
        stablecoin = _stable;
        weth = _weth;
        ethOracle = oracle;
        createOperators();
    }

    function openPosition(
        address user,
        uint256 collateralAmount,
        uint256 debtAmount
    ) public {
        // Bound inputs to reasonable ranges
        collateralAmount = bound(collateralAmount, 0.1 ether, 100 ether);
        debtAmount = bound(debtAmount, 100e18, 10_000e18);

        // Select operator using helper function
        address operator = selectOperator(collateralAmount);

        // Check collateral ratio is above 110%
        uint256 ethPrice = ethOracle.getPrice();
        uint256 collateralValue = (collateralAmount * ethPrice) / 1e18;
        uint256 collateralRatio = (collateralValue * 10000) / debtAmount;
        if (collateralRatio < 11000) return;

        // Give operator WETH and approve CDP engine
        weth.mint(operator, collateralAmount);
        vm.startPrank(operator);
        weth.approve(address(cdpEngine), collateralAmount);

        cdpEngine.openPosition(collateralAmount, debtAmount);
        if (!hasPosition[operator]) {
            hasPosition[operator] = true;
        }

        vm.stopPrank();
    }

    function closePosition(address user) public {
        // Select random operator using bound for true randomness
        uint256 randomSeed = uint256(
            keccak256(abi.encodePacked(block.timestamp))
        );
        uint256 boundedIndex = bound(randomSeed, 0, operators.length - 1);
        address operator = operators[boundedIndex];

        if (!hasPosition[operator]) return;

        vm.startPrank(operator);
        uint256 debtAmount = stablecoin.balanceOf(operator);
        stablecoin.approve(address(cdpEngine), debtAmount);

        // Check if operator has enough STABLE to repay debt
        uint256 stableBalance = stablecoin.balanceOf(operator);
        if (stableBalance < debtAmount) return;

        // Check if position is healthy before closing
        uint256 collateralRatio = cdpEngine.getPositionCollateralRatio(
            operator
        );
        if (collateralRatio < 11000) return;

        cdpEngine.closePosition();
        hasPosition[operator] = false;
        // Remove operator from active users array
        vm.stopPrank();
    }

    function liquidate(address liquidator, address target) public {
        // Select liquidator using bound for true randomness

        // Loop through operators to find liquidatable positions
        for (uint256 i = 0; i < operators.length; i++) {
            address positionOwner = operators[i];

            // Skip if position owner has no position
            if (!hasPosition[positionOwner]) continue;

            // Check if position is below MCR
            uint256 collateralRatio = cdpEngine.getPositionCollateralRatio(
                positionOwner
            );
            if (collateralRatio >= 11000) continue;

            // Position is liquidatable - prepare liquidator
            vm.startPrank(LIQUIDATOR);

            // Get debt amount and deal STABLE to liquidator using forge deal
            uint256 debtAmount = cdpEngine.getUserDebt(positionOwner);
            deal(address(stablecoin), LIQUIDATOR, debtAmount);
            stablecoin.approve(address(cdpEngine), debtAmount);

            // Attempt liquidation
            cdpEngine.liquidate(positionOwner);
            hasPosition[positionOwner] = false;

            vm.stopPrank();
        }
    }

    function updateEthPrice(uint256 newPrice) public {
        newPrice = bound(newPrice, 1700e18, 2000e18);
        ethOracle.updatePrice(newPrice);
    }

    function createOperators() public {
        for (uint256 i = 0; i < NUM_OPERATORS; i++) {
            address operator = makeAddr(
                string.concat("operator", vm.toString(i))
            );
            operators.push(operator);
        }
    }

    function selectOperator(uint256 seed) public view returns (address) {
        if (operators.length == 0) return address(0);
        uint256 boundedSeed = bound(seed, 0, operators.length - 1);
        return operators[boundedSeed];
    }
}
