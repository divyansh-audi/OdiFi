// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "@forge-std/Script.sol";
import {AuraGovernor} from "src/AuraGovernor.sol";
import {AuraPowerToken} from "src/AuraPowerToken.sol";
import {TimeLock} from "src/TimeLock.sol";
import {AuraGovernanceDiamond} from "../src/AuraGovernanceDiamond.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {AutomationFund} from "src/AutomationFund.sol";

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

        /**
         * The Proposer role is in charge of queueing operations ,it should be only and only granted to the governor contract.
         */
        bytes32 proposerRole = timeLock.PROPOSER_ROLE();

        /**
         * this is in charge of executing already available operations,and it should be assigned to address(0) which means that anyone can execute .
         */
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();

        /**
         * Admin Role is a very sensitive role which should be assign only to the timelock itself as it inclues the granting and revoking of the two previous roles.
         */
        bytes32 adminRole = timeLock.DEFAULT_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(auraGovernor));
        timeLock.grantRole(executorRole, address(0));
        timeLock.revokeRole(adminRole, config.defaultOwner);

        if (block.chainid != 31337) {
            address mostRecentlyDeployedEngine = DevOpsTools.get_most_recent_deployment("AuraEngine", block.chainid);
            AuraEngine(payable(mostRecentlyDeployedEngine)).transferOwnership(address(timeLock));

            address mostRecentlyDeployedAutomationFund =
                DevOpsTools.get_most_recent_deployment("AutomationFund", block.chainid);
            AutomationFund(payable(mostRecentlyDeployedAutomationFund)).transferOwnership(address(timeLock));
        }
        vm.stopBroadcast();
        return (timeLock, auraGovernor, auraPowerToken);
    }
}
