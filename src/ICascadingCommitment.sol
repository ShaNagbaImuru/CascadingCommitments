// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

struct CommitmentForUser {
    uint256 triggersAt;
    uint256 size;
    uint256 id;
}

/**
@title A tool for conditional commitments.
@notice Cascading commitments are a tool to allow people to register a commitment to do something only if enough other people also participate.
@dev uint128 is used throughout for commitment sizes, trigger levels, and native currency, to allow for space savings.
 */
interface ICascadingCommitment {
    /**
    @notice Register a commitment to perform some action given enough collective commitment to that action. NOTE: This function requires payment, for later gas if nothing else.
    @param triggersAt The total commitment size at which the user commits to acting. NOTE: this includes the user's commitment, i.e., the user commits to act when their action would bring the total to this level, not once this level is reached entirely by others.
    @param commitmentSize The size of the commitment being made.
    */
    function addCommitment(uint128 triggersAt, uint128 commitmentSize) external payable;
    /**
    @notice Withdraw a previously registered commitment that has not yet been acted upon.
    @param id The id of the commitment to withdraw, obtained from a call to commitments().
    */
    function withdrawCommitment(uint256 id) external;
    /**
    @notice Triggers all commitments that share one or more trigger levels, causing them to be acted upon and thus no longer withdrawable. NOTE: anyone can call this, and the expectation is that the decision of which levels to trigger will be calculated offline based on event logs. This function reimburses the caller for gas at a rate established when the contract is created.
    @param levels The list of trigger levels ('triggersAt' param to addCommitment()) to fire. Must be monotonically ascending, but is not required to include the lowest possible levels (though this is preferred).
    */
    function trigger(uint128[] calldata levels) external;
    /// @notice The total size, against which trigger levels are compared.
    function currentSizeTotal() external view returns (uint128);
    /// @notice The list of commitments registered by this user that have not yet been acted upon.
    function commitments() external view returns (CommitmentForUser[] memory);
    /**
    @notice For a commitment of a given size, the native currency that is required to reimburse gas fees when processing that commitment.
    @param size The size of the commitment.
    */
    function nativeCurrencyReservedForCommitmentGas(uint128 size) external returns (uint128);
}

/**
@title A tool for conditional commitments when the total size of accepted commitments is limited.
@notice Cascading commitments when the total size accepted is limited.
*/
interface ICascadingCommitmentWithSizeLimit is ICascadingCommitment {
    /// @notice The total size of commitments that can be accepted.
    function maxSizeTotal() external view returns (uint128);
    /// @notice Whether the max has been reached, and thus only withdrawals are now allowed.
    function stopped() external view returns (bool);
}
