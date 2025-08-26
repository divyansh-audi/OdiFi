// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {LibGovernanceStorage} from "../libraries/LibGovernanceStorage.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/**
 * @title GovernanceSettingsFacet
 * @author Divyansh Audichya
 * @notice This contract is same as the GovernanceSetting from OpenZeppelin's GovernanceSetting Contract..Almost the same functionlity
 */
contract GovernanceSettingsFacet {
    using LibGovernanceStorage for LibGovernanceStorage.GovernanceStorage;

    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);

    function setVotingDelay(uint256 newVotingDelay) public {
        LibDiamond.enforceIsContractOwner();
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();

        emit VotingDelaySet(gs.votingDelay, newVotingDelay);
        gs.votingDelay = newVotingDelay;
    }

    function setVotingPeriod(uint256 newVotingPeriod) public {
        LibDiamond.enforceIsContractOwner();
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();

        emit VotingPeriodSet(gs.votingPeriod, newVotingPeriod);
        gs.votingPeriod = newVotingPeriod;
    }

    function setProposalThreshold(uint256 newProposalThreshold) public {
        LibDiamond.enforceIsContractOwner();
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();

        emit ProposalThresholdSet(gs.proposalThreshold, newProposalThreshold);
        gs.proposalThreshold = newProposalThreshold;
    }

    function votingDelay() public view returns (uint256) {
        return LibGovernanceStorage.governanceStorage().votingDelay;
    }

    function votingPeriod() public view returns (uint256) {
        return LibGovernanceStorage.governanceStorage().votingPeriod;
    }

    function proposalThreshold() public view returns (uint256) {
        return LibGovernanceStorage.governanceStorage().proposalThreshold;
    }
}
