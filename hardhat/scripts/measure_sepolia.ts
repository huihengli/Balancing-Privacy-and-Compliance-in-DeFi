// Measures the cross-chain contract gas of Table `tab:xchainver`.
// Deploys AuditContract and LightClient, then reports the gas of:
//   storeAuditTag, syncHeader, verifyInclusion (simplified), verifyInclusionOZ.
//
// Run on Sepolia (requires the SEPOLIA_RPC_URL / SEPOLIA_PRIVATE_KEY config vars):
//   npx hardhat run scripts/measure_sepolia.ts --network sepolia
// Or on the local simulated chain (quick sanity check):
//   npx hardhat run scripts/measure_sepolia.ts
import { network } from "hardhat";

const { ethers } = await network.connect();

function pairHash(a: string, b: string): string {
  return ethers.keccak256(
    ethers.solidityPacked(["bytes32", "bytes32"], [a, b]),
  );
}

function buildMerkleProof(leaves: string[], leafIndex: number) {
  let level = leaves.slice();
  let index = leafIndex;
  const proof: string[] = [];
  while (level.length > 1) {
    const next: string[] = [];
    for (let i = 0; i < level.length; i += 2) {
      next.push(pairHash(level[i], level[i + 1]));
    }
    const sibling = index % 2 === 0 ? level[index + 1] : level[index - 1];
    proof.push(sibling);
    index = Math.floor(index / 2);
    level = next;
  }
  return { root: level[0], proof };
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Measuring from", deployer.address);

  // ---- AuditContract: audit-tag storage ----
  const AuditContract = await ethers.getContractFactory("AuditContract");
  const audit = await AuditContract.deploy();
  await audit.waitForDeployment();
  console.log("AuditContract at", await audit.getAddress());

  const ciphertext = "0x" + "ab".repeat(200); // 200-byte representative ciphertext
  const txHash = ethers.keccak256("0x1234");
  const zkProofHash = ethers.keccak256("0x5678");
  const rcStore = await (
    await audit.storeAuditTag(ciphertext, txHash, zkProofHash, 3, [zkProofHash, txHash, zkProofHash])
  ).wait();
  console.log("[AuditContract] storeAuditTag gas =", rcStore!.gasUsed.toString());

  // ---- LightClient: header sync + Merkle verification ----
  const LightClient = await ethers.getContractFactory("LightClient");
  const lc = await LightClient.deploy();
  await lc.waitForDeployment();
  console.log("LightClient at", await lc.getAddress());

  const rcSync = await (await lc.syncHeader(txHash)).wait();
  console.log("[LightClient]  syncHeader gas     =", rcSync!.gasUsed.toString());

  // 16-leaf source-chain tx tree; release leaf 7
  const leaves = Array.from({ length: 16 }, (_, i) =>
    ethers.keccak256(ethers.solidityPacked(["bytes32"], [ethers.toBeHex(i)])),
  );
  const { root, proof } = buildMerkleProof(leaves, 7);
  await (await lc.syncHeader(root)).wait();

  const ok = await lc.verifyInclusion(leaves[7], proof, 7);
  console.log("verifyInclusion result =", ok);

  const gasSimplified = await lc.verifyInclusion.estimateGas(leaves[7], proof, 7);
  console.log("[LightClient]  verifyInclusion (simplified) estimateGas =", gasSimplified.toString());

  const gasOZ = await lc.verifyInclusionOZ.estimateGas(proof, root, leaves[7]);
  console.log("[LightClient]  verifyInclusionOZ (OpenZeppelin-style) estimateGas =", gasOZ.toString());

  console.log(
    "[Totals] storage + sync + simplified verify (est.) =",
    (BigInt(rcStore!.gasUsed) + BigInt(rcSync!.gasUsed) + gasSimplified).toString(),
    "gas",
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
