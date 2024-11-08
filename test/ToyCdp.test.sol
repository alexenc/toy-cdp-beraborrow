// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ToyCDPEngine} from "../src/ToyCDPEngine.sol";
import {STABLE} from "../src/STABLE.sol";
import {MockEthOracle} from "../src/libraries/MockEthOracle.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployCdpEngine} from "../script/DeployToyCdp.s.sol";

contract ToyCdpTest is Test {
    ToyCDPEngine public cdpEngine;
    STABLE public stablecoin;
    ERC20Mock public weth;
    MockEthOracle public ethOracle;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant COLLATERAL_AMOUNT = 1 ether;
    uint256 public constant DEBT_AMOUNT = 1000e18; // 1000 STABLE

    function setUp() public {
        weth = new ERC20Mock();
        stablecoin = new STABLE();
        ethOracle = new MockEthOracle();
        cdpEngine = new ToyCDPEngine(
            address(stablecoin),
            address(weth),
            address(ethOracle)
        );
        stablecoin.transferOwnership(address(cdpEngine));

        // Give user some WETH
        weth.mint(USER, STARTING_USER_BALANCE);

        vm.startPrank(USER);
        weth.approve(address(cdpEngine), type(uint256).max);
        vm.stopPrank();
    }

    function test_OpenPosition() public {
        vm.startPrank(USER);

        uint256 userInitialWethBalance = weth.balanceOf(USER);
        uint256 userInitialStableBalance = stablecoin.balanceOf(USER);

        cdpEngine.openPosition(COLLATERAL_AMOUNT, DEBT_AMOUNT);

        assertEq(
            weth.balanceOf(USER),
            userInitialWethBalance - COLLATERAL_AMOUNT
        );
        assertEq(
            stablecoin.balanceOf(USER),
            userInitialStableBalance + DEBT_AMOUNT
        );

        vm.stopPrank();
    }

    function test_ClosePosition() public {
        vm.startPrank(USER);

        // First open a position
        cdpEngine.openPosition(COLLATERAL_AMOUNT, DEBT_AMOUNT);

        uint256 userInitialWethBalance = weth.balanceOf(USER);
        uint256 userInitialStableBalance = stablecoin.balanceOf(USER);

        // Approve stable for repayment
        stablecoin.approve(address(cdpEngine), type(uint256).max);

        cdpEngine.closePosition();

        // User should get back their collateral
        assertEq(
            weth.balanceOf(USER),
            userInitialWethBalance + COLLATERAL_AMOUNT
        );

        // User should have paid back their debt
        assertEq(
            stablecoin.balanceOf(USER),
            userInitialStableBalance - DEBT_AMOUNT
        );

        vm.stopPrank();
    }

    function test_InterestAccrualCorrectAccountingAfterRateChange() public {
        vm.startPrank(USER);

        // First open a position
        cdpEngine.openPosition(COLLATERAL_AMOUNT, DEBT_AMOUNT);

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        // Change interest rate from 5% to 3%
        vm.stopPrank();
        address USER2 = makeAddr("user2");

        cdpEngine.updateInterestRate(3);
        // Create a second user to open position and trigger interest accounting

        vm.startPrank(USER);

        // Fast forward another year
        vm.warp(block.timestamp + 365 days);
        // Approve stable for repayment
        stablecoin.approve(address(cdpEngine), type(uint256).max);

        // Calculate expected debt after interest
        // First year at 5%: DEBT_AMOUNT * 1.05
        // Second year at 3%: (DEBT_AMOUNT * 1.05) * 1.03
        // 10815e17
        // Deal user the additional stable needed to cover accrued interest
        deal(address(stablecoin), USER, 10815e17);

        uint256 userInitialStableBalance = stablecoin.balanceOf(USER);

        cdpEngine.closePosition();

        // User should have paid back their debt with accrued interest
        assertEq(stablecoin.balanceOf(USER), 0);

        vm.stopPrank();
    }

    function test_liquidatePosition() public {
        vm.startPrank(USER);
        address LIQUIDATOR = makeAddr("liquidator");
        // Create liquidator account with some ETH

        vm.deal(LIQUIDATOR, 100 ether);

        // First open a position
        cdpEngine.openPosition(COLLATERAL_AMOUNT, DEBT_AMOUNT);

        // Switch to liquidator account
        vm.stopPrank();
        vm.startPrank(LIQUIDATOR);

        // Give liquidator enough stable to repay the debt
        deal(address(stablecoin), LIQUIDATOR, DEBT_AMOUNT);
        stablecoin.approve(address(cdpEngine), type(uint256).max);

        // Store initial balances
        uint256 liquidatorInitialWethBalance = weth.balanceOf(LIQUIDATOR);
        uint256 liquidatorInitialStableBalance = stablecoin.balanceOf(
            LIQUIDATOR
        );

        // Drop ETH price to make position liquidatable
        vm.stopPrank();
        ethOracle.updatePrice(1000e18); // Significant price drop

        vm.startPrank(LIQUIDATOR);
        // Liquidate the position
        cdpEngine.liquidate(USER);

        // Liquidator should receive the collateral
        assertEq(
            weth.balanceOf(LIQUIDATOR),
            liquidatorInitialWethBalance + COLLATERAL_AMOUNT
        );

        // Liquidator should have paid the debt
        assertEq(
            stablecoin.balanceOf(LIQUIDATOR),
            liquidatorInitialStableBalance - DEBT_AMOUNT
        );

        vm.stopPrank();
    }

    function test_ClosePositionWithInterest() public {
        vm.startPrank(USER);

        // First open a position
        cdpEngine.openPosition(COLLATERAL_AMOUNT, DEBT_AMOUNT);

        uint256 userInitialWethBalance = weth.balanceOf(USER);
        uint256 userInitialStableBalance = stablecoin.balanceOf(USER);

        // Approve stable for repayment
        stablecoin.approve(address(cdpEngine), type(uint256).max);
        // Advance time by 1 year to accrue interest at 5% APR
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);

        // Expected debt after 1 year with 5% interest
        uint256 expectedDebt = (DEBT_AMOUNT * 105) / 100;
        deal(address(stablecoin), USER, (DEBT_AMOUNT * 105) / 100);
        cdpEngine.closePosition();

        // User should get back their collateral
        assertEq(
            weth.balanceOf(USER),
            userInitialWethBalance + COLLATERAL_AMOUNT
        );

        // User should have paid back their debt plus interest
        assertEq(stablecoin.balanceOf(USER), 0);

        vm.stopPrank();
    }

    function testFail_OpenPositionWithInsufficientCollateral() public {
        vm.startPrank(USER);
        // Try to borrow too much STABLE for the collateral amount
        cdpEngine.openPosition(COLLATERAL_AMOUNT, 100000e18);
        vm.expectRevert("Collateral ratio too low");
        vm.stopPrank();
    }
}
