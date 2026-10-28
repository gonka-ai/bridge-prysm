# Documentation: Graceful Fallback for Missing Execution API Methods

## Overview
This document describes the changes made to the `bridge-prysm` client to handle cases where the connected execution client (a specialized **Bridge Geth**) cannot serve modern blob-related Engine API methods.

This divergence is a direct result of the **Bridge-Geth Architecture**, which prioritizes high-performance receipt filtering over full state maintenance. Because the Bridge Client does not execute transactions or maintain a state trie, it operates in a state of perpetual divergence between its **Skeleton** (which tracks the network tip) and its **Canonical Head** (which remains at Genesis).

## Background: The "Stale Head" Paradox
In a standard Geth node, block execution advances the canonical head, updating the node's internal timestamp. Geth uses this timestamp to determine which hard forks (e.g., Deneb, Fulu, Osaka) are active.

The **Bridge Client** introduces a unique architectural challenge:
1.  **ReceiptSync Mode**: The client fetches Headers, Bodies, and Receipts but bypasses the EVM execution pipeline.
2.  **Divergent Tips**:
    *   **Skeleton Head**: Successfully tracks the latest block provided by the Consensus Layer.
    *   **Canonical Head**: Since blocks are not formally "imported" into the state, `blockchain.CurrentHeader()` remains stuck at Genesis (Timestamp 0).
3.  **Fork Rejection**: When Prysm calls methods like `engine_getBlobsV2`, Geth checks the canonical head's timestamp. Finding it at Genesis (Pre-Merge), it rejects the call with an `Unsupported fork` error, even if the network is actually post-Osaka.

Initially, this was addressed by commenting out the fork checks or the methods themselves in `bridge-geth`. However, this shifted the failure to the Prysm side, where the missing capability was treated as a fatal synchronization error. If Bridge Geth still exposes the method but rejects it because the canonical head is stale, Prysm sees Engine API error `-38005` (`Unsupported fork`) instead.

## Problem Statement
In standard Prysm, the absence of `engine_getBlobsV1` or `engine_getBlobsV2` in the execution client's capabilities, or an explicit `Unsupported fork` response for these calls, is treated as a critical failure during the reconstruction of:
*   **Blob Sidecars** (Deneb fork)
*   **Data Column Sidecars** (Fulu/PeerDAS fork)

This leads to:
*   **Continuous ERROR logs**: `Failed to process data column sidecars from execution`.
*   **Infinite Retry Loops**: Prysm indefinitely attempts to fetch PeerDAS cells from an EL that it knows (via the handshake) does not support the required method.
*   **Sync Instability**: The constant retries and logging overhead can degrade the performance of the bridge-prysm node.

## Rationale for the Change
The Bridge's primary goal is to process **Receipts** for ERC20 transfer events. It does not strictly require the reconstruction of PeerDAS sidecars from the execution layer to maintain its bridge functionality. By allowing Prysm to gracefully skip these steps when the API is unavailable, we ensure a stable sync process for the bridge without sacrificing its core objectives.

## Changes Implemented

### 1. Standardizing Support Errors
In the execution client service, we updated the capability checks to return a standard `ErrMethodNotFound` error. We also map Engine API error `-38005` to `ErrUnsupportedFork`. This allows the calling services to programmatically identify when a failure is due to an unavailable sidecar API rather than a transient network issue.

*   **File**: [beacon-chain/execution/engine_client.go](file:///Users/gliberman/Documents/GitHub/bridge-prysm/beacon-chain/execution/engine_client.go)
*   **Change**: Modified `GetBlobs` and `GetBlobsV2` to return `execution.ErrMethodNotFound` if the capability is missing from the EL handshake, and mapped `Unsupported fork` RPC responses to `execution.ErrUnsupportedFork`.

### 2. Graceful Fallback in Sync Service
We modified the Deneb and PeerDAS reconstruction paths to detect unavailable sidecar reconstruction and exit cleanly.

*   **File**: [beacon-chain/sync/subscriber_beacon_blocks.go](file:///Users/gliberman/Documents/GitHub/bridge-prysm/beacon-chain/sync/subscriber_beacon_blocks.go)
*   **Change**: Updated `processBlobSidecarsFromExecution` and `processDataColumnSidecarsFromExecution` to catch `ErrMethodNotFound` and `ErrUnsupportedFork`. When caught, the service logs at debug level and returns without treating the block as failed.

## Impact
*   **Log Cleanliness**: Syncing a bridge-prysm node against a bridge-geth node will no longer spam reconstruction errors.
*   **Sync Stability**: The node will no longer enter infinite retry loops for optional sidecar data reconstruction.
*   **Compatibility**: This change maintains full compatibility with standard Geth nodes that *do* support these methods, as the fallback only triggers when the capability is explicitly missing or the Engine API explicitly rejects the blob call as an unsupported fork.
