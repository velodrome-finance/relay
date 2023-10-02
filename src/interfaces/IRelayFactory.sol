// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRelayFactory {
    error TokenIdNotApproved();
    error TokenIdNotManaged();
    error SameRegistry();
    error ZeroAddress();
    error TokenIdZero();

    event CreateRelay(address indexed _from, address indexed _admin, string _name, address _relay);
    event SetKeeperRegistry(address indexed _keeperRegistry);

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

    /// @notice Set a new Keeper Registry to be used
    /// @param _keeperRegistry      address of the new Keeper Registry
    function setKeeperRegistry(address _keeperRegistry) external;

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

    /// @notice View if an address is an approved keeper
    /// @param _keeper Address of keeper queried
    /// @return True if keeper, else false
    function isKeeper(address _keeper) external view returns (bool);
}
