// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// C2 ablation baseline (WITHOUT light-client verification).
// Trusted-relayer model: the release path performs NO Merkle/header check.
// Comparing its gas with LightClientRelease.release isolates the cost of
// trust-minimized verification.
contract NoLightClientRelease {
    uint256 public releasedCount;

    event AssetReleased(bytes32 indexed txHash, address indexed recipient);

    function release(bytes32 txHash, address recipient) external returns (bool) {
        releasedCount += 1;
        emit AssetReleased(txHash, recipient);
        return true;
    }
}
