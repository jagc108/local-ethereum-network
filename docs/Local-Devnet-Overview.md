# Local Ethereum Devnet (Simple Explanation)

This document explains, in plain language, what this repo runs and why each part exists.

---

## What is Ethereum in one paragraph?
Think of Ethereum as a **shared spreadsheet** that many computers keep in sync.  
New “rows” are added continuously. Each row is a **block**.  
All computers agree on the same history and the current balances/state.

---

## What does this repo run?
This repo runs a **local Ethereum network** on your machine using Docker:

1) **Validator pair (Execution + Consensus)**
   - **Nethermind (Execution Layer / EL)**  
     Executes transactions and keeps the “current balances.”
   - **Teku (Consensus Layer / CL)**  
     Decides *which* block is valid and when to propose it.

   Together they **produce blocks** continuously.

2) **Archive pair (Execution + Consensus)**
   - **Nethermind Archive (EL)**  
     Stores full historical state (no pruning).  
     You can query “What was the balance at block X?”
   - **Teku Archive (CL)**  
     Follows the same chain so the archive stays consistent.

---

## Why do we need both EL and CL?
Ethereum uses two layers:
- **Consensus Layer (CL)** decides *which* block should be added.
- **Execution Layer (EL)** actually *executes* the transactions in that block.

They talk over a secure local channel using a **JWT secret**.

---

## What makes it an “archive node”?
Normal nodes delete old state to save disk.  
An **archive** node keeps **all** historical state.  
That means you can ask:
- “What was the balance at block 0?”
- “What did this contract look like 1,000 blocks ago?”

---

## What makes this reproducible?
Everything is built from scripts:
- **Genesis generation**: creates the chain “birth certificate”
- **Key generation**: creates validator keys
- **JWT generation**: secure EL/CL communication
- **Docker Compose**: starts all services
- **Peer wiring**: forces Teku nodes to discover each other

You can wipe and recreate the network from scratch at any time.

---

## How it works end-to-end
1) **Generate genesis**  
   Both EL and CL start from the same genesis files.

2) **Start validator pair**  
   Validator CL + EL begin producing blocks.

3) **Start archive pair**  
   Archive EL/CL follow the chain and keep all historical state.

4) **Query the archive**  
   JSON-RPC lets you read block history and historical balances.

---

## Typical questions you can answer
- Latest block number (`eth_blockNumber`)
- Historical balance at block 0 (`eth_getBalance` with block 0)
- Full traces for debugging (`debug_*` / `trace_*` on the archive)

---

## Where to look next
- `README.md` for the exact commands
- `scripts/start-localnet.sh` for the automated flow
- `scripts/post-start-checks.sh` for validation
- `scripts/send-test-tx.sh` to generate a real balance change
