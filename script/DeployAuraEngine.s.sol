// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "@forge-std/Script.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {AuraCoin} from "src/AuraCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployAuraEngine is Script {
    AuraCoin public auraCoin;
    AuraEngine public auraEngine;

    function run() public returns (AuraCoin, AuraEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        // console2.log("weth in deployment:", config.weth);
        vm.startBroadcast(config.defaultOwner);
        auraCoin = new AuraCoin();
        auraEngine = new AuraEngine(auraCoin, config.weth, config.ethUSDPriceFeed, config.defaultOwner);
        auraCoin.transferOwnership(address(auraEngine));
        vm.stopBroadcast();

        return (auraCoin, auraEngine, helperConfig);
    }
}
