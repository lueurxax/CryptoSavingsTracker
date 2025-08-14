# Nownodes API: Balances & Transactions

> This document outlines the integration of Nownodes API for fetching blockchain balances and transaction history. Nownodes serves as an alternative or fallback integration for various chains.

---

## Authentication & Base

- **Base URL:** `https://<NODE_NAME>-blockbook.nownodes.io/api/v2` (Replace `<NODE_NAME>` with the specific blockchain, e.g., `eth`, `trx`. For Bitcoin, use `https://btcbook.nownodes.io/api/v2`)
- **Header:** `api-key: <YOUR_API_KEY>`

---

## 1) Bitcoin (BTC)

### 1.1 Address Balance

**GET** `/address/{address}`

**Notes:** The response for this endpoint includes the address balance and a list of transaction IDs (`txids`). You can use these IDs to fetch individual transaction details.

**Examples**

```bash
# BTC balance for an address
curl --request GET \
  --url "https://btcbook.nownodes.io/api/v2/address/1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa" \
  --header "api-key: $NOWNODES_API_KEY"
```

### 1.2 Address Balance History

**GET** `/balancehistory/{address}`

**Notes:** This endpoint provides a historical overview of the address balance, including transaction counts and received/sent amounts over time.

**Examples**

```bash
# BTC balance history for an address
curl --request GET \
  --url "https://btcbook.nownodes.io/api/v2/balancehistory/1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa" \
  --header "api-key: $NOWNODES_API_KEY"
```

---

## 2) Ethereum (ETH) & ERC-20

### 2.1 Address Balance (Native ETH)

**GET** `/address/{address}`

**Notes:** The response for this endpoint includes the address balance and a list of transaction IDs (`txids`). You can use these IDs to fetch individual transaction details.

**Examples**

```bash
# ETH balance for an address
curl --request GET \
  --url "https://eth-blockbook.nownodes.io/api/v2/address/0xYourWallet" \
  --header "api-key: $NOWNODES_API_KEY"
```

### 2.2 ERC-20 Token Balance

**GET** `/address/{address}/tokens`

**Notes:** This endpoint returns a list of all tokens for the given address. You will need to filter the response by the specific `tokenAddress` (contract address) to get the balance for a particular ERC-20 token.

**Examples**

```bash
# Get all ERC-20 token balances for an address
curl --request GET \
  --url "https://eth-blockbook.nownodes.io/api/v2/address/0xYourWallet/tokens" \
  --header "api-key: $NOWNODES_API_KEY"
```


### 2.3 Address Balance History

**GET** `/balancehistory/{address}`

**Notes:** This endpoint provides a historical overview of the address balance, including transaction counts and received/sent amounts over time.

**Examples**

```bash
# ETH balance history for an address
curl --request GET \
  --url "https://eth-blockbook.nownodes.io/api/v2/balancehistory/0xYourWallet" \
  --header "api-key: $NOWNODES_API_KEY"
```









---

## 3) TRON (TRX, TRC-20)

### 3.1 Address Balance (Native TRX)

**GET** `/address/{address}`

**Notes:** The response for this endpoint includes the address balance and a list of transaction IDs (`txids`). You can use these IDs to fetch individual transaction details.

**Examples**

```bash
# TRX balance for an address
curl --request GET \
  --url "https://trx-blockbook.nownodes.io/api/v2/address/TYourAddress" \
  --header "api-key: $NOWNODES_API_KEY"
```

### 3.2 TRC-20 Token Balance

**GET** `/address/{address}/tokens`

**Notes:** This endpoint returns a list of all tokens for the given address. You will need to filter the response by the specific `tokenAddress` (contract address) to get the balance for a particular TRC-20 token.

**Examples**

```bash
# Get all TRC-20 token balances for an address
curl --request GET \
  --url "https://trx-blockbook.nownodes.io/api/v2/address/TYourAddress/tokens" \
  --header "api-key: $NOWNODES_API_KEY"
```


### 3.3 Address Balance History

**GET** `/balancehistory/{address}`

**Notes:** This endpoint provides a historical overview of the address balance, including transaction counts and received/sent amounts over time.

**Examples**

```bash
# TRX balance history for an address
curl --request GET \
  --url "https://trx-blockbook.nownodes.io/api/v2/balancehistory/TYourAddress" \
  --header "api-key: $NOWNODES_API_KEY"
```







---

## Notes

- Values are typically returned in the smallest units (e.g., satoshis for BTC, wei for ETH, sun for TRX). Convert as needed for display.
- Ensure your Nownodes API key has access to the desired blockchains.
- To fetch individual transaction details, use the `/tx/{txid}` endpoint (e.g., `https://btcbook.nownodes.io/api/v2/tx/{txid}`).
- For other chains, refer to the official Nownodes documentation for specific endpoints and parameters.
