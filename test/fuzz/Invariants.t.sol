// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCengine} from "../../src/DSCengine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC public deployer;
    DSCengine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    Handler _handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();
        _handler = new Handler(dsce, dsc);
        targetContract(address(_handler));
    }

    function invariant_protocolMustBeOverCollateralized() public view {
        uint256 totalSupplyDSC = dsc.totalSupply();
        uint256 totalAmountWeth = IERC20(weth).balanceOf(address(dsce));
        uint256 totalAmountWbtc = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethvalue = dsce.getUSDvalue(weth, totalAmountWeth);
        uint256 wbtcvalue = dsce.getUSDvalue(wbtc, totalAmountWbtc);

        console.log("Amount of weth: ", wethvalue);
        console.log("Amount of wbtc: ", wbtcvalue);
        console.log("Total Supply of Dsc : ", totalSupplyDSC);

        assert(wethvalue + wbtcvalue >= totalSupplyDSC);
    }

    function invariant_gettersCantRevert() public view {
        dsce.getAdditionalFeedPrecision();
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getLiquidationBonus();
        dsce.getLiquidationThreshold();
        dsce.getMinHealthFactor();
        dsce.getPrecision();
        dsce.getDsc();
        // dsce.getTokenAmountFromUsd();
        // dsce.getCollateralTokenPriceFeed();
        // dsce.getCollateralBalanceOfUser();
        // getAccountCollateralValue();
    }
}
