// C2 ablation: cost of trust-minimized (light-client) verification.
// Deploys LightClientRelease and NoLightClientRelease, executes the same
// release flow, and reports the gas delta (the price of light-client verification).
//
// Run:  npx hardhat test test/ablation_lightclient.mjs
// (hardhat-gas-reporter is also active, so a per-function gas table prints too.)
import { expect } from "chai";
import { network } from "hardhat";

// Hardhat 3 ESM: obtain ethers via network.connect() (no named export on "hardhat").
const { ethers } = await network.connect();

function pairHash(a, b) {
    return ethers.keccak256(
        ethers.solidityPacked(["bytes32", "bytes32"], [a, b]));
}

// Build a balanced binary Merkle tree over `leaves`; return root and the
// inclusion proof for `leafIndex`.
function buildMerkleProof(leaves, leafIndex) {
    let level = leaves.slice();
    let index = leafIndex;
    const proof = [];
    while (level.length > 1) {
        const next = [];
        for (let i = 0; i < level.length; i += 2) {
            next.push(pairHash(level[i], level[i + 1]));
        }
        const sibling = (index % 2 === 0) ? level[index + 1] : level[index - 1];
        proof.push(sibling);
        index = Math.floor(index / 2);
        level = next;
    }
    return { root: level[0], proof };
}

describe("C2 ablation: light-client verification cost", () => {
    it("reports gas with and without light-client verification", async () => {
        const [deployer] = await ethers.getSigners();
        const recipient = deployer.address;

        // 16-leaf source-chain transaction tree; we release leaf 7.
        // The contract forms its leaf as keccak256(txHash), so the JS tree is
        // built over hashed leaves to match. toBeHex(i, 32) pads to 32 bytes
        // (ethers v6 solidityPacked does NOT left-pad automatically).
        const txHashes = Array.from({ length: 16 }, (_, i) =>
            ethers.keccak256(
                ethers.solidityPacked(["bytes32"], [ethers.toBeHex(i, 32)])));
        const treeLeaves = txHashes.map((tx) =>
            ethers.keccak256(ethers.solidityPacked(["bytes32"], [tx])));
        const { root, proof } = buildMerkleProof(treeLeaves, 7);
        const txHash = txHashes[7];

        // ---- WITH light client ----
        const LCFactory = await ethers.getContractFactory("LightClientRelease");
        const lc = await LCFactory.deploy();
        await lc.waitForDeployment();

        const syncRc = await (await lc.syncHeader(root)).wait();
        const relRc = await (await lc.release(txHash, proof, 7, recipient)).wait();
        console.log("[LC]     syncHeader gas            =", syncRc.gasUsed.toString());
        console.log("[LC]     release (verify+execute) gas =", relRc.gasUsed.toString());

        // ---- WITHOUT light client ----
        const NoLCFactory = await ethers.getContractFactory("NoLightClientRelease");
        const nolc = await NoLCFactory.deploy();
        await nolc.waitForDeployment();

        const nolcRc = await (await nolc.release(txHash, recipient)).wait();
        console.log("[No-LC]  release gas               =", nolcRc.gasUsed.toString());

        const delta = BigInt(relRc.gasUsed) - BigInt(nolcRc.gasUsed);
        console.log("[Delta]  light-client verification overhead =", delta.toString(), "gas");

        expect(await lc.releasedCount()).to.equal(1n);
        expect(await nolc.releasedCount()).to.equal(1n);
    });
});
