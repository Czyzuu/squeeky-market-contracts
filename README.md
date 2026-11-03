# Squeeky Market — Solidity contracts

Smart contracts for [Squeeky Market](https://hamster.squeekymarket.trade), an independent community prediction market on Squeektoshi’s daily wheel distance.

Players trade distance thresholds and final-distance ranges with free test tokens on Ethereum Sepolia. The app reads Squeekchain’s public wheel telemetry; an authorized reporter submits distance reports to these contracts. The contracts do not read the API or verify hardware signatures themselves. A guardian can correct or invalidate a report during its dispute period before final payouts are set, and can file the report itself if the reporter stays silent for a day after a market ends.

This repository contains the Solidity contracts, contract tests and public deployment addresses. The hosted app also uses a separate web frontend, matching engine and telemetry service. This is a play-money testnet prototype, not an audited production protocol. It is not affiliated with Squeekchain and was developed independently of IMD.

## Contracts

| Contract | Purpose |
|---|---|
| [MockUSDC](contracts/src/MockUSDC.sol) | Six-decimal test collateral with a free faucet. |
| [ConditionalTokens](contracts/src/ConditionalTokens.sol) | ERC-1155 outcome positions, collateral split/merge, redemption and withdrawals. |
| [DistanceOracle](contracts/src/DistanceOracle.sol) | Binary thresholds and distance buckets, reporting, guardian overrides, dispute periods and final payouts. |
| [Exchange](contracts/src/Exchange.sol) | Operator-submitted matches of EIP-712 orders, partial fills, cancellations, fees and complementary outcome mint/merge. |
| [NegRiskAdapter](contracts/src/NegRiskAdapter.sol) | Conversions between complementary positions in multi-outcome markets. |

Binary thresholds can report early once distance strictly exceeds their line. Bucket markets wait until their window ends. The hosted daily markets use UTC noon-to-noon windows. Winning positions become redeemable after reporting, the dispute period and finalization.

The exchange retains the EIP-712 signing-domain name `Wheel Markets`, version `1`, for compatibility with its existing Sepolia deployment. The public product is named Squeeky Market.

## Build and test

Requires Node.js 22+ and npm. Foundry’s platform binary is installed through npm; the first build downloads Solidity 0.8.30.

```sh
npm ci
npm run build
npm test
```

The tests cover fills, fees, complementary mint/merge, nonce and order cancellation, signatures across chains, access controls, time-in-force policies, disputes and guardian corrections, reporter fallback, fresh-market minting, bucket settlement, winner claims, rounding, fuzzed collateral conservation and a collateral invariant. Each audit finding below has a regression test.

## Audit

An [IMD agent swarm audit](https://explorer.imd.fun/jobs/bc92d588-9ac0-478e-8538-a4e73ea93727?hired=audit) reviewed commit `249ed72` and reported 9 findings (1 high, 1 medium, 3 low, 4 info). Eight are fixed in `fa8c119` and the contracts were redeployed on 2026-11-03; the addresses below are the fixed deployment.

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | High | Guardian could not correct or invalidate a wrong early report | Fixed |
| 2 | Medium | First complementary mint on a fresh market reverted | Fixed: `prepare` registers positions; `registerPosition` for unions |
| 3 | Low | FOK/IOC enforced only on the taker slot | Fixed |
| 4 | Low | Notional could floor to zero | Fixed: fill amounts in steps of 100 |
| 5 | Low | No resolution path if the reporter never reports | Fixed: guardian fallback after `REPORT_GRACE` (1 day) |
| 6 | Info | Each override restarted the dispute clock | Fixed: capped at `max(pending, end + dispute)` |
| 7 | Info | `uint64` cast of the finalize time could wrap | Fixed: dispute delay at most 30 days |
| 8 | Info | Per-mask rounding stranded dust on redemption | Fixed |
| 9 | Info | Operator decides who keeps the crossing surplus | Accepted: documented operator trust |

## Sepolia deployment

Chain ID: **11155111**. Addresses are also available in [deployments/sepolia.json](deployments/sepolia.json).

| Contract | Address |
|---|---|
| MockUSDC | [0x6E12af8551142976a09400DB67A2da18C12E1fD6](https://sepolia.etherscan.io/address/0x6E12af8551142976a09400DB67A2da18C12E1fD6) |
| ConditionalTokens | [0x34D16477A8A31E343396914B5848DC3e961d4381](https://sepolia.etherscan.io/address/0x34D16477A8A31E343396914B5848DC3e961d4381) |
| DistanceOracle | [0xcfCDB77AE102a9A314ACdC4e9043BA969bfDd174](https://sepolia.etherscan.io/address/0xcfCDB77AE102a9A314ACdC4e9043BA969bfDd174) |
| Exchange | [0x434ADdEf3c86150DAB598dEEeb8d7BD61d34A8c4](https://sepolia.etherscan.io/address/0x434ADdEf3c86150DAB598dEEeb8d7BD61d34A8c4) |
| NegRiskAdapter | [0x1A76af44B6014735DE5Bb8D0ee909dbB739E31c8](https://sepolia.etherscan.io/address/0x1A76af44B6014735DE5Bb8D0ee909dbB739E31c8) |

Solidity source files use the MIT SPDX license identifier; dependencies retain their own licenses.

squeekchain-project: 69db1da2-6a9c-4433-970e-6d8cbd307678
