// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Target-chain light client: syncs source-chain transaction roots and verifies
// transaction inclusion via Merkle proofs (paper §4.3).
//   syncHeader          -> "Block Header Synchronization" row of Table `tab:xchainver`
//   verifyInclusion     -> simplified verifier ("Light Client Verification" row)
//   verifyInclusionOZ   -> OpenZeppelin-style verifier, for the 26,050-gas comparison
contract LightClient {
    bytes32 public txRoot;
    uint256 public headerCount;

    event HeaderSynced(bytes32 indexed root);

    // Any relayer (gas-incentivized) syncs the latest source-chain tx root.
    function syncHeader(bytes32 root) external {
        txRoot = root;
        headerCount += 1;
        emit HeaderSynced(root);
    }

    // Simplified Merkle inclusion (leaf = keccak256(txHash), position by index bits).
    function verifyInclusion(
        bytes32 txHash,
        bytes32[] calldata proof,
        uint256 index
    ) external view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(txHash));
        uint256 n = proof.length;
        for (uint256 i = 0; i < n; i++) {
            node = (index & 1) == 1
                ? keccak256(abi.encodePacked(proof[i], node))
                : keccak256(abi.encodePacked(node, proof[i]));
            index >>= 1;
        }
        return node == txRoot;
    }

    // OpenZeppelin MerkleProof-style verification (logic replicated from the
    // MIT-licensed OpenZeppelin Contracts library).
    function verifyInclusionOZ(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) external pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            computedHash = computedHash <= proofElement
                ? keccak256(abi.encodePacked(computedHash, proofElement))
                : keccak256(abi.encodePacked(proofElement, computedHash));
        }
        return computedHash == root;
    }
}
