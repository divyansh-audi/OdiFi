// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink-brownie/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainID();

    struct NetworkConfig {
        address weth;
        address ethUSDPriceFeed;
        address defaultOwner;
    }

    address private constant DEFAULT_WALLET = 0x818c95937Cf7254cE5923e4E1dBf2fAF0dDaD06E;
    address private constant ANVIL_WALLET = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    uint8 private constant DECIMALS = 8;
    int256 private constant ETH_USD_PRICE = 2000e8;

    uint256 private constant LOCAL_CHAIN_ID = 31337;
    uint256 private constant ETH_SEPOLIA_CHAIN_ID = 11155111;

    NetworkConfig public activeNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilConfig();
        } else if (networkConfigs[chainId].defaultOwner != address(0)) {
            return networkConfigs[chainId];
        } else {
            revert HelperConfig__InvalidChainID();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            ethUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            defaultOwner: DEFAULT_WALLET
        });
        return sepoliaConfig;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock weth = new ERC20Mock();
        vm.stopBroadcast();
        return
            NetworkConfig({weth: address(weth), ethUSDPriceFeed: address(ethUsdPriceFeed), defaultOwner: ANVIL_WALLET});
    }
}
