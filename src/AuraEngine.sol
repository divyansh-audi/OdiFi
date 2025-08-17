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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console2} from "forge-std/console2.sol";
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
 *
 * @notice There are some onlyOwner functions which is for governance purpose and the community can propose for the changes ,basically someone will propose a change ,voting will happen and then Governor will tell the Timelock contract to change that thing in this contract ,so after deploying ,the ownership of this should be sent to TimeLock Contract.
 */
contract AuraEngine is ReentrancyGuard, Ownable {
    /*///////////////////////////////////////
                   ERRORS
    ///////////////////////////////////////*/

    error AuraEngine__MustBeMoreThanZero();
    error AuraEngine__CollateralNotDeposited();
    error AuraEngine__MintingFailed();
    error AuraEngine__HealthFactorBroken();
    error AuraEngine__CollateralNotRedeemed();
    error AuraEngine__HealthFactorAlreadyGood();
    error DSCEngine__HealthFactorNotImproved();
    error AuraEngine__ProtocolWillBreakIfBonusIsTooMuch();
    error AuraEngine__OverCollateralizationNotValid();
    error AuraEngine__TokenNotAllowedAsCollateral();
    error AuraEngine__TokenAlreadyAllowed();
    error DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();

    /*///////////////////////////////////////
                    TYPES
    ///////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*///////////////////////////////////////
                STATE VARIABLES
    ///////////////////////////////////////*/

    AuraCoin private immutable i_auraCoin;
    address[] public s_collateralTokens;

    // address private immutable i_wethAddress;
    // address private immutable i_ethUSDPriceFeed;
    // address private immutable i_timeLockContract;
    // mapping(address user => uint256 amountDepositedInEth) s_userToCollateralDepositedInEth;

    mapping(address collateralAddress => address collateralPriceFeedAddress) public s_collateralToPriceFeed;
    mapping(address user => mapping(address collateralToken => uint256 amount)) public s_collateralDeposited;
    mapping(address user => uint256 tokensMinted) s_userToAuraCoinMinted;

    uint8 private constant USD_INR_PRICE = 85; // because of unavailability of inr priice feeds directly ,this will be usd *85--> almost equivalent to INR
    uint8 private THRESHOLD_HEALTH_FACTOR = 20;
    uint8 private constant THRESHOLD_HEALTH_FACTOR_PRECISION = 10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private constant PRECISION_PRICE_FEED = 1e10;
    uint256 private LIQUIDATION_BONUS = 10e18;
    uint256 private constant LIQUIDATION_PRECISION = 100e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /*///////////////////////////////////////
                     EVENTS
    ///////////////////////////////////////*/

    event CollateralDeposited(
        address indexed from, address indexed collateralToken, uint256 indexed amountDepositedAsCollateral
    );
    event CollateralReedemed(
        address indexed user, address to, address indexed collateralToken, uint256 indexed amountRedeemed
    );

    /*///////////////////////////////////////
                   MODIFIER
    ///////////////////////////////////////*/
    modifier mustBeMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert AuraEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedCollateral(address _token) {
        if (s_collateralToPriceFeed[_token] == address(0)) {
            revert AuraEngine__TokenNotAllowedAsCollateral();
        }
        _;
    }

    /*///////////////////////////////////////
                   FUNCTIONS
    ///////////////////////////////////////*/

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, AuraCoin auraCoin, address owner)
        Ownable(owner)
    {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_collateralToPriceFeed[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_auraCoin = auraCoin;
        // i_wethAddress = weth;
        // i_ethUSDPriceFeed = ethUSDPriceFeed;
        // i_timeLockContract = timeLockContractAddress;
    }

    receive() external payable {}

    /*///////////////////////////////////////
              EXTERNAL FUNCTIONS
    ///////////////////////////////////////*/
    /**
     * This function will do two things -->
     * 1. Deposit the collateral
     * 2. Mint the AuraCoin Based on collateral deposited
     * @param _collateralToken The address of the collateral token being deposited.
     * @param _amountOfCollateralToDeposit Amount of the collateral token to deposit.
     * @param _amountAuraToMint Amount of AuraCoin to mint.
     */
    function depositCollateralAndMintAura(
        address _collateralToken,
        uint256 _amountOfCollateralToDeposit,
        uint256 _amountAuraToMint
    ) external {
        _depositCollateral(_collateralToken, _amountOfCollateralToDeposit);
        _mintAuraCoin(_amountAuraToMint);
    }

    /**
     * @dev This function is calling the public functions burnAura and redeemCollateral
     */
    function redeemCollateralAndBurnAura(
        address _collateralToken,
        uint256 _amountOfCollateralToRedeem,
        uint256 _amountAuraToBurn
    ) public {
        burnAura(_amountAuraToBurn);
        redeemCollateral(_collateralToken, _amountOfCollateralToRedeem);
    }

    /**
     * @dev This functions redeems collatercal and check for the health factor after that
     * @param _amountOfCollateralToRedeem Amount of collateral which the msg.sender wants to redeem
     * @param _collateralToken The address of the collateral token to redeem.
     */
    function redeemCollateral(address _collateralToken, uint256 _amountOfCollateralToRedeem)
        public
        nonReentrant
        mustBeMoreThanZero(_amountOfCollateralToRedeem)
        isAllowedCollateral(_collateralToken)
    {
        _redeemCollateral(msg.sender, msg.sender, _collateralToken, _amountOfCollateralToRedeem);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev This call the internal burnAura function and then checks the health Factor which would never gonna hit ..
     * @param _amountAuraToBurn Amount of AuraToken to be burn and then you can claim collateral
     */
    function burnAura(uint256 _amountAuraToBurn) public mustBeMoreThanZero(_amountAuraToBurn) {
        _burnAura(msg.sender, msg.sender, _amountAuraToBurn);
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param _userToLiquidate The user which is getting liquidated
     *  @param _collateralToSeize The collateral token the liquidator will receive.
     * @param _debtToCover Amount of debt liquidator wants to cover
     */
    function liquidate(address _userToLiquidate, address _collateralToSeize, uint256 _debtToCover)
        external
        mustBeMoreThanZero(_debtToCover)
        nonReentrant
        isAllowedCollateral(_collateralToSeize)
    {
        uint256 startingHealthFactor = getHealthFactorByUserAddressInProtocol(_userToLiquidate);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert AuraEngine__HealthFactorAlreadyGood();
        }

        // The amount of collateral (in its own units) equivalent to the debt being covered.
        uint256 amountOfCollateralToCoverDebt = getTokensForINR(_collateralToSeize, _debtToCover);

        uint256 bonusCollateral = (amountOfCollateralToCoverDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = amountOfCollateralToCoverDebt + bonusCollateral;

        _redeemCollateral(_userToLiquidate, msg.sender, _collateralToSeize, totalCollateralToRedeem);
        _burnAura(_userToLiquidate, msg.sender, _debtToCover);

        uint256 endingUserHealthFactor = getHealthFactorByUserAddressInProtocol(_userToLiquidate);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function checkUpkeep() external {}
    function performUpKeep() external {}

    /*///////////////////////////////////////
              INTERNAL FUNCTIONS
    ///////////////////////////////////////*/

    /**
     * @dev This function is doing the low level calls and is compatible if someone else want to liquaidate a user
     *
     * @param _from The guy who has submitted the collateral
     * @param _to address which wants claim the collateral
     * @param _collateralToken The address of the collateral token.
     * @param _amountOfCollateralToRedeem amount of collateral to redeem
     */
    function _redeemCollateral(
        address _from,
        address _to,
        address _collateralToken,
        uint256 _amountOfCollateralToRedeem
    ) internal {
        s_collateralDeposited[_from][_collateralToken] -= _amountOfCollateralToRedeem;
        emit CollateralReedemed(_from, _to, _collateralToken, _amountOfCollateralToRedeem);
        bool success = IERC20(_collateralToken).transfer(_to, _amountOfCollateralToRedeem);
        if (!success) {
            revert AuraEngine__CollateralNotRedeemed();
        }
    }

    /**
     * @dev This contract is first sending AuraToken to this contract and then this contract will call the burn function and it is also compatible if someone wants to liquidate a user.
     * @param inPlaceOf address who deposited the collateral before
     * @param by address which is burning the AuraTokens
     * @param _amountAuraToBurn amount of AuraTokens to burn
     */
    function _burnAura(address inPlaceOf, address by, uint256 _amountAuraToBurn) internal {
        s_userToAuraCoinMinted[inPlaceOf] -= _amountAuraToBurn;
        bool success = i_auraCoin.transferFrom(by, address(this), _amountAuraToBurn);
        if (!success) {
            revert AuraEngine__CollateralNotRedeemed();
        }
        i_auraCoin.burn(_amountAuraToBurn);
    }

    /**
     * This function will deposit collateral to this AuraEngine contract .
     * @param _collateralToken The address of the collateral token being deposited.
     * @param _amountToDeposit The amount of collateral to deposit.
     * @notice In this function the state is first updated to ensure safety and re-entrency safety .
     */
    function _depositCollateral(address _collateralToken, uint256 _amountToDeposit)
        internal
        mustBeMoreThanZero(_amountToDeposit)
        nonReentrant
        isAllowedCollateral(_collateralToken)
    {
        s_collateralDeposited[msg.sender][_collateralToken] += _amountToDeposit;
        emit CollateralDeposited(msg.sender, _collateralToken, _amountToDeposit);
        bool success = IERC20(_collateralToken).transferFrom(msg.sender, address(this), _amountToDeposit);
        if (!success) {
            revert AuraEngine__CollateralNotDeposited();
        }
    }

    /**
     * This function will mint AuraCoin .
     * @param _amountAuraToMint Amount of Aura to mint after depositing collateral
     * @notice In this function the state is first updated to ensure safety and re-entrency safety .
     */
    function _mintAuraCoin(uint256 _amountAuraToMint) internal mustBeMoreThanZero(_amountAuraToMint) nonReentrant {
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
        uint256 healthFactor = getHealthFactorByUserAddressInProtocol(_user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert AuraEngine__HealthFactorBroken();
        }
    }
    /*///////////////////////////////////////
              GETTER FUNCTIONS
    ///////////////////////////////////////*/

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
    function getHealthFactorByUserAddressInProtocol(address _user) public view returns (uint256) {
        uint256 totalCollateralValueInINR;
        uint256 amountOfAuraCoinMintedInINR = getAuraCoinMintedByUsers(_user);

        // Loop through all allowed collateral tokens
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address collateralToken = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][collateralToken];
            if (amount > 0) {
                totalCollateralValueInINR += getTokenValueInINR(collateralToken, amount);
            }
        }

        uint256 healthFactor = getHealthFactor(totalCollateralValueInINR, amountOfAuraCoinMintedInINR);
        return healthFactor;
    }

    /**
     * @notice anyone can check the health factor using this function
     * @param _totalCollateralValueInINR amount of collateral in inr deposited
     * @param _auraMinted amount of Aura minted (if 1000 rupee -> represent it as 1000 ether)
     */
    // uint8 private constant THRESHOLD_HEALTH_FACTOR_PRECISION = 10;
    // uint256 private constant PRECISION_FACTOR = 1e18;
    // uint8 private THRESHOLD_HEALTH_FACTOR = 20;
    function getHealthFactor(uint256 _totalCollateralValueInINR, uint256 _auraMinted) public view returns (uint256) {
        if (_auraMinted == 0) return type(uint256).max;
        uint256 healthFactor = (_totalCollateralValueInINR * PRECISION_FACTOR * THRESHOLD_HEALTH_FACTOR_PRECISION)
            / (_auraMinted * THRESHOLD_HEALTH_FACTOR);
        return healthFactor;
    }

    /**
     * @param _tokenAddress The address of the token to value.
     * @param _amount The amount of the token.
     * @return uint256 if _amoun = 2 ether and _tokenAddress is `wETH` and price of 1 eth in INR is 1000INR, then this returns 2000*1e18;
     */
    function getTokenValueInINR(address _tokenAddress, uint256 _amount) public view returns (uint256) {
        address priceFeedAddress = s_collateralToPriceFeed[_tokenAddress];
        if (priceFeedAddress == address(0)) {
            revert AuraEngine__TokenNotAllowedAsCollateral();
        }
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // Assumes price feed is USD based with 8 decimals, common for Chainlink
        uint256 adjustedPrice = uint256(price) * PRECISION_PRICE_FEED * USD_INR_PRICE;
        return (adjustedPrice * _amount) / PRECISION_FACTOR;
    }

    /**
     * @param _amountInINR Amount in INR to convert in ETH
     * @return uint256 if _amountInEth = 2000INR and price of 1 eth in INR is 1000INR, then this returns 2 ether
     */
    function getTokensForINR(address _tokenAddress, uint256 _amountInINR) public view returns (uint256) {
        address priceFeedAddress = s_collateralToPriceFeed[_tokenAddress];
        if (priceFeedAddress == address(0)) {
            revert AuraEngine__TokenNotAllowedAsCollateral();
        }
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        uint256 adjustedPrice = uint256(price) * PRECISION_PRICE_FEED * USD_INR_PRICE;
        return (_amountInINR * PRECISION_FACTOR) / adjustedPrice;
    }

    /**
     * @return address Address of the AuraCoin Contract
     */
    function getAuraCoinAddress() public view returns (address) {
        return address(i_auraCoin);
    }

    /**
     * @return address this return an array of collateral token addresses.
     */
    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     * @param _user User to know how much collateral to deposit
     * @return uint256 Amount of AuraCoin minited by the `_user`.
     */
    function getAuraCoinMintedByUsers(address _user) public view returns (uint256) {
        return s_userToAuraCoinMinted[_user];
    }

    /**
     * @return address Address of the TimeLock Contract
     */
    // function getTimeLockContract() public view returns (address) {
    //     return i_timeLockContract;
    // }

    function getThresholdHealthFactor() public view returns (uint8) {
        return THRESHOLD_HEALTH_FACTOR;
    }

    /*///////////////////////////////////////
              OWNER FUNCTIONS
    ///////////////////////////////////////*/

    /**
     * @notice Adds a new collateral token and its price feed to the protocol.
     * @param _collateralToken The address of the token to add.
     * @param _priceFeed The address of the Chainlink price feed for the token.
     */
    function addCollateralType(address _collateralToken, address _priceFeed) external onlyOwner {
        if (s_collateralToPriceFeed[_collateralToken] != address(0)) {
            revert AuraEngine__TokenAlreadyAllowed();
        }
        s_collateralToPriceFeed[_collateralToken] = _priceFeed;
        s_collateralTokens.push(_collateralToken);
    }

    /**
     * @dev this function will be called by the timelock contract
     * @param _newBonusPercentage the new Bonus percentage which is being set by the community voting
     */
    function updateTheLiquidationBonus(uint256 _newBonusPercentage) internal onlyOwner {
        if (_newBonusPercentage > 15 || _newBonusPercentage < 5) {
            revert AuraEngine__ProtocolWillBreakIfBonusIsTooMuch();
        }
        LIQUIDATION_BONUS = _newBonusPercentage;
    }

    /**
     * @notice If you want to provide an overcollateralization value of for example-> 1.5 then provide 15 in the parameter as solidity don't have integer so make sure multiplying the answer with 10
     * @param _newOvercollateralizedPercent The new percentage for over-collaterlaization decided by the community
     */
    function updateTheLiquidationThreshold(uint8 _newOvercollateralizedPercent) external onlyOwner {
        if (_newOvercollateralizedPercent < 12 || _newOvercollateralizedPercent > type(uint8).max) {
            revert AuraEngine__OverCollateralizationNotValid();
        }
        THRESHOLD_HEALTH_FACTOR = _newOvercollateralizedPercent;
    }
}
