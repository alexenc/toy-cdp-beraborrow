// SPDX-License-Identifier: MIT
/*pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToyCDPEngine} from "../../src/ToyCDPEngine.sol";
import {STABLE} from "../../src/STABLE.sol";
import {MockEthOracle} from "../../src/libraries/MockEthOracle.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract CdpEngineHandler is Test {
    ToyCDPEngine public cdpEngine;
    STABLE public stablecoin;
    ERC20Mock public weth;
    MockEthOracle public ethOracle;

    constructor(ToyCDPEngine _toyCdpEngine, STABLE _stable) {
        cdpEngine = _toyCdpEngine;
        stablecoin = _stable;
    }

    function openPosition(
        address user,
        uint256 collateralAmount,
        uint256 debtAmount
    ) public {
        // Bound inputs to reasonable ranges
        collateralAmount = bound(collateralAmount, 0.1 ether, 100 ether);
        debtAmount = bound(debtAmount, 100e18, 10_000e18);

        // Give user WETH and approve CDP engine
        weth.mint(user, collateralAmount);
        vm.startPrank(user);
        weth.approve(address(cdpEngine), collateralAmount);

        try cdpEngine.openPosition(collateralAmount, debtAmount) {
            if (!hasPosition[user]) {
                users.push(user);
                hasPosition[user] = true;
            }
        } catch {}

        vm.stopPrank();
    }

    function closePosition(address user) public {
        if (!hasPosition[user]) return;

        vm.startPrank(user);
        uint256 debtAmount = stablecoin.balanceOf(user);
        stablecoin.approve(address(cdpEngine), debtAmount);

        try cdpEngine.closePosition() {
            hasPosition[user] = false;
            // Remove user from active users array
            for (uint i = 0; i < users.length; i++) {
                if (users[i] == user) {
                    users[i] = users[users.length - 1];
                    users.pop();
                    break;
                }
            }
        } catch {}

        vm.stopPrank();
    }

    function liquidate(address liquidator, address target) public {
        if (!hasPosition[target]) return;

        vm.startPrank(liquidator);

        // Give liquidator enough stable to potentially liquidate
        uint256 maxDebt = 10_000e18;
        deal(address(stablecoin), liquidator, maxDebt);
        stablecoin.approve(address(cdpEngine), maxDebt);

        try cdpEngine.liquidate(target) {
            hasPosition[target] = false;
            // Remove liquidated user from active users
            for (uint i = 0; i < users.length; i++) {
                if (users[i] == target) {
                    users[i] = users[users.length - 1];
                    users.pop();
                    break;
                }
            }
        } catch {}

        vm.stopPrank();
    }

    function updateEthPrice(uint256 newPrice) public {
        newPrice = bound(newPrice, 100e18, 10_000e18);
        ethOracle.setPrice(newPrice);
    }

 
}
*/