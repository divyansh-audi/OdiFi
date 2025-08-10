// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "@forge-std/Script.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {AuraCoin} from "src/AuraCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployAuraEngine is Script {
    AuraCoin public auraCoin;
    AuraEngine public auraEngine;

    function run() public {
        deployAuraEngine();
    }

    function deployAuraEngine() public returns (AuraCoin, AuraEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.defaultOwner);
        auraCoin = new AuraCoin();
        auraEngine = new AuraEngine(auraCoin, config.weth, config.ethUSDPriceFeed, config.defaultOwner);
        vm.stopBroadcast();
        return (auraCoin, auraEngine, helperConfig);
    }
}
