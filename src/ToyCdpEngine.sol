// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {STABLE} from "./STABLE.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockEthOracle} from "./libraries/MockEthOracle.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/console.sol";

/**
 * @title ToyCDPEngine
 * The system its meant to be a basic CDP contract allowing users to borrow $Table with overcolletarized loans
 * The system allows to open and close positions as well as perform liquidations on insolvet positions
 *
 * @notice this contract is the core of the whole ToyCDP protocol
 */
contract ToyCDPEngine {
    using SafeERC20 for IERC20;
    ///////////////
    // ERRORS   //
    ///////////////

    error TOYCDPEngine_moreThanZero();

    /*
     * @notice struct that represents a user position inside the system
     * it keeps tracks of position collateral and accrued debt
     * and iRates accounting
     */
    struct Position {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 userInterestIndex;
    }

    ///////////////
    // Modifiers //
    ///////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert TOYCDPEngine_moreThanZero();
        }
        _;
    }

    /////////////////////
    // State variables //
    /////////////////////

    // @notice amount its in weth as it is the only collateral available
    mapping(address user => Position position) private userPositions;

    STABLE immutable i_stablecoin;

    address immutable weth;
    uint256 constant MCR = 11000; // MCR 110%
    uint256 constant ratioprecision = 10000;
    uint256 totalProtocolCollateral;

    // interest accounting variables
    uint256 interestRate = 5; // 5.00% (500/100)
    uint256 interestIndex = 1e18;
    uint256 lastInterestUpdate = block.timestamp;

    MockEthOracle ethPriceOracle;

    /// EVENTS
    event PositionCreated(
        address indexed user,
        uint256 collateralAmount,
        uint256 _debtAmount
    );

    event PosotionClosed(
        address indexed user,
        uint256 collateralAmount,
        uint256 debtAmount
    );

    event Liquidation(
        address indexed liquidator,
        address indexed liquidatedUser,
        uint256 collateralAmount,
        uint256 debtAmount
    );

    constructor(
        address _stableAddress,
        address _weth,
        address _ethOracleAddress
    ) {
        i_stablecoin = STABLE(_stableAddress);
        weth = _weth;
        ethPriceOracle = MockEthOracle(_ethOracleAddress);
    }

    //////////////
    // External //
    //////////////
    function openPosition(
        uint256 _amount,
        uint256 _debtAmount
    ) external moreThanZero(_amount) {
        _updateGlobalInterestIndex();
        Position memory userPosition = userPositions[msg.sender];
        if (userPosition.collateralAmount > 0) {
            revert("User already has an existing position");
        }

        _updateGlobalInterestIndex();
        uint256 collateralValue = _getCollateralUSDVaule(_amount);

        // Check if desired debt amount maintains minimum collateralization ratio
        // Multiply by ratio precision since collateralRatio includes it
        if (_getPositionCollateralRatio(collateralValue, _debtAmount) < MCR) {
            revert("Collateral ratio too low");
        }

        // Transfer WETH from user to contract
        IERC20(weth).transferFrom(msg.sender, address(this), _amount); // @audit use safetransferFrom

        // Update user's collateral balance
        userPosition = Position({
            collateralAmount: _amount,
            debtAmount: _debtAmount,
            userInterestIndex: interestIndex
        });

        userPositions[msg.sender] = userPosition;
        totalProtocolCollateral += _amount;

        emit PositionCreated(msg.sender, _amount, _debtAmount);

        // Mint requested amount of stable tokens to user
        _mintStable(msg.sender, _debtAmount);
    }

    /**
     * @notice close a user position repaying back its debt + interest and getting back its collateral
     */
    function closePosition() external {
        _updateGlobalInterestIndex();
        _accrueUserInterest(msg.sender);

        Position memory userPosition = userPositions[msg.sender];
        // Get user's collateral balance
        uint256 userCollateral = userPosition.collateralAmount;

        if (userCollateral == 0) revert("No position to close");

        uint256 collateralValue = _getCollateralUSDVaule(userCollateral);
        uint256 userDebt = userPosition.debtAmount;

        if (_getPositionCollateralRatio(collateralValue, userDebt) < MCR)
            revert("Position below MCR");

        // Transfer STABLE from user back to contract and burn it
        i_stablecoin.transferFrom(msg.sender, address(this), userDebt);
        _burnStable(userDebt);

        // Update state
        delete userPositions[msg.sender];
        totalProtocolCollateral -= userCollateral;
        // follow CEI pattern
        // Transfer collateral back to user
        _redeemCollateral(msg.sender, userCollateral);
        emit PosotionClosed(msg.sender, userCollateral, userDebt);
    }

    /*
     *  @notice function to liquidate insolvent positions, maxrepayamount to cover mev slippage
     * @param positionToLiquidate user position to be liquidated
     * @paramz maxrepayAmount Stable amount to be paid by liquidator
     */
    function liquidate(address positionToLiquidate) external {
        require(
            msg.sender != positionToLiquidate,
            "User can not liquidate its position"
        );
        _updateGlobalInterestIndex();

        uint256 userDebt = _accrueUserInterest(positionToLiquidate);

        Position memory userPosition = userPositions[positionToLiquidate];

        uint256 userCollateral = userPosition.collateralAmount;

        if (userCollateral == 0) revert("No position to liquidate");

        uint256 collateralValue = _getCollateralUSDVaule(userCollateral);

        require(
            _isLiquidatable(collateralValue, userDebt),
            "Position not subsceptible to liquidation"
        );

        // Update state
        delete userPositions[positionToLiquidate];
        totalProtocolCollateral -= userCollateral;

        // Transfer STABLE from liquidator to contract and burn it
        i_stablecoin.transferFrom(msg.sender, address(this), userDebt);
        _burnStable(userDebt);

        // Transfer liquidated collateral to liquidator
        _redeemCollateral(msg.sender, userCollateral);

        emit Liquidation(
            msg.sender,
            positionToLiquidate,
            userCollateral,
            userDebt
        );
    }

    /*
     * @notice function that returns the total collateral ratio of the protocol
     * it can be used to get a health status of the system
     *
     */
    function getProtocolCr() external returns (uint256) {
        uint256 totalCollateralValueInUsd = _getCollateralUSDVaule(
            totalProtocolCollateral
        );
        uint256 totalSupply = i_stablecoin.totalSupply();
        if (totalSupply == 0) return type(uint256).max;
        return (totalCollateralValueInUsd * ratioprecision) / totalSupply;
    }

    ///////////////////////
    // INTERNAL FUNCTIONS /
    ///////////////////////

    /**
     * burns selected amount of STABLE used when liquidating or closing a position
     */
    function _burnStable(uint256 _amount) internal {
        i_stablecoin.burn(_amount);
    }

    /**
     * mints selected amount of STABLE aka user debt
     */
    function _mintStable(address user, uint256 _amount) internal {
        i_stablecoin.mint(user, _amount);
    }

    /**
     * @notice redeems colateral for a user
     * @param _amount amount of weth to be sent
     * @param _user user that will receive the collateral
     */
    function _redeemCollateral(address _user, uint256 _amount) internal {
        IERC20(weth).transfer(_user, _amount);
    }

    /**
     * @notice function that updates the global interest index
     * and the last interest update.
     *
     */
    function _updateGlobalInterestIndex() internal {
        // Calculate time elapsed since last interest update
        uint256 timeElapsed = block.timestamp - lastInterestUpdate;
        if (timeElapsed == 0) return;

        // Calculate interest factor using simple interest formula
        // interestRate is in percentage terms (e.g. 5 for 5%)
        // Scale up by 1e18 for precision
        uint256 interestFactor = 1e18 +
            ((interestRate * timeElapsed * 1e18) / (365 days * 100));

        // Update global interest index by multiplying by interest factor
        // Divide by 1e18 to remove scaling factor
        interestIndex = (interestIndex * interestFactor) / 1e18;
        // Update last interest timestamp
        lastInterestUpdate = block.timestamp;
    }

    /**
     * @notice function that updates a user's debt with accrued interest
     * updates the user position with new debt amount and interest index
     * returns the debt the user has with interest applied
     */
    function _accrueUserInterest(address user) internal returns (uint256) {
        Position storage position = userPositions[user];
        if (position.debtAmount == 0) return 0;

        uint256 currentDebt = (position.debtAmount * interestIndex) /
            position.userInterestIndex;

        // Update position with new debt and current interest index
        position.debtAmount = currentDebt;
        position.userInterestIndex = interestIndex;

        return currentDebt;
    }

    function _isLiquidatable(
        uint256 collateralValue,
        uint256 debtAmount
    ) internal view returns (bool) {
        // Calculate collateral ratio
        uint collateralRatio = (collateralValue * ratioprecision) / debtAmount;

        // Check if below the liquidation threshold
        return collateralRatio < MCR;
    }

    /**
     * @notice function that given a token and an amount returns its value in usd
     * this current implementation uses the MockETHOracle
     */
    function _getCollateralUSDVaule(
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 ethPrice = ethPriceOracle.getPrice(); // price of weth in usd represented with 18 decimals
        uint256 collateralValue = (_amount * ethPrice) / 1e18;
        return collateralValue;
    }

    /*
     * @notice function that returns the collareral ratio of a given position
     *
     */
    function _getPositionCollateralRatio(
        uint256 _collateralValue,
        uint256 _debt
    ) internal view returns (uint256) {
        return (_collateralValue * ratioprecision) / _debt;
    }
}
