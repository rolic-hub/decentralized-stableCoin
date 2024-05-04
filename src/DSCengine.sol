// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin


pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralisedStableCoin.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

contract DSCengine is ReentrancyGuard {
    error DSCengine__NeedsMoreThanZero();
    error DSCengine__NotAllowedToken();
    error DSCengine__TransferFailed();
    error DSCengine__MintFailed();
    error DSCengine__HealthFactorOK();
    error DSCengine__HealthFactorNotImproved();
    error DSCengine__HealthFactorBroken(uint256 healthFactor);
    error DSCengine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();

    using OracleLib for AggregatorV3Interface;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;

    DecentralizedStableCoin private immutable i_dscToken;

    mapping(address token => address pricefeed) private s_PriceFeed;
    mapping(address user => mapping(address token => uint256 amount))
        private s_CollateralDeposited;
    mapping(address user => uint256 amountMint) private s_DSCMinted;
    address[] private s_CollateralTokens;

    event CollateralDeposited(
        address indexed user,
        address indexed tokenCollateral,
        uint256 indexed amountCollateral
    );
    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed tokenCollateral,
        uint256 amountCollateral
    );

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCengine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_PriceFeed[token] == address(0)) {
            revert DSCengine__NotAllowedToken();
        }
        _;
    }

/**
 * @dev Constructor for DSCengine contract.
 * @param tokenAddresses Array of addresses of collateral tokens.
 * @param priceFeedAdresses Array of addresses of price feed contracts for each collateral token.
 * @param dscToken Address of the DSC token contract.
 * throws DSCengine__TokenAddressesAndPriceFeedAddressesMustBeSameLength if the lengths of tokenAddresses and priceFeedAdresses arrays are not equal.
 */

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAdresses,
        address dscToken
    ) {
        if (tokenAddresses.length != priceFeedAdresses.length) {
            revert DSCengine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_PriceFeed[tokenAddresses[i]] = priceFeedAdresses[i];
            s_CollateralTokens.push(tokenAddresses[i]);
        }
        i_dscToken = DecentralizedStableCoin(dscToken);
    }

    /**
 * @dev Deposits collateral and mints DSC.
 * @param tokenCollateralAddress Address of the collateral token.
 * @param amountCollateral Amount of collateral to deposit.
 * @param amountDSCMint Amount of DSC to mint.
 * throws DSCengine__NeedsMoreThanZero if amountCollateral or amountDSCMint is zero.
 * throws DSCengine__NotAllowedToken if the tokenCollateralAddress is not allowed.
 * throws DSCengine__TransferFailed if the transfer of collateral fails.
 * throws DSCengine__MintFailed if the minting of DSC fails.
 * throws DSCengine__HealthFactorBroken if the user's health factor is broken.
 */

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCMint);
    }

/**
 * @dev Deposits collateral for the user.
 * @param tokenCollateralAddress Address of the collateral token.
 * @param amountCollateral Amount of collateral to deposit.
 * throws DSCengine__NeedsMoreThanZero if amountCollateral is zero.
 * throws DSCengine__NotAllowedToken if the tokenCollateralAddress is not allowed.
 * throws DSCengine__TransferFailed if the transfer of collateral fails.
 * throws DSCengine__HealthFactorBroken if the user's health factor is broken.
 */

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
    {
        s_CollateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );

        if (!success) {
            revert DSCengine__TransferFailed();
        }
    }

    /**
 * @dev Redeems collateral for DSC and burns DSC.
 * @param tokenCollateralAddress Address of the collateral token.
 * @param amountCollateral Amount of collateral to redeem.
 * @param amountDSCBurn Amount of DSC to burn.
 * throws DSCengine__NeedsMoreThanZero if amountCollateral or amountDSCBurn is zero.
 * throws DSCengine__HealthFactorBroken if the user's health factor is broken.
 */

    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCBurn
    ) external {
        burnDSC(amountDSCBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
 * @dev Redeems collateral for the user.
 * @param tokenCollateralAddress Address of the collateral token.
 * @param amountCollateral Amount of collateral to redeem.
 * throws DSCengine__NeedsMoreThanZero if amountCollateral is zero.
 * throws DSCengine__HealthFactorBroken if the user's health factor is broken.
 */

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
 * @dev Mints DSC for the user.
 * @param amountDSCMint Amount of DSC to mint.
 * throws DSCengine__NeedsMoreThanZero if amountDSCMint is zero.
 * throws DSCengine__MintFailed if the minting of DSC fails.
 * throws DSCengine__HealthFactorBroken if the user's health factor is broken.
 */

    function mintDSC(
        uint256 amountDSCMint
    ) public moreThanZero(amountDSCMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dscToken.mint(msg.sender, amountDSCMint);
        if (!minted) {
            revert DSCengine__MintFailed();
        }
    }

    /**
 * @dev Burns DSC for the user.
 * @param amount Amount of DSC to burn.
 * throws DSCengine__NeedsMoreThanZero if amount is zero.
 * throws DSCengine__HealthFactorBroken if the user's health factor is broken.
 */

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
 * @dev Liquidates the user's collateral to cover debt.
 * @param tokenCollateralAddress Address of the collateral token.
 * @param user Address of the user to liquidate.
 * @param debtToCover Amount of debt to cover.
 * throws DSCengine__NeedsMoreThanZero if debtToCover is zero.
 * throws DSCengine__HealthFactorOK if the user's health factor is already above the minimum health factor.
 * throws DSCengine__HealthFactorNotImproved if the user's health factor does not improve after liquidation.
 * throws DSCengine__HealthFactorBroken if the liquidator's health factor is broken.
 */
    function liquidate(
        address tokenCollateralAddress,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCengine__HealthFactorOK();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            tokenCollateralAddress,
            debtToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateral = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(
            user,
            msg.sender,
            tokenCollateralAddress,
            totalCollateral
        );
        _burnDSC(user, msg.sender, debtToCover);
        uint256 endingHealthFactor = _healthFactor(user);

        if (endingHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCengine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    

    ////////////////////////////////////////////////////////////////
    //// Private & Internal Functions
    ////////////////////////////////////////////////////////////////

    function _redeemCollateral(
        address from,
        address to,
        address collateralAddress,
        uint256 collateralAmount
    ) private {
        s_CollateralDeposited[from][collateralAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, collateralAddress, collateralAmount);
        bool sucess = IERC20(collateralAddress).transfer(to, collateralAmount);
        if (!sucess) {
            revert DSCengine__TransferFailed();
        }
    }

    function _burnDSC(
        address onBehalfOf,
        address dscFrom,
        uint256 amountDscToBurn
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool sucess = i_dscToken.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        if (!sucess) {
            revert DSCengine__TransferFailed();
        }
        i_dscToken.burn(amountDscToBurn);
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalCollateralinUSD, uint256 totalDSCmint)
    {
        totalDSCmint = s_DSCMinted[user];
        totalCollateralinUSD = getAccountCollateralValue(user);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) {
            return type(uint96).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCengine__HealthFactorBroken(userHealthFactor);
        }
    }

    ////////////////////////////////////////////////////////////////
    ////////////// Public functions //////////////////////////////////////////////////////////////////

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_PriceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralinUSD) {
        for (uint256 i = 0; i < s_CollateralTokens.length; i++) {
            address token = s_CollateralTokens[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralinUSD += getUSDvalue(token, amount);
        }
        return totalCollateralinUSD;
    }

    function getUSDvalue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(
            s_PriceFeed[token]
        );
        (, int256 price, , , ) = pricefeed.staleCheckLatestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_CollateralDeposited[user][token];
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalCollateralinUSD, uint256 totalDSCmint)
    {
        (totalCollateralinUSD, totalDSCmint) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_CollateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dscToken);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_PriceFeed[token];
    }

    /**
 * @dev Returns the health factor of the user.
 * @return The health factor of the user.
 */

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
