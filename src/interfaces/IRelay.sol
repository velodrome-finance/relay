// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRelay {
    /// @notice Error during keeper functions if sender is not Keeper
    error NotKeeper();
    /// @notice General error if one call in the multicall fails
    error MulticallFailed();
    /// @notice Error during initialize() if the (m)tokenId is not a managed veNFT
    error TokenIdNotManaged();
    /// @notice Error during initialize() if the (m)tokenID is not owned by the Relay
    error ManagedTokenNotOwned();

    /// @notice Get the name of the Relay
    function name() external view returns (string memory);

    /// @notice Get the Managed veNFT tokenId owned by the Relay
    function mTokenId() external view returns (uint256);

    /// @notice Address of token to convert into
    function token() external view returns (address);

    /// @notice Initialize the Relay by setting the (m)tokenId within the contract
    /// @dev The (m)tokenId must be owned by the Relay to initialize
    /// @param _mTokenId Unique identifier of the managed veNFT
    function initialize(uint256 _mTokenId) external;

    // -------------------------------------------------
    // Basic functions
    // -------------------------------------------------

    /// @notice Refer to IVoter.claimBribes.  Also claims rebases if available.
    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens) external;

    /// @notice Refer to IVoter.claimFees.  Also claims rebases if available.
    function claimFees(address[] calldata _fees, address[][] calldata _tokens) external;

    /// @notice Multicall the relay to trigger multiple actions in one contract call
    function multicall(bytes[] calldata _calls) external;

    // -------------------------------------------------
    // ALLOWED_CALLER functions
    // -------------------------------------------------

    /// @notice Additional functionality for ALLOWED_CALLER to deposit more VELO into the managed tokenId.
    ///         This is effectively a bribe bonus for users that deposited into the Relay.
    /// @dev Refer to IVoter.increaseAmount()
    function increaseAmount(uint256 _value) external;

    /// @notice Vote for Velodrome pools with the given weights.
    ///         Only callable by ALLOWED_CALLER.
    /// @dev Refer to IVoter.vote()
    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external;
}
