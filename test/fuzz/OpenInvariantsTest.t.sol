// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCengine} from "../../src/DSCengine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract OpenFuzzTest is Test {
    DeployDSC public deployer;
    DSCengine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();
    }

    function testprotocolMustBeOverCollateralizedFuzz() public view {
        uint256 totalSupplyDSC = dsc.totalSupply();
        uint256 totalAmountWeth = IERC20(weth).balanceOf(address(dsce));
        uint256 totalAmountWbtc = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethvalue = dsce.getUSDvalue(weth, totalAmountWeth);
        uint256 wbtcvalue = dsce.getUSDvalue(wbtc, totalAmountWbtc);

        assert(wethvalue + wbtcvalue >= totalSupplyDSC);
    }
}
