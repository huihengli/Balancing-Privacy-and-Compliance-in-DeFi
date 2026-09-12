// Generates valid witness inputs for the three compliance circuits.
// Requirement: `npm install` (installs circomlibjs) at the repo root.
//
// Usage:  node gen_input.js
// Output: circuits/input_simple.json, circuits/input_medium.json, circuits/input_complex.json
//
// Test transaction (all-compliant):
//   amount = 5000, senderId = 12345, vaspId = 30, amlThreshold = 10000,
//   vaspId = 30 is NOT in the blacklist {10, 20, 40, 50}.
const circomlibjs = require("circomlibjs");
const fs = require("fs");
const path = require("path");

const LEVELS = 10;     // blacklist Merkle depth; MUST equal the depth in complex.circom
const OUT_DIR = path.join(__dirname, "circuits");

async function main() {
    const babyJub = await circomlibjs.buildBabyjub();
    const eddsa = await circomlibjs.buildEddsa();
    const poseidon = await circomlibjs.buildPoseidon();
    const F = babyJub.F;

    const toStr = (x) => F.toString(F.e(x));

    // ---- deterministic signer key (32-byte seed; test-only, not a production secret) ----
    const prvKey = Buffer.from(
        "0001020304050607080900010203040506070809000102030405060708090001", "hex");
    const pubKey = eddsa.prv2pub(prvKey); // [Ax, Ay]

    // ---- transaction fields ----
    const amount = 5000n;
    const senderId = 12345n;
    const vaspId = 30n;          // NOT in blacklist
    const amlThreshold = 10000n;

    // ---- commitment c = Poseidon(amount, senderId, vaspId) ----
    const commitment = toStr(poseidon([amount, senderId, vaspId]));

    // ---- EdDSA-Poseidon signature over the commitment ----
    const sig = eddsa.signPoseidon(prvKey, F.e(commitment));
    const Ax = toStr(pubKey[0]);
    const Ay = toStr(pubKey[1]);
    const S = sig.S.toString();
    const R8x = toStr(sig.R8[0]);
    const R8y = toStr(sig.R8[1]);

    // ---- sorted blacklist Poseidon(2) Merkle tree ----
    const MAX = (1n << 252n) - 1n;            // sentinel max (< BN254 scalar field prime)
    const blacklist = [10n, 20n, 40n, 50n];
    const sorted = [0n, ...blacklist, MAX];   // sentinel min + ids + sentinel max

    const size = 1 << LEVELS;
    const leafValues = sorted.slice();
    while (leafValues.length < size) leafValues.push(MAX); // pad with MAX (sorted)

    // build tree bottom-up; levelStore[d] = bigints at depth d (d=0 leaves)
    const levelStore = [leafValues];
    let cur = leafValues;
    for (let d = 0; d < LEVELS; d++) {
        const next = [];
        for (let j = 0; j < cur.length; j += 2) {
            next.push(poseidon([cur[j], cur[j + 1]]));   // bigint node hash
        }
        cur = next;
        levelStore.push(cur);
    }
    const root = toStr(cur[0]);

    function pathFor(index) {
        const pathElements = [];
        const pathIndices = [];
        for (let d = 0; d < LEVELS; d++) {
            const sibling = (index % 2 === 0) ? index + 1 : index - 1;
            pathElements.push(toStr(levelStore[d][sibling]));
            pathIndices.push(index % 2);
            index = Math.floor(index / 2);
        }
        return { pathElements, pathIndices };
    }

    // bracketing leaves for vaspId: L = largest sorted leaf < v, R = smallest > v
    const li = sorted.filter((x) => x < vaspId).length - 1; // index of L in `sorted`
    const L = sorted[li];
    const R = sorted[li + 1];
    const Lpath = pathFor(li);       // L and R occupy consecutive positions in `sorted`
    const Rpath = pathFor(li + 1);   // (padding MAX is appended after the sorted prefix)

    // ---- assemble inputs (values as decimal strings) ----
    const sigInputs = {
        amount: amount.toString(),
        senderId: senderId.toString(),
        vaspId: vaspId.toString(),
        Ax, Ay, S, R8x, R8y, commitment,
    };
    const simple = { ...sigInputs };
    const medium = { ...sigInputs, amlThreshold: amlThreshold.toString() };
    const complex = {
        ...sigInputs,
        amlThreshold: amlThreshold.toString(),
        blacklistRoot: root,
        L: toStr(L), R: toStr(R),
        L_pathElements: Lpath.pathElements, L_pathIndices: Lpath.pathIndices,
        R_pathElements: Rpath.pathElements, R_pathIndices: Rpath.pathIndices,
    };

    fs.writeFileSync(path.join(OUT_DIR, "input_simple.json"), JSON.stringify(simple, null, 2));
    fs.writeFileSync(path.join(OUT_DIR, "input_medium.json"), JSON.stringify(medium, null, 2));
    fs.writeFileSync(path.join(OUT_DIR, "input_complex.json"), JSON.stringify(complex, null, 2));

    console.log("commitment    =", commitment);
    console.log("blacklistRoot =", root);
    console.log("L =", toStr(L), " R =", toStr(R), " (bracket vaspId =", vaspId.toString(), ")");
    console.log("wrote circuits/input_simple.json / input_medium.json / input_complex.json");
}

main().catch((e) => { console.error(e); process.exit(1); });
