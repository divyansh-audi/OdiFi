// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {AuraCoin} from "src/AuraCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink-brownie/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
// import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @dev Always follow the CEI method while writing any function -->
 * -Check
 * -Effects (updating the state)
 * -Interactions
 *
 * @title AuraEngine
 * @author Divyansh Audichya
 * @notice This Engine will be the Owner of the AuraCoin contract .
 *
 * The system is designed to keep the price of 1 Aura token == `₹1` ( i.e. 1 INR).
 *
 * The stableCoin has the properties :
 * - Exogenous Collateral(Eth)
 * - Algorithmically Stable
 * - INR Pegged
 *
 * The system should always be `over collateralized`
 *
 * @notice This is the core contract for the AuraCoin Contract and is responsible for all kind of collateral deposits, minting and Burning of tokens .
 */
contract AuraEngine is ReentrancyGuard {
    /*///////////////////////////////////////
                   ERRORS
    ///////////////////////////////////////*/

    error AuraEngine__MustBeMoreThanZero();
    error AuraEngine__CollateralNotDeposited();
    error AuraEngine__MintingFailed();
    error AuraEngine__HealthFactorBroken();

    /*///////////////////////////////////////
                    TYPES
    ///////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*///////////////////////////////////////
                STATE VARIABLES
    ///////////////////////////////////////*/

    AuraCoin immutable i_auraCoin;
    address immutable i_wethAddress;
    address immutable i_ethINRPriceFeed;

    mapping(address user => uint256 amountDepositedInEth) s_userToCollateralDepositedInEth;
    mapping(address user => uint256 tokensMinted) s_userToAuraCoinMinted;

    uint8 constant THRESHOLD_HEALTH_FACTOR = 2;
    uint256 constant PRECISION_FACTOR = 1e18;
    uint256 constant PRECISION_PRICE_FEED = 1e10;

    /*///////////////////////////////////////
                     EVENTS
    ///////////////////////////////////////*/

    event CollateralDeposited(address indexed sender, uint256 indexed amountDepositedAsCollateral);

    /*///////////////////////////////////////
                   MODIFIER
    ///////////////////////////////////////*/
    modifier collateralMustBeMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert AuraEngine__MustBeMoreThanZero();
        }
        _;
    }

    /*///////////////////////////////////////
                   FUNCTIONS
    ///////////////////////////////////////*/

    constructor(AuraCoin auraCoin, address weth, address ethINRPriceFeed) {
        i_auraCoin = auraCoin;
        i_wethAddress = weth;
        i_ethINRPriceFeed = ethINRPriceFeed;
    }

    receive() external payable {}

    /*///////////////////////////////////////
              EXTERNAL FUNCTIONS
    ///////////////////////////////////////*/
    /**
     * This function will do two things -->
     * 1. Deposit the collateral
     * 2. Mint the AuraCoin Based on collateral deposited
     * @param _amountOfCollateralToDepositInEth Amount to deposit as collateral In Eth
     */
    function depositCollateralAndMintAura(uint256 _amountOfCollateralToDepositInEth, uint256 _amountAuraToMint)
        external
    {
        _depositCollateral(_amountOfCollateralToDepositInEth);
        _mintAuraCoin(_amountAuraToMint);
    }

    function redeemCollateralAndBurnAura() public {}
    function liquidate() public {}
    function checkUpkeep() external {}
    function performUpKeep() external {}

    /*///////////////////////////////////////
              INTERNAL FUNCTIONS
    ///////////////////////////////////////*/
    /**
     * This function will deposit collateral to this AuraEngine contract .
     * @param _amountInEth Amount of collateral in ETH
     * @notice In this function the state is first updated to ensure safety and re-entrency safety .
     */
    function _depositCollateral(uint256 _amountInEth)
        internal
        collateralMustBeMoreThanZero(_amountInEth)
        nonReentrant
    {
        s_userToCollateralDepositedInEth[msg.sender] = _amountInEth;
        emit CollateralDeposited(msg.sender, _amountInEth);
        bool success = IERC20(i_wethAddress).transferFrom(msg.sender, address(this), _amountInEth);
        if (!success) {
            revert AuraEngine__CollateralNotDeposited();
        }
    }

    /**
     * This function will mint AuraCoin .
     * @param _amountAuraToMint Amount of Aura to mint after depositing collateral
     * @notice In this function the state is first updated to ensure safety and re-entrency safety .
     */
    function _mintAuraCoin(uint256 _amountAuraToMint)
        internal
        collateralMustBeMoreThanZero(_amountAuraToMint)
        nonReentrant
    {
        s_userToAuraCoinMinted[msg.sender] += _amountAuraToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_auraCoin.mint(msg.sender, _amountAuraToMint);
        if (!success) {
            revert AuraEngine__MintingFailed();
        }
    }

    /**
     * @dev THRESHOLD_HEALTH_FACTOR is uint8 and when multiplied by uint256 returns uint256.
     */
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 healthFactor = getHealthFactor(_user);
        if (healthFactor < THRESHOLD_HEALTH_FACTOR * PRECISION_FACTOR) {
            revert AuraEngine__HealthFactorBroken();
        }
    }

    /**
     * @dev This one is bit tricky:
     *
     * Example->
     * ALICE-->2 eth==> 2*1e18 1 eth== 1000INR*1e18*2(getINRforETH)
     *         500*1e18
     *         healthFactor=2000e18*1e18/500e18=>4 e18
     *
     * @dev in order to not losse precision ,we can't return healthFactor in uint8 as then if suppose there is something like 2000/700,it will losse precision
     * @param _user User for which the health factor is being checked.
     * @return uint256 it returns 4 * 1e18 in case of above example.
     */
    function getHealthFactor(address _user) public view returns (uint256) {
        uint256 collateralDepositedInEth = getCollateralDepositedByUsers(_user);
        uint256 amountOfAuraCoinMintedInINR = getAuraCoinMintedByUsers(_user);
        uint256 collateralDepositedInINR = getINRforEth(collateralDepositedInEth);

        uint256 healthFactor = collateralDepositedInINR * PRECISION_FACTOR / amountOfAuraCoinMintedInINR;
        return healthFactor;
    }

    /**
     * @param _amountInEth Amount in ETH to convert in INR
     * @return uint256 if _amountInEth = 2 ether and price of 1 eth in INR is 1000INR, then this returns 2000*1e18;
     */
    function getINRforEth(uint256 _amountInEth) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(getEthInrPriceFeed());
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData(); // this return value in 8 decimal places ,we need to add 10 more
        uint256 adjustedPrice = uint256(price) * PRECISION_PRICE_FEED;
        uint256 finalValue = adjustedPrice * _amountInEth / PRECISION_FACTOR;
        return finalValue;
    }

    /*///////////////////////////////////////
              GETTER FUNCTIONS
    ///////////////////////////////////////*/
    /**
     * @return address Address of the AuraCoin Contract
     */
    function getAuraCoinAddress() public view returns (address) {
        return address(i_auraCoin);
    }

    /**
     * @return address Address of WethToken
     */
    function getWethTokenAddress() public view returns (address) {
        return i_wethAddress;
    }

    /**
     * @return address Address for ETH/INR price feed.
     */
    function getEthInrPriceFeed() public view returns (address) {
        return i_ethINRPriceFeed;
    }

    /**
     * @param _user User to know how much collateral to deposit
     * @return uint256 Amount of collateral deposit by the `_user`.
     */
    function getCollateralDepositedByUsers(address _user) public view returns (uint256) {
        return s_userToCollateralDepositedInEth[_user];
    }

    /**
     * @param _user User to know how much collateral to deposit
     * @return uint256 Amount of AuraCoin minited by the `_user`.
     */
    function getAuraCoinMintedByUsers(address _user) public view returns (uint256) {
        return s_userToAuraCoinMinted[_user];
    }
}
