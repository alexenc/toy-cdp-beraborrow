// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ToyCDPEngine} from "../src/ToyCDPEngine.sol";
import {STABLE} from "../src/STABLE.sol";
import {MockEthOracle} from "../src/libraries/MockEthOracle.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

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

        console.log(cdpEngine.getProtocolCr());
        vm.stopPrank();
    }

    function testFail_OpenPositionWithInsufficientCollateral() public {
        vm.startPrank(USER);
        // Try to borrow too much STABLE for the collateral amount
        cdpEngine.openPosition(COLLATERAL_AMOUNT, 100000e18);
        vm.stopPrank();
    }
}
