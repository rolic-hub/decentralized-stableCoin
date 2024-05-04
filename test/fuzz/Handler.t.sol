// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCengine} from "../../src/DSCengine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.t.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.t.sol";

contract Handler is Test {
    DSCengine dscengine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    address[] public usersDepositedCollateral;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCengine _dscengine, DecentralizedStableCoin _dsc) {
        dscengine = _dscengine;
        dsc = _dsc;

        address[] memory collateralTokens = dscengine.getCollateralTokens();

        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersDepositedCollateral.length == 0) {
            return;
        }
        address sender = usersDepositedCollateral[
            addressSeed % usersDepositedCollateral.length
        ];
        (uint256 collateralValueinUSD, uint256 totalDSCminted) = dscengine
            .getAccountInformation(sender);

        int256 maxToMint = (int256(collateralValueinUSD) / 2) -
            int256(totalDSCminted);

        if (maxToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxToMint));

        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscengine.mintDSC(amount);
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromseed(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(dscengine), amount);

        dscengine.depositCollateral(address(collateral), amount);
        usersDepositedCollateral.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromseed(collateralSeed);

        vm.startPrank(msg.sender);
        uint256 maxCollateral = dscengine.getCollateralBalanceOfUser(
            msg.sender,
            address(collateral)
        );

        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) {
            return;
        }

        dscengine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
        int256 intNewPrice = int256(uint256(newPrice));
        ERC20Mock collateral = _getCollateralFromseed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(dscengine.getCollateralTokenPriceFeed(address(collateral)));

        priceFeed.updateAnswer(intNewPrice);
    }

    function _getCollateralFromseed(
        uint256 collateralSeed
    ) public view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
