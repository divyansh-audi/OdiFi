// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "@forge-std/Script.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {AuraCoin} from "src/AuraCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AutomationFund} from "../src/AutomationFund.sol";

contract DeployAuraEngine is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    AuraCoin public auraCoin;
    AuraEngine public auraEngine;
    AutomationFund public automationFund;

    uint256 public INITIAL_FUNDING_TO_AUTOMATION_FUND = 20000000 ether; //2,00,00,000 INR

    function run() public returns (AuraCoin, AuraEngine, HelperConfig, AutomationFund) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        tokenAddresses = [config.token];
        priceFeedAddresses = [config.priceFeed];
        // console2.log("weth in deployment:", config.weth);
        vm.startBroadcast(config.defaultOwner);
        auraCoin = new AuraCoin();
        automationFund = new AutomationFund();
        auraCoin.mint(address(automationFund), INITIAL_FUNDING_TO_AUTOMATION_FUND);
        auraEngine = new AuraEngine(tokenAddresses, priceFeedAddresses, auraCoin, config.defaultOwner, automationFund);
        auraCoin.transferOwnership(address(auraEngine));
        vm.stopBroadcast();

        return (auraCoin, auraEngine, helperConfig, automationFund);
    }
}
