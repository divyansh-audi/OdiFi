// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "@forge-std/Script.sol";
import {TimeLock} from "src/TimeLock.sol";
import {AuraPowerToken} from "src/AuraPowerToken.sol";
import {DiamondCutFacet} from "src/facets/DiamondCutFacet.sol";
import {GovernanceCoreFacet} from "src/facets/GovernanceCoreFacet.sol";
import {GovernanceTimelockFacet} from "src/facets/GovernanceTimelockFacet.sol";
import {GovernanceSettingsFacet} from "src/facets/GovernanceSettingsFacet.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {AutomationFund} from "src/AutomationFund.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {AuraGovernanceDiamond} from "src/AuraGovernanceDiamond.sol";
import {IDiamondCut} from "src/interfaces/IDiamondCut.sol";
import {LibDiamond} from "src/libraries/LibDiamond.sol";

contract DeployDiamondGovernance is Script {
    TimeLock timeLock;
    AuraPowerToken auraPowerToken;
    AuraGovernanceDiamond auraGovernanceDiamond;

    DiamondCutFacet diamondCutFacet;
    GovernanceCoreFacet governanceCoreFacet;
    GovernanceTimelockFacet governanceTimelockFacet;
    GovernanceSettingsFacet governanceSettingFacet;

    address[] proposers;
    address[] executors;

    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 50400;

    struct DeploymentAddresses {
        address governanceToken;
        address timelock;
        address diamond;
        address diamondCutFacet;
        address governanceCoreFacet;
        address governanceTimelockFacet;
        address governanceSettingsFacet;
    }

    function run()
        public
        returns (
            TimeLock,
            AuraPowerToken,
            GovernanceCoreFacet,
            GovernanceTimelockFacet,
            GovernanceSettingsFacet,
            DiamondCutFacet,
            AuraGovernanceDiamond
        )
    {
        DeploymentAddresses memory addresses;
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startBroadcast(config.defaultOwner);
        auraPowerToken = new AuraPowerToken();
        addresses.governanceToken = address(auraPowerToken);

        timeLock = new TimeLock(MIN_DELAY, proposers, executors);
        addresses.timelock = address(timeLock);

        diamondCutFacet = new DiamondCutFacet();
        addresses.diamondCutFacet = address(diamondCutFacet);

        auraGovernanceDiamond = new AuraGovernanceDiamond(address(config.defaultOwner), address(diamondCutFacet));
        addresses.diamond = address(auraGovernanceDiamond);

        governanceSettingFacet = new GovernanceSettingsFacet();
        addresses.governanceSettingsFacet = address(governanceSettingFacet);

        governanceTimelockFacet = new GovernanceTimelockFacet();
        addresses.governanceTimelockFacet = address(governanceTimelockFacet);

        governanceCoreFacet = new GovernanceCoreFacet();
        addresses.governanceCoreFacet = address(governanceCoreFacet);

        IDiamondCut.FacetCut[] memory cut = prepareFacetCuts(addresses);
        IDiamondCut(address(auraGovernanceDiamond)).diamondCut(cut, address(0), "");

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

        timeLock.grantRole(proposerRole, address(auraGovernanceDiamond));
        timeLock.grantRole(executorRole, address(auraGovernanceDiamond));

        timeLock.revokeRole(proposerRole, config.defaultOwner);
        timeLock.revokeRole(executorRole, config.defaultOwner);

        LibDiamond.setContractOwner(address(timeLock));
        timeLock.revokeRole(adminRole, config.defaultOwner);

        if (block.chainid != 31337) {
            address mostRecentlyDeployedEngine = DevOpsTools.get_most_recent_deployment("AuraEngine", block.chainid);
            AuraEngine(payable(mostRecentlyDeployedEngine)).transferOwnership(address(timeLock));

            address mostRecentlyDeployedAutomationFund =
                DevOpsTools.get_most_recent_deployment("AutomationFund", block.chainid);
            AutomationFund(payable(mostRecentlyDeployedAutomationFund)).transferOwnership(address(timeLock));
        }
        vm.stopBroadcast();
        return (
            timeLock,
            auraPowerToken,
            governanceCoreFacet,
            governanceTimelockFacet,
            governanceSettingFacet,
            diamondCutFacet,
            auraGovernanceDiamond
        );
    }

    function prepareFacetCuts(DeploymentAddresses memory addresses)
        internal
        pure
        returns (IDiamondCut.FacetCut[] memory cut)
    {
        bytes4[] memory coreSelectors = new bytes4[](9);
        coreSelectors[0] = GovernanceCoreFacet.initialize.selector;
        coreSelectors[1] = GovernanceCoreFacet.propose.selector;
        coreSelectors[2] = GovernanceCoreFacet.castVote.selector;
        coreSelectors[3] = GovernanceCoreFacet.castVoteWithReason.selector;
        coreSelectors[4] = GovernanceCoreFacet.state.selector;
        coreSelectors[5] = GovernanceCoreFacet.proposalThreshold.selector;
        coreSelectors[6] = GovernanceCoreFacet.quorum.selector;
        coreSelectors[7] = GovernanceCoreFacet.hashProposal.selector;
        coreSelectors[8] = GovernanceCoreFacet.getProposal.selector;

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: addresses.governanceCoreFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: coreSelectors
        });

        bytes4[] memory timelockSelectors = new bytes4[](2);
        timelockSelectors[0] = GovernanceTimelockFacet.queue.selector;
        timelockSelectors[1] = GovernanceTimelockFacet.execute.selector;

        cut[1] = IDiamondCut.FacetCut({
            facetAddress: addresses.governanceTimelockFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: timelockSelectors
        });

        bytes4[] memory settingsSelectors = new bytes4[](5);
        settingsSelectors[0] = GovernanceSettingsFacet.setVotingDelay.selector;
        settingsSelectors[1] = GovernanceSettingsFacet.setVotingPeriod.selector;
        settingsSelectors[2] = GovernanceSettingsFacet.setProposalThreshold.selector;
        settingsSelectors[3] = GovernanceSettingsFacet.votingDelay.selector;
        settingsSelectors[4] = GovernanceSettingsFacet.votingPeriod.selector;

        cut[2] = IDiamondCut.FacetCut({
            facetAddress: addresses.governanceSettingsFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: settingsSelectors
        });
    }
}
