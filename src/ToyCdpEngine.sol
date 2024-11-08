// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {STABLE} from "./STABLE.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockEthOracle} from "./libraries/MockEthOracle.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ToyCDPEngine
 * The system its meant to be a basic CDP contract allowing users to borrow $Table with overcolletarized loans
 * The system allows to open and close positions as well as perform liquidations on insolvet positions
 *
 * @notice this contract is the core of the whole ToyCDP protocol
 */
contract ToyCDPEngine is Ownable {
    using SafeERC20 for IERC20;

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
            revert("amount must be more than zero");
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

    uint256 public MCR = 11000; // MCR 110%
    uint256 public ratioprecision = 10000;
    uint256 totalProtocolCollateral;

    // interest accounting variables
    uint256 interestRate = 5; // 5.00%
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

    event InterestRateUpdated(uint256 oldRate, uint256 newRate);

    constructor(
        address _stableAddress,
        address _weth,
        address _ethOracleAddress
    ) Ownable(msg.sender) {
        i_stablecoin = STABLE(_stableAddress);
        weth = _weth;
        ethPriceOracle = MockEthOracle(_ethOracleAddress);
    }

    //////////////
    // External //
    //////////////
    /**
     * @notice Opens a new CDP position by depositing collateral and minting stablecoin debt
     * @dev Follows CEI pattern: Checks -> Effects -> Interactions
     * @dev Interest index is updated before position creation
     * @dev Position must maintain minimum collateralization ratio (MCR)
     * @dev User must have approved sufficient WETH tokens as collateral
     * @param _amount Amount of WETH collateral to deposit
     * @param _debtAmount Amount of stablecoin debt to mint
     * @dev Emits a PositionCreated event on successful creation
     * @dev Reverts if:
     *      - Amount is zero
     *      - User already has an open position
     *      - Resulting collateral ratio would be below MCR
     *      - Insufficient WETH allowance
     */
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
        IERC20(weth).safeTransferFrom(msg.sender, address(this), _amount); // @audit use safetransferFrom

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
     * @notice Closes a user's CDP position by repaying debt and redeeming collateral
     * @dev Follows CEI pattern: Checks -> Effects -> Interactions
     * @dev Interest is accrued before closing to ensure accurate debt calculation
     * @dev Position must be above MCR (Minimum Collateralization Ratio) to be closed
     * @dev User must have approved sufficient STABLE tokens to cover position debt
     * @dev Emits a PosotionClosed event on successful closure
     * @dev Reverts if:
     *      - User has no open position
     *      - Position is below MCR
     *      - Insufficient STABLE token allowance
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
        IERC20(i_stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            userDebt
        );

        _burnStable(userDebt);

        // Update state
        delete userPositions[msg.sender];
        totalProtocolCollateral -= userCollateral;
        // follow CEI pattern
        // Transfer collateral back to user
        _redeemCollateral(msg.sender, userCollateral);
        emit PosotionClosed(msg.sender, userCollateral, userDebt);
    }

    /**
     * @notice Liquidates an undercollateralized position, allowing liquidator to repay the debt and receive collateral
     * @dev The liquidator must have approved sufficient STABLE tokens to cover the position's debt
     * @dev Position must be below MCR (Minimum Collateralization Ratio) to be liquidatable
     * @dev Interest is accrued before liquidation to ensure accurate debt calculation
     * @dev Follows CEI pattern: Checks -> Effects -> Interactions
     * @param positionToLiquidate Address of the position owner to be liquidated
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
        IERC20(i_stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            userDebt
        );
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

    /**
     * @notice Updates the protocol interest rate
     * @param _newRate New interest rate (between 0-5)
     * @dev Rate is expressed as a whole number, e.g. 5 = 5.00%
     */
    function updateInterestRate(uint256 _newRate) external onlyOwner {
        _updateGlobalInterestIndex();
        if (_newRate > 5) {
            revert("Invalid interest rate");
        }
        uint256 oldRate = interestRate;
        interestRate = _newRate;
        emit InterestRateUpdated(oldRate, _newRate);
    }

    /**
     * @notice Updates the Minimum Collateralization Ratio (MCR)
     * @param _newMcr New MCR value (between 11000-15000, representing 110%-150%)
     * @dev MCR is expressed in basis points, e.g. 11000 = 110%
     */
    function updateMcr(uint256 _newMcr) external onlyOwner {
        if (_newMcr < 11000 || _newMcr > 15000) {
            revert("MCR must be between 110% and 150%");
        }
        uint256 oldMcr = MCR;
        MCR = _newMcr;
        emit McrUpdated(oldMcr, _newMcr);
    }

    event McrUpdated(uint256 oldMcr, uint256 newMcr);

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
     * @notice Updates the global interest index based on time elapsed since last update
     * @dev Uses simple interest formula: principal * (1 + rate * time)
     * @dev Interest rate is in percentage terms (e.g. 5 for 5%) and scaled by 100
     * @dev All calculations use 1e18 precision scaling to avoid rounding errors
     * @dev Formula: interestFactor = 1e18 + ((rate * timeElapsed * 1e18) / (365 days * 100))
     * @dev New index = (oldIndex * interestFactor) / 1e18
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
     * @notice Updates a user's debt by applying accrued interest based on the global interest index
     * @dev Uses the formula: currentDebt = originalDebt * (currentIndex / userLastIndex)
     * @dev If user has no debt, returns 0 without any updates
     * @param user The address of the user whose debt to update
     * @return The user's current debt amount after applying accrued interest
     *
     * This function:
     * 1. Retrieves the user's position
     * 2. If user has no debt, returns 0
     * 3. Calculates new debt by scaling original debt by ratio of current/last index
     * 4. Updates position with new debt and current index
     * 5. Returns the updated debt amount
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

    /**
     * @notice Checks if a position is eligible for liquidation based on its collateral ratio
     * @dev Uses the minimum collateralization ratio (MCR) as the liquidation threshold
     * @param collateralValue The USD value of the collateral in the position
     * @param debtAmount The amount of debt in the position
     * @return bool True if position can be liquidated (collateral ratio < MCR), false otherwise
     */
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

    /**
     * @notice Returns the current collateral ratio for a user's position
     * @param user The address of the user whose position to check
     * @return The collateral ratio of the user's position, scaled by ratioprecision
     */
    function getPositionCollateralRatio(
        address user
    ) public view returns (uint256) {
        Position memory position = userPositions[user];
        if (position.debtAmount == 0) return 0;

        uint256 collateralValue = _getCollateralUSDVaule(
            position.collateralAmount
        );
        return
            _getPositionCollateralRatio(collateralValue, position.debtAmount);
    }

    /**
     * @notice Returns the current debt amount for a user's position
     * @param user The address of the user whose debt to check
     * @return The debt amount for the user's position
     */
    function getUserDebt(address user) public view returns (uint256) {
        Position memory position = userPositions[user];
        return position.debtAmount;
    }

    /**
     * @notice Returns the total USD value of all collateral in the protocol
     * @return The total value of protocol collateral in USD terms
     */
    function getTotalCollateralValue() public view returns (uint256) {
        return _getCollateralUSDVaule(totalProtocolCollateral);
    }
}
