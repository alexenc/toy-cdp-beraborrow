## Goals

1. make a cdp protocol that uses ETH as collateral and mints $Table overcolletarized stable coin
2. The stability mechanism is both algorithinc and incentiviced by Irates of borrowing $table
3. multile users can create positions
4. positions can be closed
5. positions can ve liquidated at 110% LTV

## System overview

Toy CDP is a CDP protocol that allows users to borrow the stable coin STABLE by depositing overcolletarized WETH at a minimum ratio of 110%. The system allows user to create and close positions, positions that falls below the 110% ltv ratio are subsceptible to be liquidated.

Also theres a global interes rate charged to borrowers the initial value is a 5% annual rate.

## How interest rates are accounted

To keep track in an efficient way of interest accrued Toy CDP uses a global interest index methodology, this allows to manage interes accross all the users without having to update each user position.
to do so the system has the global `ìnterestIndex` variable that represents the total growth factor for the entire protocol's bebt

`interestRate` this variable is the actual interest rate of the protocol, at the time of deployment the interest rate for borrowing is a 2%.

`lastInterestUpdate` represents the timestamp when the interestIndex was last updated

When a user position is created it keeps track of the cumulative interexIndex of that user position each time the protocol interacts with the user possition new accrued debt is calculated.

## Potential economic flaws and possible ways to fix them

1. gas sponsor to the liquidators
2. fees on borrowing + repaying to avoid minting and burnign cascade effects due to arbitraje
3. interest rate manipulation depending on market conditions
4. System recovery mode
