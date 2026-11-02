# Squeeky Market — Solidity contracts

Smart contracts for [Squeeky Market](https://hamster.squeekymarket.trade), an independent community prediction market on Squeektoshi’s daily wheel distance.

Players trade distance thresholds and final-distance ranges with free test tokens on Ethereum Sepolia. The app reads Squeekchain’s public wheel telemetry; an authorized reporter submits distance reports to these contracts. The contracts do not read the API or verify hardware signatures themselves. A guardian can override reports during a dispute period before final payouts are set.

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

The tests cover fills, fees, complementary mint/merge, nonce and order cancellation, signatures across chains, access controls, time-in-force policies, disputes, bucket settlement, winner claims, fuzzed collateral conservation and a collateral invariant.

## Sepolia deployment

Chain ID: **11155111**. Addresses are also available in [deployments/sepolia.json](deployments/sepolia.json).

| Contract | Address |
|---|---|
| MockUSDC | [0x6E12af8551142976a09400DB67A2da18C12E1fD6](https://sepolia.etherscan.io/address/0x6E12af8551142976a09400DB67A2da18C12E1fD6) |
| ConditionalTokens | [0xFB1588ee34cfd7Dcb9F60681746D6209ee82c54E](https://sepolia.etherscan.io/address/0xFB1588ee34cfd7Dcb9F60681746D6209ee82c54E) |
| DistanceOracle | [0x7748d1d99036a8F7a82e63c99DDFDBCD32BDC5DB](https://sepolia.etherscan.io/address/0x7748d1d99036a8F7a82e63c99DDFDBCD32BDC5DB) |
| Exchange | [0x95eAaE865eC67cBC9F7dF51DfEdb31F63d4B0A0b](https://sepolia.etherscan.io/address/0x95eAaE865eC67cBC9F7dF51DfEdb31F63d4B0A0b) |
| NegRiskAdapter | [0xf6CE0561681A57613fC7Da02151b7E8D417E8BB0](https://sepolia.etherscan.io/address/0xf6CE0561681A57613fC7Da02151b7E8D417E8BB0) |

Solidity source files use the MIT SPDX license identifier; dependencies retain their own licenses.
