# API Integrations

This document provides an overview of the external APIs used in the CryptoSavingsTracker application.

## CoinGecko API

- **Purpose**: Used to fetch cryptocurrency exchange rates.
- **Endpoint**: `https://api.coingecko.com/api/v3/simple/price`
- **Service**: `CoinGeckoService.swift`

## Tatum API

- **Purpose**: Used to fetch blockchain data, such as account balances and transaction histories.
- **Service**: `TatumService.swift`

## QuickNode API

- **Purpose**: Used as a fallback for fetching blockchain data.
- **Service**: `TatumService.swift` (via `TatumClient`)

## Nownodes API

- **Purpose**: Used as a fallback for fetching blockchain data.
- **Service**: `TatumService.swift` (via `TatumClient`)

---

## Tatum API

- **Website**: [tatum.io](https://tatum.io)
- **Primary Use**: Blockchain data access (balances, transactions).
- **API Key Location**: `Config.plist` -> `TATUM_API_KEY`

### Implementation Details

- The `TatumClient` class in `TatumClient.swift` is responsible for making requests to the Tatum API.
- The `TatumService` class in `TatumService.swift` uses the `TatumClient` to fetch data.

---

## QuickNode API

- **Website**: [quicknode.com](https://www.quicknode.com)
- **Primary Use**: Fallback blockchain data access.
- **API Key Location**: `Config.plist` -> `QUICKNODE_API_KEY`

### Implementation Details

- QuickNode is used as a fallback provider within the `TatumClient` when the primary Tatum API fails.

---

## Nownodes API

- **Website**: [nownodes.io](https://nownodes.io)
- **Primary Use**: Fallback blockchain data access.
- **API Key Location**: `Config.plist` -> `NOWNODES_API_KEY`

### Implementation Details

- Nownodes is used as a fallback provider within the `TatumClient` when both the primary Tatum API and QuickNode fail.
