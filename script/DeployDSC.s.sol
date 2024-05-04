// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralisedStableCoin.sol";
import {DSCengine} from "../src/DSCengine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

pragma solidity ^0.8.19;

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeed;

    function run()
        public
        returns (DecentralizedStableCoin, DSCengine, HelperConfig)
    {
        HelperConfig _config = new HelperConfig();

        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = _config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeed = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        DecentralizedStableCoin _decentralisedStableCoin = new DecentralizedStableCoin();

        DSCengine _engine = new DSCengine(
            tokenAddresses,
            priceFeed,
            address(_decentralisedStableCoin)
        );
        _decentralisedStableCoin.transferOwnership(address(_engine));
        vm.stopBroadcast();
        return (_decentralisedStableCoin, _engine, _config);
    }
}
