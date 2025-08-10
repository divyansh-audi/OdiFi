// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "@forge-std/Script.sol";
import {AuraGovernor} from "src/AuraGovernor.sol";
import {AuraPowerToken} from "src/AuraPowerToken.sol";
import {TimeLock} from "src/TimeLock.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {AuraEngine} from "src/AuraEngine.sol";

contract DeployAuraGovernor is Script {
    TimeLock timeLock;
    AuraGovernor auraGovernor;
    AuraPowerToken auraPowerToken;

    address[] proposers;
    address[] executors;

    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 50400;

    function run() public returns (TimeLock, AuraGovernor, AuraPowerToken) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.defaultOwner);
        auraPowerToken = new AuraPowerToken();
        timeLock = new TimeLock(MIN_DELAY, proposers, executors);
        auraGovernor = new AuraGovernor(auraPowerToken, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.DEFAULT_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(auraGovernor));
        timeLock.grantRole(executorRole, address(0));
        timeLock.revokeRole(adminRole, config.defaultOwner);

        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("AuraEngine", block.chainid);
        AuraEngine(payable(mostRecentlyDeployed)).transferOwnership(address(timeLock));
        vm.stopBroadcast();
        return (timeLock, auraGovernor, auraPowerToken);
    }
}
