# Technical Documentation for ToyCDPEngine

The `ToyCDPEngine` contract is a basic Collateralized Debt Position (CDP) system that allows users to borrow a stablecoin ($Table) against their collateral (WETH). The contract facilitates the opening and closing of positions, as well as the liquidation of insolvent positions. The core functionality revolves around managing user positions, calculating collateralization ratios, and accounting for interest on borrowed amounts.

## Key Components

### 1. User Position Management

The `Position` struct represents a user's collateral and debt:

```solidity
struct Position {
uint256 collateralAmount; // Amount of collateral (WETH)
uint256 debtAmount; // Amount of debt (stablecoin)
uint256 userInterestIndex; // User's interest index for debt calculation
}
```

### 2. Interest Accounting

Interest is a critical aspect of the ToyCDPEngine, and it is accounted for using the following mechanisms:

#### 2.1 Interest Rate

The interest rate is defined as a percentage and is set by the contract owner. It can be updated through the `updateInterestRate` function:

```solidity
    function updateInterestRate(uint256 _newRate) external onlyOwner {
    if (_newRate > 5) {
    revert("Invalid interest rate");
    }
    uint256 oldRate = interestRate;
    interestRate = _newRate;
    emit InterestRateUpdated(oldRate, _newRate);
    }
```

#### 2.2 Interest Index

The `interestIndex` is a scaling factor used to calculate the effective debt amount for each user. It is updated periodically based on the elapsed time since the last update and the current interest rate.

#### 2.3 Global Interest Index Update

The `_updateGlobalInterestIndex` function calculates the new interest index based on the time elapsed since the last update:

```solidity
function _updateGlobalInterestIndex() internal {
uint256 timeElapsed = block.timestamp - lastInterestUpdate;
if (timeElapsed == 0) return;

    uint256 interestFactor = 1e18 +
        ((interestRate * timeElapsed * 1e18) / (365 days * 100));

    interestIndex = (interestIndex * interestFactor) / 1e18;
    lastInterestUpdate = block.timestamp;
}
```

- **Interest Factor Calculation**: The interest factor is calculated using the formula:
  \[
  \text{interestFactor} = 1 + \left(\frac{\text{interestRate} \times \text{timeElapsed}}{365 \text{ days} \times 100}\right)
  \]

- **Updating the Interest Index**: The global interest index is updated by multiplying the current index by the interest factor.

#### 2.4 User Debt Accrual

When a user interacts with their position (e.g., opening or closing), the `_accrueUserInterest` function is called to update their debt based on the current interest index:

```solidity
function _accrueUserInterest(address user) internal returns (uint256) {
Position storage position = userPositions[user];
if (position.debtAmount == 0) return 0;

    uint256 currentDebt = (position.debtAmount * interestIndex) /
        position.userInterestIndex;

    position.debtAmount = currentDebt;
    position.userInterestIndex = interestIndex;

    return currentDebt;

}
```

- **Debt Calculation**: The current debt is calculated by adjusting the user's debt amount based on the ratio of the current interest index to the user's last recorded interest index.

### 3. Collateral Management

The contract manages collateral through various functions:

- **Opening a Position**: Users can open a position by providing collateral and specifying the amount of debt they wish to incur. The system checks the collateralization ratio to ensure it meets the minimum collateralization requirement (MCR).

- **Closing a Position**: Users can close their positions by repaying their debt and receiving their collateral back. The system ensures that the position is solvent before allowing closure.

- **Liquidation**: If a user's position falls below the MCR, it can be liquidated by another user. The liquidator pays off the user's debt and receives the collateral.

### 4. Events

The contract emits several events to log important actions:

- `PositionCreated`: Emitted when a new position is opened.

- `PosotionClosed`: Emitted when a position is closed.

- `Liquidation`: Emitted when a position is liquidated.

- `InterestRateUpdated`: Emitted when the interest rate is updated.

- `McrUpdated`: Emitted when the minimum collateralization ratio is updated.

## Potential economic flaws and possible ways to fix them

### 1. Liquidation Incentives

Currently, liquidators must pay gas fees to perform liquidations, which may discourage participation in maintaining system health. Potential solutions:

- Implement a gas rebate mechanism for successful liquidations
- Add liquidation rewards/bonuses taken from the liquidated collateral
- Allow partial liquidations to make the process more capital efficient

### 2. Protocol Fee Structure

The current lack of fees creates potential issues:

- Flash loan attacks could be used to rapidly mint and burn STABLE for arbitrage
- No revenue generation for protocol maintenance and upgrades
- No incentive alignment between users and protocol

Recommendations:

- Add origination fees for opening positions (e.g. 0.5%)
- Include small fees on repayments (e.g. 0.1%)
- Consider dynamic fee scaling based on utilization

### 3. Interest Rate Mechanism

The fixed interest rate model has limitations:

- Does not respond to market conditions or utilization
- Could lead to protocol insolvency in high volatility periods
- No incentive for users to repay during market stress

Proposed improvements:

- Implement utilization-based interest rates
- Add rate multipliers during extreme market conditions
- Include stability fees that adjust based on STABLE peg deviation

### 4. System Safety

Critical safety mechanisms missing:

- No emergency shutdown procedure
- Lack of circuit breakers for extreme market moves
- No governance controls for system parameters

Required additions:

- Emergency pause functionality
- Gradual parameter adjustment limits
- Multi-signature controls for critical functions
- Circuit breakers tied to market volatility

### 5. Position Management

Current position management is limited:

- Users cannot partially close positions
- No ability to add collateral without borrowing more
- Cannot repay debt without closing position

Needed features:

- Partial position closure
- Collateral top-up functionality
- Flexible debt repayment options
- Position merging/splitting capabilities

### 6. Secondary Markets

The protocol would benefit from:

- Integration with DEXs for efficient STABLE trading
- Liquidation auctions for collateral
- Yield-generating opportunities for STABLE holders
- Insurance/protection markets for positions

These mechanisms would improve capital efficiency, risk management, and overall protocol sustainability.
