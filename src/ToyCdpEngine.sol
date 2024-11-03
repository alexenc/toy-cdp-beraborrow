// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {STABLE} from "./STABLE.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockEthOracle} from "./libraries/MockEthOracle.sol";

/**
 * @title ToyCDPEngine
 * The system its meant to be a basic CDP contract allowing users to borrow $Table with overcolletarized loans
 * The system allows to open and close positions as well as perform liquidations on insolvet positions
 *
 * @notice this contract is the core of the whole ToyCDP protocol
 */
contract ToyCDPEngine {
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
        address user;
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 useInterestIndex;
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
    uint256 constant collateralRatio = 1100;
    uint256 constant ratioprecision = 1000;
    uint256 totalProtocolCollateral;

    // interest accounting variables
    uint256 interestRate = 5; // 5%
    uint256 interestIndex = 1e18;
    uint256 lastInterestUpdate = block.timestamp;

    MockEthOracle ethPriceOracle;

    /// EVENTS
    event CollateralDeposited(address indexed user, uint256 amount);

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
        _updateGlogalInterestIndex();
        uint256 collateralValue = _getCollateralUSDVaule(_amount);

        // Check if desired debt amount maintains minimum collateralization ratio
        // Multiply by ratio precision since collateralRatio includes it
        // TODO move that to internal function like check postion cratio
        if (
            (collateralValue * ratioprecision) / _debtAmount < collateralRatio
        ) {
            revert("Collateral ratio too low");
        }

        // Transfer WETH from user to contract
        IERC20(weth).transferFrom(msg.sender, address(this), _amount);

        // Update user's collateral balance
        Position memory userPosition = Position({
            collateralAmount: _amount,
            debtAmount: _debtAmount,
            user: msg.sender,
            useInterestIndex: block.timestamp
        });

        userPositions[msg.sender] = userPosition;
        totalProtocolCollateral += _amount;
        // @audit q maybe update also debt amount?
        emit CollateralDeposited(msg.sender, _amount);

        // Mint requested amount of stable tokens to user
        _mintStable(msg.sender, _amount);
    }

    /**
     * @notice close a user position repaying back its debt + interest and getting back its collateral
     */
    function closePosition() external {
        _updateGlogalInterestIndex();
        _accrueUserInterest(msg.sender);

        Position memory userPosition = userPositions[msg.sender];
        // Get user's collateral balance
        uint256 userCollateral = userPosition.collateralAmount;
        // TODO check user healt factor if cr lower than min revert as user its not allowed
        if (userCollateral == 0) revert("No position to close");
        // TODO position should have accrued debt as interal param

        // Get user's debt balance from STABLE contract
        uint256 userDebt = userPosition.debtAmount;

        // Transfer STABLE from user back to contract and burn it
        i_stablecoin.transferFrom(msg.sender, address(this), userDebt);
        // @audit q - what to do with surplus satble being burned
        i_stablecoin.burn(userDebt);

        // Transfer collateral back to user
        _redeemCollateral(msg.sender, userCollateral);

        // Update state
        delete userPositions[msg.sender];
        totalProtocolCollateral -= userCollateral;
    }
    function liquidate() external {
        _updateGlogalInterestIndex();
        // when a user position is subsceptible for being liquidated a user can call liquidate
        // this is possible when cr ratio of possition its below the minimum collateral ratio
        // the user who liquidates the position receibes the liquidated user collateral by paying back the debt
        // need to accrue interest on user positions
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
    function _burnStable(uint256 _amount) internal {}

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
    function _redeemCollateral(address _user, uint256 _amount) internal {}

    /**
     * @notice function that updates the global interest index
     * and the last interest update.
     *
     */
    function _updateGlogalInterestIndex() internal {
        uint256 timeElapsed = block.timestamp - lastInterestUpdate;
        if (timeElapsed == 0) return;
        //calculate interest factor for elapsed time in anually terms
        uint256 interestFactor = (1e18 +
            ((interestRate * timeElapsed) / 365 days / 100));
        interestIndex = (interestIndex * interestFactor) / 1e18;

        lastInterestUpdate = block.timestamp;
    }

    /**
     * @notice function that updates a user's debt with accrued interest
     * updates the user position with new debt amount and interest index
     */
    function _accrueUserInterest(address user) internal returns (uint256) {
        Position storage position = userPositions[user];
        if (position.debtAmount == 0) return 0;

        // Calculate total debt with interest
        uint256 currentDebt = (position.debtAmount * interestIndex) /
            position.useInterestIndex;

        // Update position with new debt and current interest index
        position.debtAmount = currentDebt;
        position.useInterestIndex = interestIndex;

        return currentDebt;
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

    // TODO probably getters of user position value to improve readability and updating etc
}
