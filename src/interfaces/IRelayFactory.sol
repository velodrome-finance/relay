// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRelayFactory {
    error KeeperAlreadyExists();
    error KeeperDoesNotExist();
    error TokenIdNotApproved();
    error TokenIdNotManaged();
    error ZeroAddress();
    error TokenIdZero();
    error NotTeam();

    event AddKeeper(address indexed _keeper);
    event RemoveKeeper(address indexed _keeper);
    event CreateRelay(address indexed _from, address indexed _admin, string _name, address _relay);

    /// @notice Create a Relay for a (m)veNFT
    /// @param _admin       Admin address to set slippage tolerance / manage ALLOWED_CALLER
    /// @param _mTokenId    Unique identifier of the managed veNFT
    /// @param _name        Name of the Relay
    function createRelay(
        address _admin,
        uint256 _mTokenId,
        string calldata _name,
        bytes calldata _data
    ) external returns (address);

    /// @notice Add an authorized keeper to call `Relay.claimXAndCompoundKeeper()`
    ///         Callable by FactoryRegistry.owner()
    /// @param _keeper Address of keeper to approve
    function addKeeper(address _keeper) external;

    /// @notice Remove an authorized keeper from calling `Relay.claimXAndCompoundKeeper()`
    ///         Callable by FactoryRegistry.owner()
    /// @param _keeper Address of keeper to remove
    function removeKeeper(address _keeper) external;

    /// @notice View for all approved keepers
    /// @return Array of keepers
    function keepers() external view returns (address[] memory);

    /// @notice View if an address is an approved keeper
    /// @param _keeper Address of keeper queried
    /// @return True if keeper, else false
    function isKeeper(address _keeper) external view returns (bool);

    /// @notice Get the count of approved keepers
    /// @return Count of approved keepers
    function keepersLength() external view returns (uint256);

    /// @notice View for all created Relays
    /// @return Array of Relays
    function relays() external view returns (address[] memory);

    /// @notice View for an address is an Relay contract created by this factory
    /// @param _relay Address of Relay queried
    /// @return True if Relay, else false
    function isRelay(address _relay) external view returns (bool);

    /// @notice Get the count of created Relays
    /// @return Count of created Relays
    function relaysLength() external view returns (uint256);
}
