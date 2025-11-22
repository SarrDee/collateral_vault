# Collateral Vault

A programmable collateral vault smart contract on Stacks with automated risk shields and dynamic collateral ratios.

## Overview

The Collateral Vault is a DeFi primitive that allows users to:
- **Deposit** STX as collateral
- **Borrow** against their collateral at a configurable collateralization ratio
- **Repay** loans to reclaim collateral
- **Liquidate** unsafe positions when collateral falls below required ratio

An oracle controls the risk shield (collateral ratio) to dynamically adjust protocol risk based on market conditions.

## Key Features

### 🛡️ Dynamic Risk Shields
- Oracle-controlled collateral ratio adjustments
- Prevents extreme risk spikes with configurable max-step (default: 20%)
- Ratio locked at minimum 150% collateralization on initialization

### 💰 Core Operations
- **Deposit**: Users deposit STX as collateral
- **Borrow**: Borrow STX if collateralization ratio is maintained
- **Repay**: Repay loans partially or fully
- **Liquidate**: Public liquidation mechanism with 5% reward incentive

### 🔐 Security
- Oracle-only functions for risk parameter updates
- Input validation on all user-facing functions
- Collateralization checks before allowing borrows
- Liquidation only allowed on unsafe positions

## Contract Functions

### Public Functions

#### `deposit(amount: uint) -> (response uint uint)`
Deposit STX as collateral.
```clarity
(deposit u1000000) ;; Deposit 1 STX (in microSTX)
