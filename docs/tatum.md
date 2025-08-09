# Tatum API: Balances & Transactions (ETH first; TRX tokens; others by specific routes)

> Focus first on **Ethereum & ERC‑20** using the new, non‑deprecated ``. For **TRON** stablecoins (USDT/USDC), use the **v3 TRON** routes. For BTC, SOL, ADA, and XRP, use the chain‑specific balance endpoints and examples below.

---

## Authentication & Base

- **Base URL:** `https://api.tatum.io`
- **Header:** `x-api-key: <YOUR_API_KEY>`

---

## 1) Ethereum & ERC‑20 (Primary)

### 1.1 Address transaction history (new API)

**GET** `/v4/data/transaction/history`

**Query params**

- `chain=ethereum`
- `addresses=<comma-separated addresses>`
- Optional: `tokenAddress=<ERC-20 contract>`, `blockFrom`, `blockTo`, `page`, `pageSize`

**Examples**

```bash
# All txs for an ETH address
curl --request GET \
  --url "https://api.tatum.io/v4/data/transaction/history?chain=ethereum&addresses=0xYourWallet&pageSize=50&page=1" \
  --header "x-api-key: $TATUM_API_KEY"

# Only USDT transfers (ERC-20)
curl --request GET \
  --url "https://api.tatum.io/v4/data/transaction/history?chain=ethereum&addresses=0xYourWallet&tokenAddress=0xdAC17F958D2ee523a2206206994597C13D831ec7" \
  --header "x-api-key: $TATUM_API_KEY"

# Only USDC transfers (ERC-20)
curl --request GET \
  --url "https://api.tatum.io/v4/data/transaction/history?chain=ethereum&addresses=0xYourWallet&tokenAddress=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" \
  --header "x-api-key: $TATUM_API_KEY"
```

### 1.2 Balances (ETH + ERC‑20)

- **Native ETH:**

```bash
curl --request GET \
  --url "https://api.tatum.io/v3/ethereum/account/balance/0xYourWallet" \
  --header "x-api-key: $TATUM_API_KEY"
```

- **ERC‑20 balance:**

```bash
curl --request GET \
  --url "https://api.tatum.io/v3/blockchain/token/balance/ethereum/0xdAC17F958D2ee523a2206206994597C13D831ec7/0xYourWallet" \
  --header "x-api-key: $TATUM_API_KEY"
```

---

## 2) TRON (TRX, USDT, USDC)

> The new `/v4/data/transaction/history` does **not** support TRON. Use the **v3 TRON** routes.

### 2.1 TRON account transactions (mixed)

```bash
curl --request GET \
  --url "https://api.tatum.io/v3/tron/transaction/account/TYourAddress" \
  --header "x-api-key: $TATUM_API_KEY"
```

### 2.2 TRC‑20 transfers only

```bash
curl --request GET \
  --url "https://api.tatum.io/v3/tron/transaction/account/TYourAddress/trc20" \
  --header "x-api-key: $TATUM_API_KEY"
```

**TRC‑20 contracts**

- **USDT (TRON):** `TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`
- **USDC (TRON):** `TEkxiTehnzSmSe2XqrBj4w32RUN966rdz8`

---

## 3) Other Currencies (specific routes)

### 3.1 BTC

- **Balance:** `GET /v3/bitcoin/address/balance/{address}`
- **Transaction history:** GET /v3/bitcoin/transaction/address/{address}

Params: pageSize, page

Examples

# BTC balance
```bash
curl --request GET \
  --url "https://api.tatum.io/v3/bitcoin/address/balance/bc1q7yckywxgxhqr49xkx5ynwucfqzu23ektf7qynp" \
  --header "x-api-key: $TATUM_API_KEY"
```
# BTC transactions (latest first)
```bash
curl --request GET \
  --url "https://api.tatum.io/v3/bitcoin/transaction/address/bc1q7yckywxgxhqr49xkx5ynwucfqzu23ektf7qynp?pageSize=2&page=1" \
  --header "x-api-key: $TATUM_API_KEY"


```

### 3.2 SOL

- **Balance:** `GET /v3/solana/account/balance/{address}`
- **Transaction by signature:** `GET /v3/solana/transaction/{signature}`
- **List signatures (then fetch each tx):** Use Solana RPC `getSignaturesForAddress` to page signatures; then call the transaction endpoint per signature.

**Examples**

```bash
# SOL balance
curl --request GET \
  --url "https://api.tatum.io/v3/solana/account/balance/YourSolAddress" \
  --header "x-api-key: $TATUM_API_KEY"

# Fetch a Solana transaction by signature
curl --request GET \
  --url "https://api.tatum.io/v3/solana/transaction/5ZfZxkY4u7...ReplaceWithSignature" \
  --header "x-api-key: $TATUM_API_KEY"
```

> Tip: Get signatures with Solana RPC `getSignaturesForAddress` (paginate with `before` / `until`), then resolve each via `/v3/solana/transaction/{signature}`.

### 3.3 ADA

- **Transaction history by address:** `GET /v3/ada/transaction/address/{address}`
  - Params: `pageSize` (1–50), optional `page`
- **Block by hash (for timestamp):** `GET /v3/ada/block/{hash}` → use `forgedAt` as the block time
- **Balance:** `GET /v3/cardano/account/balance/{address}` (kept for completeness)

**Working examples (from testing):**

```bash
# ADA transactions by address (returns inputs/outputs & block hash/number)
curl --request GET \
     --url 'https://api.tatum.io/v3/ada/transaction/address/addr1q96slkwgxkczvrtalknyryq893z5xpgw3m5p3s2kvcd2m4je57dvk67ygd2u8ef8e2pvqmu8ggqls8nj44ycl9qhl3mqcjjuuv?pageSize=20' \
     --header 'accept: application/json' \
     --header "x-api-key: $TATUM_API_KEY"

# Fetch the block to get the transaction date/time (forgedAt)
curl --request GET \
     --url 'https://api.tatum.io/v3/ada/block/e8da9b41e0d5b111dc9fcc0826cfac9d8ac9ea0ade866061e1a8c0a6b1cd87b2' \
     --header 'accept: application/json' \
     --header "x-api-key: $TATUM_API_KEY"
```

> Use the `block.hash` (e.g., `e8da9b...`) from the transaction list to retrieve `forgedAt`, which you can treat as the transaction date/time for display.

### 3.4 XRP

- **Account balance:** `GET /v3/xrp/account/{address}/balance` 
- **Transaction history (paginated):** `GET /v3/xrp/account/tx/{address}`
  - Query params: `min` (starting ledger index; use `-1` for newest), optional `marker` for pagination

**Examples**

```bash
# XRP balance
curl --request GET \
  --url "https://api.tatum.io/v3/xrp/account/rYourXrpAddress/balance" \
  --header "x-api-key: $TATUM_API_KEY"

# Response format:
# {
#   "balance": "61114498",    // Balance in drops (1 XRP = 1,000,000 drops)
#   "assets": []
# }

# XRP transactions (latest first)
curl --request GET \
  --url "https://api.tatum.io/v3/xrp/account/tx/rYourXrpAddress?min=-1" \
  --header "x-api-key: $TATUM_API_KEY"

# Next page using marker from previous response
curl --request GET \
  --url "https://api.tatum.io/v3/xrp/account/tx/rYourXrpAddress?min=-1&marker=<MARKER_FROM_PREVIOUS_RESPONSE>" \
  --header "x-api-key: $TATUM_API_KEY"
```

**Notes**

- Amounts are in **drops** (1 XRP = 1,000,000 drops). Convert as needed.
- XRPL timestamps are in **XRPL epoch seconds**; convert to Unix by adding **946684800**, then to ISO date.

## Stablecoin Contracts (reference)

- **USDT (ETH):** `0xdAC17F958D2ee523a2206206994597C13D831ec7`
- **USDC (ETH):** `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- **USDT (TRON):** `TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`
- **USDC (TRON):** `TEkxiTehnzSmSe2XqrBj4w32RUN966rdz8`

---

## Notes

- Values come in smallest units (wei, satoshis, lamports, drops, etc.).
- For TRON `/trc20` endpoint, filter by `contract` for USDT/USDC.
- EVM chains other than ETH (BSC, Polygon, Base, Arbitrum, Optimism, Celo, Chiliz, Unichain) are supported by `/v4/data/transaction/history` with `chain=<evm>`.


