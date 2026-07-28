# API Integrations

> External APIs used for exchange rates, blockchain balances, and transaction history

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-07-28 |
| Platform | Shared |
| Audience | Developers |

---

## CoinGecko

CoinGecko provides exchange rates through
`https://api.coingecko.com/api/v3/simple/price`.

- Apple entry points: `ExchangeRateService` and `CoinGeckoService`.
- Android entry point: `ExchangeRateRepositoryImpl`.
- Missing, malformed, non-finite, or non-positive rates remain unavailable;
  financial consumers must not substitute `1` or `0`.
- Calculation and persistence boundaries carry immutable rate evidence and
  revalidate it after asynchronous work.

## Tatum

Tatum is the only configured blockchain provider. QuickNode and Nownodes are
not runtime fallbacks in the current implementation.

- Apple request/client layer: `TatumClient`, `TatumService`, and
  `TatumModels`.
- Apple balance/import layer: `BalanceService` and
  `OnChainTransactionImportService`.
- Android request layer: `TatumApi`.
- Android balance/import layer: `OnChainBalanceRepositoryImpl` and
  `OnChainTransactionRepositoryImpl`.

### Routing contract

- Native EVM balances use the documented V4 native-balance route.
- Canonical EVM tokens use wallet portfolio with contract validation and
  bounded offset pagination.
- EVM history requests declare native or fungible type and, for tokens, the
  canonical contract. Returned movements are validated locally again.
- BTC, LTC, BCH, DOGE, Cardano, TRON, Solana, and XRP use their chain-specific
  endpoint, authentication, pagination, identity, and address-normalization
  contracts.
- Unsupported currency/network/contract combinations fail before cache access
  or persistence.

### EVM receipt and reconciliation contract

The Android importer obtains the authoritative transaction receipt with
`eth_getTransactionReceipt` when success status or gas evidence is required.
Receipt status, `gasUsed`, and `effectiveGasPrice` must be present and valid;
failed transactions may still consume gas and are not treated as successful
asset movements.

Provider corrections and later enrichment reconcile to the installed durable
movement identity. Optional event indices, UTXO aliases, legacy external IDs,
and same-batch enrichment are accepted only when they identify exactly one
movement in the same asset scope. Ambiguous, cross-asset, truncated, or
conflicting provider data fails closed and leaves the last durable history
unchanged.

Primary contracts:

- [Tatum V4 transaction history](https://docs.tatum.io/reference/gettransactionhistoryv4)
- [Tatum transaction by hash](https://docs.tatum.io/reference/gettransactionblockchainsapi)
- [Tatum EVM transaction receipt RPC](https://docs.tatum.io/reference/rpc-ethereum-eth_gettransactionreceipt)
- [Ethereum receipt schema](https://ethereum.github.io/execution-apis/api/methods/eth_getTransactionReceipt/)

## Credentials

- Apple reads `TatumAPIKey` from `Config.plist`, migrates a configured value to
  Keychain, and sends the endpoint-specific Tatum authentication header.
- Android imports `TatumAPIKey` through `ApiKeyStore`; Settings writes it to
  encrypted storage.
- CoinGecko and Tatum keys must never be committed. Use
  `Config.example.plist` or local configuration only.
