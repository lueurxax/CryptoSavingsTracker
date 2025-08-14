# QuickNode API: Balances & Transactions (JSON-RPC)

> This document outlines the integration of QuickNode API for fetching blockchain balances and transaction history using JSON-RPC methods. QuickNode provides high-performance access to various blockchain networks.

---

## Authentication & Base

- **Base URL:** `https://<YOUR_QUICKNODE_ENDPOINT>/` (Replace `<YOUR_QUICKNODE_ENDPOINT>` with the specific endpoint URL provided by QuickNode for your node. This URL typically includes your API key.)
- **Method:** `POST`
- **Content-Type:** `application/json`

---

## 1) Ethereum (ETH)

### 1.1 Native ETH Balance (`eth_getBalance`)

This method returns the native ETH balance of an account in wei.

**Method:** `eth_getBalance`

**Parameters:**
- `address`: The Ethereum address (20 bytes) for which to check the balance.
- `blockNumber`: The block number in hexadecimal format, or a string like "latest", "earliest", "pending", "safe", or "finalized".

**Examples**

```bash
# Get native ETH balance for an address
curl --request POST \
  --url 'https://<YOUR_QUICKNODE_ENDPOINT>/' \
  --header 'Content-Type: application/json' \
  --data '{ "jsonrpc": "2.0", "method": "eth_getBalance", "params": ["0x8D97689C9818892B700e27F316cc3E41e17fBeb9", "latest"], "id": 1 }'
```

### 1.2 ERC-20 Token Balances (`qn_getWalletTokenBalance`)

This QuickNode-specific RPC method fetches ERC-20 token balances for a specific wallet. Requires the Token API add-on.

**Method:** `qn_getWalletTokenBalance`

**Parameters:**
- `walletAddress`: The wallet address for which to fetch token balances.
- `contractAddresses`: (Optional) An array of contract addresses to filter by. If omitted, returns all token balances.

**Examples**

```bash
# Get all ERC-20 token balances for a wallet
curl --request POST \
  --url 'https://<YOUR_QUICKNODE_ENDPOINT>/' \
  --header 'Content-Type: application/json' \
  --data '{ "jsonrpc": "2.0", "method": "qn_getWalletTokenBalance", "params": [{"wallet": "0x8D97689C9818892B700e27F316cc3E41e17fBeb9"}], "id": 1 }'

# Get specific ERC-20 token balances for a wallet (e.g., USDT, USDC)
curl --request POST \n  --url 'https://<YOUR_QUICKNODE_ENDPOINT>/' \n  --header 'Content-Type: application/json' \n  --data '{ "jsonrpc": "2.0", "method": "qn_getWalletTokenBalance", "params": [{"wallet": "0x8D97689C9818892B700e27F316cc3E41e17fBeb9"}, ["0xdAC17F958D2ee523a2206206994597C13D831ec7", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"]], "id": 1 }'
```

### 1.3 Transaction History

Retrieving a complete transaction history for an Ethereum address is complex due to the nature of the blockchain. There isn't a single standard RPC method that directly provides all transactions for an address.

**Approaches:**
- **Iterating through each block:** Programmatically go through each block and check for transactions related to the address. This can be time-consuming and resource-intensive, often requiring an Archive node.
- **Using an indexing service:** Utilize APIs from services like Etherscan (though they might have limitations).
- **QuickNode's Trace Mode add-on:** For transactions where an address was part of a trace call, QuickNode provides a "Trace Mode" add-on for your blockchain node.

**To get details for a specific transaction (if you have the transaction hash):**

**Method:** `eth_getTransactionByHash`

**Parameters:**
- `transactionHash`: The hash of the transaction.

**Examples**

```bash
# Get details for a specific transaction
curl --request POST \n  --url 'https://<YOUR_QUICKNODE_ENDPOINT>/' \n  --header 'Content-Type: application/json' \n  --data '{ "jsonrpc": "2.0", "method": "eth_getTransactionByHash", "params": ["0xYourTransactionHashHere"], "id": 1 }'
```

---

## 2) Bitcoin (BTC)

QuickNode supports Bitcoin via JSON-RPC. The methods are similar to `bitcoind` RPC calls.

### 2.1 Address Balance (`getaddressinfo` or `listunspent`)

To get the balance of a Bitcoin address, you can use `getaddressinfo` (which provides general address info including balance) or `listunspent` (to get UTXOs, which can then be summed for balance).

**Method:** `getaddressinfo`

**Parameters:**
- `address`: The Bitcoin address.

**Examples**

```bash
# Get Bitcoin address info (including balance)
curl --request POST \n  --url 'https://<YOUR_QUICKNODE_ENDPOINT>/' \n  --header 'Content-Type: application/json' \n  --data '{ "jsonrpc": "1.0", "method": "getaddressinfo", "params": ["1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"], "id": 1 }'
```

### 2.2 Transaction History

Similar to Ethereum, getting a full transaction history for Bitcoin via RPC can be complex. You typically need to iterate through blocks or use an indexing solution.

**To get details for a specific transaction (if you have the transaction hash):**

**Method:** `getrawtransaction` (followed by `decoderawtransaction` for human-readable format)

**Parameters:**
- `txid`: The transaction hash.
- `verbose`: (Optional) Set to `true` for verbose output.

**Examples**

```bash
# Get raw transaction details
curl --request POST \
  --url 'https://<YOUR_QUICKNODE_ENDPOINT>/' \
  --header 'Content-Type: application/json' \
  --data '{ "jsonrpc": "1.0", "method": "getrawtransaction", "params": ["YourTransactionHashHere", true], "id": 1 }'
```

---

## Notes

- QuickNode primarily uses JSON-RPC methods. Ensure your requests are `POST` with `Content-Type: application/json`.
- Balances are often returned in the smallest units (e.g., wei for ETH, satoshis for BTC). Convert as needed for display.
- Some advanced features (like `qn_getWalletTokenBalance` or Trace Mode) may require specific QuickNode add-ons.
- Always refer to the official QuickNode documentation for the most up-to-date and comprehensive information on supported chains and methods.
