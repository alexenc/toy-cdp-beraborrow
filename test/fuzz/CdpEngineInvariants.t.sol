// TODO Finish invariant testing
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ToyCDPEngine} from "../../src/ToyCDPEngine.sol";
import {STABLE} from "../../src/STABLE.sol";
import {MockEthOracle} from "../../src/libraries/MockEthOracle.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {CdpEngineHandler} from "./CdpEngineHandler.t.sol";
import {console} from "forge-std/console.sol";

contract CdpEngineInvariantsTest is StdInvariant, Test {
    ToyCDPEngine public cdpEngine;
    STABLE public stablecoin;
    ERC20Mock public weth;
    MockEthOracle public ethOracle;
    CdpEngineHandler public handler;

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

        handler = new CdpEngineHandler(cdpEngine, stablecoin, weth, ethOracle);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreUSDValueThanSupply() public {
        // Get total supply of stablecoin
        uint256 totalSupply = stablecoin.totalSupply();

        // Get total protocol collateral value in USD
        uint256 totalCollateralValueInUsd = cdpEngine.getTotalCollateralValue();
        // Protocol total USD value should be greater than total supply
        assert(totalCollateralValueInUsd >= totalSupply);
    }
}
