// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuraAirdrop} from "src/AuraAirdrop.sol";
import {Script} from "@forge-std/Script.sol";
import {AuraPowerToken} from "src/AuraPowerToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {TimeLock} from "src/TimeLock.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployAuraAirdrop is Script {
    AuraAirdrop auraAirdrop;
    TimeLock timeLock;
    bytes32 constant MERKLE_ROOT = 0xdef7050d26c38d24eb6a8ae026530ed4bf0eb5c189e14cd3b13d342dc345e7de;
    AuraPowerToken airDropToken;
    address mostRecentlyDeployedPowerToken;
    address mostRecentlyDeployedTimeLock;

    uint256 constant AMOUNT_TO_MINT_AIRDROP = 100 ether;
    address[] proposers;
    address[] executors;
    uint256 public constant MIN_DELAY = 3600;

    function run() external returns (AuraAirdrop, AuraPowerToken) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startBroadcast(config.defaultOwner);
        if (block.chainid != 31337) {
            mostRecentlyDeployedPowerToken = DevOpsTools.get_most_recent_deployment("AuraPowerToken", block.chainid);
            mostRecentlyDeployedTimeLock = DevOpsTools.get_most_recent_deployment("TimeLock", block.chainid);
        } else {
            airDropToken = new AuraPowerToken(config.defaultOwner);
            mostRecentlyDeployedPowerToken = address(airDropToken);
            timeLock = new TimeLock(MIN_DELAY, proposers, executors);
            mostRecentlyDeployedTimeLock = address(timeLock);
        }
        auraAirdrop = new AuraAirdrop(MERKLE_ROOT, mostRecentlyDeployedPowerToken);

        AuraPowerToken(mostRecentlyDeployedPowerToken).mint(address(auraAirdrop), AMOUNT_TO_MINT_AIRDROP);
        AuraPowerToken(mostRecentlyDeployedPowerToken).grantRole(
            AuraPowerToken(mostRecentlyDeployedPowerToken).DEFAULT_ADMIN_ROLE(), address(mostRecentlyDeployedTimeLock)
        );
        AuraPowerToken(mostRecentlyDeployedPowerToken).grantRole(
            AuraPowerToken(mostRecentlyDeployedPowerToken).MINTER_ROLE(), address(mostRecentlyDeployedTimeLock)
        );
        AuraPowerToken(mostRecentlyDeployedPowerToken).renounceRole(
            AuraPowerToken(mostRecentlyDeployedPowerToken).DEFAULT_ADMIN_ROLE(), config.defaultOwner
        );
        AuraPowerToken(mostRecentlyDeployedPowerToken).renounceRole(
            AuraPowerToken(mostRecentlyDeployedPowerToken).MINTER_ROLE(), config.defaultOwner
        );

        vm.stopBroadcast();
        return (auraAirdrop, AuraPowerToken(mostRecentlyDeployedPowerToken));
    }
}
