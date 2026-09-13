// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Source-chain audit contract: stores the encrypted audit tags and emits events
// for the target chain to listen to (paper §4.2.3). Gas of `storeAuditTag`
// corresponds to the "Audit Tag Storage (Source Chain)" row of Table `tab:xchainver`.
contract AuditContract {
    struct AuditTag {
        bytes ciphertext;
        bytes32 txHash;
        bytes32 zkProofHash;
        uint8 threshold;
        bytes32[] regulatorIds;
    }

    mapping(bytes32 => AuditTag) public tags;
    uint256 public tagCount;

    event AuditTagStored(bytes32 indexed txHash, bytes32 indexed zkProofHash);

    function storeAuditTag(
        bytes calldata ciphertext,
        bytes32 txHash,
        bytes32 zkProofHash,
        uint8 threshold,
        bytes32[] calldata regulatorIds
    ) external {
        tags[txHash] = AuditTag(ciphertext, txHash, zkProofHash, threshold, regulatorIds);
        tagCount += 1;
        emit AuditTagStored(txHash, zkProofHash);
    }
}
