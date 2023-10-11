// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRelayFactory {
    error TokenIdNotApproved();
    error TokenIdNotManaged();
    error SameRegistry();
    error ZeroAddress();
    error TokenIdZero();
    error HighLiquidityTokenAlreadyExists();
    error AmountOutOfAcceptableRange();
    error AmountSame();

    event CreateRelay(address indexed _from, address indexed _admin, string _name, address _relay);
    event SetKeeperRegistry(address indexed _keeperRegistry);
    event AddHighLiquidityToken(address indexed _token);

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

    /// @notice Register a token address with high liquidity
    ///         Callable by Owner
    /// @dev Once an address is added, it cannot be removed
    /// @param _token Address of token to register
    function addHighLiquidityToken(address _token) external;

    /// @notice View if an address is registered as a high liquidity token
    ///         This indicates a token has significant liquidity to swap route into VELO
    ///         If a token address returns true, it cannot be swept from an AutoCompounder
    /// @param _token Address of token to query
    /// @return True if token is registered as a high liquidity token, else false
    function isHighLiquidityToken(address _token) external view returns (bool);

    /// @notice View for all registered high liquidity tokens
    /// @return Array of high liquidity tokens
    function highLiquidityTokens() external view returns (address[] memory);

    /// @notice Get the count of registered high liquidity tokens
    /// @return Count of registered high liquidity tokens
    function highLiquidityTokensLength() external view returns (uint256);
}
