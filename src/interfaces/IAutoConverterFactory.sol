// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAutoConverterFactory {
    error NotTeam();
    error KeeperAlreadyExists();
    error KeeperDoesNotExist();
    error TokenIdNotApproved();
    error TokenIdNotManaged();
    error TokenIdZero();
    error ZeroAddress();

    event AddKeeper(address indexed _keeper);
    event CreateAutoConverter(address indexed _from, address indexed _admin, string _name, address _autoConverter);
    event RemoveKeeper(address indexed _keeper);

    /// @notice Create an AutoConverter for a (m)veNFT
    /// @param _admin       Admin address to set slippage tolerance / manage ALLOWED_CALLER
    /// @param _mTokenId    Unique identifier of the managed veNFT
    /// @param _name        Name of the autoConverter
    /// @param _token       Address of token to convert into
    function createAutoConverter(
        address _admin,
        uint256 _mTokenId,
        string calldata _name,
        address _token
    ) external returns (address autoConverter);

    /// @notice Add an authorized keeper to call `AutoConverter.claimXAndConvertKeeper()`
    ///         Callable by FactoryRegistry.owner()
    /// @param _keeper Address of keeper to approve
    function addKeeper(address _keeper) external;

    /// @notice Remove an authorized keeper from calling `AutoConverter.claimXAndConvertKeeper()`
    ///         Callable by FactoryRegistry.owner()
    /// @param _keeper Address of keeper to remove
    function removeKeeper(address _keeper) external;

    /// @notice View if an address is an approved keeper
    /// @param _keeper Address of keeper queried
    /// @return True if keeper, else false
    function isKeeper(address _keeper) external view returns (bool);

    /// @notice View for all approved keepers
    /// @return Array of keepers
    function keepers() external view returns (address[] memory);

    /// @notice Get the count of approved keepers
    /// @return Count of approved keepers
    function keepersLength() external view returns (uint256);

    /// @notice View for all created AutoConverters
    /// @return Array of AutoConverters
    function autoConverters() external view returns (address[] memory);

    /// @notice Get the count of created AutoConverters
    /// @return Count of created AutoConverters
    function autoConvertersLength() external view returns (uint256);

    /// @notice View for an address is an AutoConverter contract created by this factory
    /// @param _autoConverter Address of AutoConverter queried
    /// @return True if AutoConverter, else false
    function isAutoConverter(address _autoConverter) external view returns (bool);
}
