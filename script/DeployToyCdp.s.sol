// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ToyCDPEngine} from "../src/ToyCDPEngine.sol";
import {STABLE} from "../src/STABLE.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockEthOracle} from "../src/libraries/MockEthOracle.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DeployCdpEngine is Script {
    function run()
        public
        returns (IERC20, STABLE, MockEthOracle, ToyCDPEngine)
    {
        vm.startBroadcast();

        // Deploy mock WETH token
        ERC20Mock weth = new ERC20Mock();

        // Deploy stablecoin
        STABLE stablecoin = new STABLE();

        // Deploy price oracle
        MockEthOracle ethOracle = new MockEthOracle();

        // Deploy CDP engine
        ToyCDPEngine cdpEngine = new ToyCDPEngine(
            address(stablecoin),
            address(weth),
            address(ethOracle)
        );

        // Transfer stablecoin ownership to CDP engine
        stablecoin.transferOwnership(address(cdpEngine));

        vm.stopBroadcast();

        return (weth, stablecoin, ethOracle, cdpEngine);

        /*console.log("Deployed WETH at:", address(weth));
        console.log("Deployed STABLE at:", address(stablecoin));
        console.log("Deployed ETH Oracle at:", address(ethOracle));
        console.log("Deployed CDP Engine at:", address(cdpEngine)); */
    }
}
