# BitFlow Stable Protocol

### Next-generation Bitcoin-collateralized stablecoin ecosystem on Stacks

---

## 📖 Overview

**BitFlow Stable** is a decentralized lending protocol built on the [Stacks blockchain](https://www.stacks.co/), enabling Bitcoin holders to unlock liquidity without selling their BTC. Users can deposit Bitcoin as collateral, mint USD-pegged stablecoins, and maintain BTC exposure while accessing on-chain liquidity.

The protocol integrates **real-time price oracles**, **dynamic collateralization ratios**, **automated liquidation protection**, and **interest accrual mechanisms** to ensure system-wide solvency and robust risk management.

BitFlow Stable bridges the Bitcoin economy with modern DeFi primitives, allowing BTC to function as productive collateral while retaining its long-term value proposition.

---

## 🏛️ System Overview

* **Collateralized Debt Positions (CDPs)**
  Users deposit BTC (satoshis) to open a CDP and borrow BitFlow’s native stablecoin (`stable-usd`).
  Each position tracks:

  * `collateral` (BTC amount locked)
  * `debt` (stablecoins borrowed)
  * `last-update-block` (interest checkpoint)

* **Stability & Risk Management**

  * **Collateral Ratio:** 150% minimum
  * **Liquidation Threshold:** 120%
  * **Liquidation Penalty:** 10% (allocated as protocol revenue)
  * **Interest Rate:** \~10% APR, compounded per block

* **Oracles**
  BTC/USD price feeds are managed via admin updates, with a **24h expiry window** to prevent stale data usage.

* **Stablecoin (stable-usd)**
  Fungible token minted when debt is created and burned when repaid.

* **Protocol Treasury**
  Collects stability fees and liquidation penalties for sustainability.

---

## ⚙️ Contract Architecture

The contract is organized into **core modules**:

### 1. **Error Handling**

Standardized error codes (`ERR-NOT-AUTHORIZED`, `ERR-INSUFFICIENT-COLLATERAL`, etc.) ensure predictable failure paths for dApp integrators.

### 2. **Protocol Configuration**

Constants define risk parameters, interest rates, and oracle timeouts. These can be adjusted via governance upgrades in future iterations.

### 3. **State Management**

* **Global variables** track:

  * Total debt
  * Total collateral
  * Accumulated stability fees
  * Last accrual block
* **User-level state**: Maintained in the `positions` map keyed by user principal.

### 4. **Core Functions**

* **Position Lifecycle**

  * `create-position`: Deposit BTC + mint stablecoins
  * `add-collateral`: Increase collateral backing
  * `repay-debt`: Burn stablecoins, unlock collateral
  * `withdraw-collateral`: Remove collateral safely
  * `liquidate-position`: Third-party liquidation of unsafe CDPs
* **Admin Controls**

  * `set-protocol-owner`: Ownership transfer
  * `pause-protocol`: Emergency circuit breaker
  * `update-btc-price`: Oracle price feed updates
* **Utilities**

  * `accrue-global-interest` / `accrue-position-interest`: Debt growth tracking
  * `get-current-price`: Validated oracle reads

### 5. **Public Queries**

* `get-position`: Fetch user’s position data
* `get-collateralization-ratio`: Compute CDP health
* `get-protocol-stats`: Aggregate system health snapshot

---

## 🔄 Data Flow

The protocol’s main lifecycle can be summarized as follows:

1. **Position Creation**

   * User deposits BTC collateral → Protocol verifies collateral ratio → Stablecoins are minted.

2. **Debt Accrual**

   * Over time, interest accumulates globally and per position, increasing outstanding debt.

3. **Debt Repayment**

   * User burns stablecoins → Debt decreases → If fully repaid, collateral is released.

4. **Collateral Withdrawal**

   * User requests BTC withdrawal → Protocol validates safe collateralization → Collateral is released.

5. **Liquidation**

   * If a position falls below the **120% threshold**, any participant can liquidate:

     * Liquidator burns stablecoins equal to the debt.
     * Protocol seizes collateral, pays liquidator (minus penalty).
     * Penalty allocated to protocol treasury.

---

## 📊 Example Parameters

* **Collateral Ratio:** 150%
* **Liquidation Threshold:** 120%
* **Interest Rate:** \~10% APR (per-block compounding)
* **Minimum Loan Size:** 100 stablecoins

---

## 🔐 Security Considerations

* Protocol is **owner-governed** at launch, with upgradeable controls for oracle and pause mechanics.
* Collateral safety is enforced via **oracle freshness checks** and **hard-coded ratios**.
* Emergency `pause-protocol` allows halting all interactions in case of exploit detection.

---

## 📜 License

This repository is licensed under the MIT License. See `LICENSE` for details.
