// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "@forge-std/Test.sol";
import {AuraCoin} from "src/AuraCoin.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {DeployAuraEngine} from "script/DeployAuraEngine.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract AuraEngineTest is Test {
    DeployAuraEngine public deploy;
    AuraEngine public auraEngine;
    AuraCoin public auraCoin;
    HelperConfig public config;
    address public weth;
    address public ethUSDPriceFeed;
    address public defaultOwner;

    uint8 private constant USD_INR_PRICE = 85;

    uint256 constant INITIAL_WETH_BALANCE = 10 ether;
    uint256 constant AMOUNT_TO_DEPOSIT = 2 ether;
    uint256 constant AURA_TO_MINT = 2000 * 85e18; //1 ether in INR
    address public USER = makeAddr("user");
    address public ALICE = makeAddr("alice");
    address public DEFAULT_OWNER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        deploy = new DeployAuraEngine();
        (auraCoin, auraEngine, config) = deploy.run();
        (weth, ethUSDPriceFeed, defaultOwner) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, INITIAL_WETH_BALANCE);
        ERC20Mock(weth).mint(ALICE, INITIAL_WETH_BALANCE);
        ERC20Mock(weth).mint(DEFAULT_OWNER, INITIAL_WETH_BALANCE);
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUSDPriceFeed);
    }

    function testDepositCollateralAndMintAura() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), AMOUNT_TO_DEPOSIT);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT, AURA_TO_MINT);
        uint256 balance = auraCoin.balanceOf(USER);
        vm.stopPrank();
        assertEq(balance, AURA_TO_MINT);
    }

    function testPriceConversionWorkingFine() public {
        vm.prank(USER);
        uint256 indianPrice = auraEngine.getTokenValueInINR(weth, AMOUNT_TO_DEPOSIT);
        console2.log("indian price", indianPrice);
        uint256 expectedValue = 2000 * uint256(USD_INR_PRICE) * AMOUNT_TO_DEPOSIT;
        console2.log("expected value", expectedValue);
        assertEq(indianPrice, expectedValue);

        vm.prank(USER);
        uint256 ethPrice = auraEngine.getTokensForINR(weth, 2000 * uint256(USD_INR_PRICE) * 1e18);
        uint256 expectedEth = 1 ether;
        assertEq(ethPrice, expectedEth);
    }

    function testHealthFactorWorkingFine() public {
        vm.prank(USER);

        uint256 expectedHealth = auraEngine.getHealthFactor(2000 ether, 1000 ether);
        assertEq(1 ether, expectedHealth);
    }

    function testRevertsIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), AMOUNT_TO_DEPOSIT);
        // vm.expectRevert(AuraEngine.AuraEngine__HealthFactorBroken.selector);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT, AURA_TO_MINT);

        assertEq(1 ether, auraEngine.getHealthFactorByUserAddressInProtocol(USER));

        vm.stopPrank();
    }

    function testRevertIfZeroIsInAnyPlace() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), AMOUNT_TO_DEPOSIT);
        vm.expectRevert(AuraEngine.AuraEngine__MustBeMoreThanZero.selector);
        auraEngine.depositCollateralAndMintAura(weth, 0, AURA_TO_MINT + 1);

        vm.expectRevert(AuraEngine.AuraEngine__MustBeMoreThanZero.selector);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT, 0);

        vm.stopPrank();
    }

    function testRedeemCollateralAndBurnAura() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraCoin.approve(address(auraEngine), AURA_TO_MINT);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);
        vm.expectRevert(AuraEngine.AuraEngine__HealthFactorBroken.selector);
        auraEngine.redeemCollateralAndBurnAura(weth, 2 ether, AURA_TO_MINT / 2 - uint256(1));

        vm.stopPrank();
    }

    function testLiquidationRevertsIfHealthFactorNotBroken() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);
        vm.stopPrank();
        vm.startPrank(ALICE);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);
        vm.expectRevert(AuraEngine.AuraEngine__HealthFactorAlreadyGood.selector);
        auraEngine.liquidate(USER, weth, AURA_TO_MINT);
        vm.stopPrank();
    }

    /**
     * @dev L.THRESHOLD=2
     * HEALTH FACTOR=3/2=1.5
     * NOW L.THRESHOLD=4
     * HAELTH FACTOR=3/4---> 0.75 liqudation!!!!!!
     *
     */
    function testLiquidationWorksWell() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);

        vm.stopPrank();

        //////////////////////////////////////////////
        vm.prank(DEFAULT_OWNER);
        // Increase the threshold to 4 times
        auraEngine.updateTheLiquidationThreshold(40);
        uint256 healthFactorBefore = auraEngine.getHealthFactorByUserAddressInProtocol(USER);
        //////////////////////////////////////////////////
        vm.startPrank(ALICE);

        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraCoin.approve(address(auraEngine), AURA_TO_MINT);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT * 2, AURA_TO_MINT);
        auraEngine.liquidate(USER, weth, AURA_TO_MINT / 4);
        vm.stopPrank();

        uint256 healthFactorAfter = auraEngine.getHealthFactorByUserAddressInProtocol(USER);

        uint8 healthThreshold = auraEngine.getThresholdHealthFactor();
        assertEq(healthThreshold, 40);
        assertEq(auraEngine.getAuraCoinMintedByUsers(USER), AURA_TO_MINT * 3 / 4);
        assert(healthFactorAfter > healthFactorBefore);
    }

    function testAddingCollateralWorksFine(address collateral, address priceFeed) public {
        vm.prank(DEFAULT_OWNER);
        auraEngine.addCollateralType(collateral, priceFeed);
        assertEq(auraEngine.getCollateralTokens()[1], collateral);
        assertEq(auraEngine.getPriceFeed(collateral), priceFeed);
    }

    function testCheckUpkeepRunsFine() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 2 ether, AURA_TO_MINT);
        vm.stopPrank();
        vm.startPrank(ALICE);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        // auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 2 ether, AURA_TO_MINT);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);

        vm.stopPrank();
        vm.startPrank(DEFAULT_OWNER);
        auraEngine.updateTheLiquidationThreshold(40);
        (bool checkUpkeep,) = auraEngine.checkUpkeep("");
        vm.stopPrank();

        // assertEq(checkUpkeep, false);
        assertEq(checkUpkeep, true);
    }

    /**
     * USER-> deposited 3 ether as collateral ,minted 1 ether-> as Aura
     * HEALTH FACTOR ->1.5 (3/1*2)
     * threshold changed -> 4
     * HEALTH FACTOR ->0.75 (3/1*4)
     * liquidate half of the debt ->0.5 ether
     * and redeemed (0.5+0.5*10/100)=>0.55 ether
     * collateral left ->2.45 ether and remaining debt ->0.5 ether
     * health factor ->2.45/0.5*4=1.225
     * which is fine
     */
    function testPerformUpkeepWorksFine() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 2 ether, AURA_TO_MINT);
        vm.stopPrank();
        vm.startPrank(ALICE);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        // auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 2 ether, AURA_TO_MINT);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);

        vm.stopPrank();
        vm.startPrank(DEFAULT_OWNER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(weth, AMOUNT_TO_DEPOSIT + 2 ether, AURA_TO_MINT);
        // auraCoin.approve(DEFAULT_OWNER, AURA_TO_MINT);
        auraCoin.approve(address(auraEngine), AURA_TO_MINT);
        auraEngine.updateTheLiquidationThreshold(40);
        console2.log("first check");
        assertEq(1 ether, auraEngine.getHealthFactorByUserAddressInProtocol(USER));
        (bool checkUpkeep, bytes memory performData) = auraEngine.checkUpkeep("");
        auraEngine.performUpkeep(performData);
        vm.stopPrank();
        assertEq(checkUpkeep, true);
        assertEq(1.225 ether, auraEngine.getHealthFactorByUserAddressInProtocol(ALICE));
        assertEq(ALICE, abi.decode(performData, (address)));
    }
}
