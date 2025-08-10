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

    function setUp() public {
        deploy = new DeployAuraEngine();
        (auraCoin, auraEngine, config) = deploy.run();
        (weth, ethUSDPriceFeed, defaultOwner) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, INITIAL_WETH_BALANCE);
        ERC20Mock(weth).mint(ALICE, INITIAL_WETH_BALANCE);
    }

    function testDepositCollateralAndMintAura() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), AMOUNT_TO_DEPOSIT);
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT, AURA_TO_MINT);
        uint256 balance = auraCoin.balanceOf(USER);
        vm.stopPrank();
        assertEq(balance, AURA_TO_MINT);
    }

    function testPriceConversionWorkingFine() public {
        vm.prank(USER);
        uint256 indianPrice = auraEngine.getINRforEth(AMOUNT_TO_DEPOSIT);
        console2.log("indian price", indianPrice);
        uint256 expectedValue = 2000 * uint256(USD_INR_PRICE) * AMOUNT_TO_DEPOSIT;
        console2.log("expected value", expectedValue);
        assertEq(indianPrice, expectedValue);

        vm.prank(USER);
        uint256 ethPrice = auraEngine.getETHforINR(2000 * uint256(USD_INR_PRICE) * 1e18);
        uint256 expectedEth = 1 ether;
        assertEq(ethPrice, expectedEth);
    }

    function testHealthFactorWorkingFine() public {
        vm.prank(USER);

        uint256 expectedHealth = auraEngine.getHealthFactor(2 ether, 2000 * uint256(USD_INR_PRICE) * 1e18);
        assertEq(1 ether, expectedHealth);
    }

    function testRevertsIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), AMOUNT_TO_DEPOSIT);
        vm.expectRevert(AuraEngine.AuraEngine__HealthFactorBroken.selector);
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT, AURA_TO_MINT + 1);

        vm.stopPrank();
    }

    function testRevertIfZeroIsInAnyPlace() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), AMOUNT_TO_DEPOSIT);
        vm.expectRevert(AuraEngine.AuraEngine__MustBeMoreThanZero.selector);
        auraEngine.depositCollateralAndMintAura(0, AURA_TO_MINT + 1);

        vm.expectRevert(AuraEngine.AuraEngine__MustBeMoreThanZero.selector);
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT, 0);

        vm.stopPrank();
    }

    function testRedeemCollateralAndBurnAura() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraCoin.approve(address(auraEngine), AURA_TO_MINT);
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);
        vm.expectRevert(AuraEngine.AuraEngine__HealthFactorBroken.selector);
        auraEngine.redeemCollateralAndBurnAura(2 ether, AURA_TO_MINT / 2 - uint256(1));

        vm.stopPrank();
    }

    function testLiquidationRevertsIfHealthFactorNotBroken() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);
        vm.stopPrank();
        vm.startPrank(ALICE);
        ERC20Mock(weth).approve(address(auraEngine), INITIAL_WETH_BALANCE);
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);
        vm.expectRevert(AuraEngine.AuraEngine__HealthFactorAlreadyGood.selector);
        auraEngine.liquidate(USER, AURA_TO_MINT);
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
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT + 1 ether, AURA_TO_MINT);

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
        auraEngine.depositCollateralAndMintAura(AMOUNT_TO_DEPOSIT * 2, AURA_TO_MINT);
        auraEngine.liquidate(USER, AURA_TO_MINT / 4);
        vm.stopPrank();

        uint256 healthFactorAfter = auraEngine.getHealthFactorByUserAddressInProtocol(USER);

        uint8 healthThreshold = auraEngine.getThresholdHealthFactor();
        assertEq(healthThreshold, 40);
        assertEq(auraEngine.getAuraCoinMintedByUsers(USER), AURA_TO_MINT * 3 / 4);
        assert(healthFactorAfter > healthFactorBefore);
    }
}
