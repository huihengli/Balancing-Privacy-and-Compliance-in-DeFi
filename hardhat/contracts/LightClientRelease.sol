// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// C2 ablation baseline (WITH light-client verification).
// The light client stores a source-chain transaction root (synced by relayers)
// and releases assets only if a Merkle inclusion proof verifies against it.
// Leaf hashing: keccak256(txHash); node = keccak256(left, right) with the
// proof position given by `index` (0 = left, 1 = right), matching the JS side.
contract LightClientRelease {
    bytes32 public txRoot;
    uint256 public releasedCount;

    event HeaderSynced(bytes32 indexed root);
    event AssetReleased(bytes32 indexed txHash, address indexed recipient);

    // Any relayer (gas-incentivized) syncs the latest source-chain root.
    function syncHeader(bytes32 root) external {
        txRoot = root;
        emit HeaderSynced(root);
    }

    // Release after verifying that txHash is included in the synced root.
    function release(
        bytes32 txHash,
        bytes32[] calldata proof,
        uint256 index,
        address recipient
    ) external returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(txHash));
        uint256 n = proof.length;
        for (uint256 i = 0; i < n; i++) {
            node = (index & 1) == 1
                ? keccak256(abi.encodePacked(proof[i], node))
                : keccak256(abi.encodePacked(node, proof[i]));
            index >>= 1;
        }
        require(node == txRoot, "LightClientRelease: invalid inclusion proof");
        releasedCount += 1;
        emit AssetReleased(txHash, recipient);
        return true;
    }
}
