// Tier 1 (simple): commitment binding + amount range + EdDSA-Poseidon signature.
// These are HARD constraints: any valid witness is necessarily a well-formed,
// correctly-signed transaction. `isCompliant` is therefore the constant 1 for
// this tier (the compliance is certified by witness existence).
pragma circom 2.1.4;

include "../node_modules/circomlib/circuits/eddsaposeidon.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/bitify.circom";

template SimpleCompliance() {
    // --- private transaction fields ---
    signal input amount;
    signal input senderId;
    signal input vaspId;

    // --- private EdDSA-Poseidon signature ---
    signal input Ax;
    signal input Ay;
    signal input S;
    signal input R8x;
    signal input R8y;

    // --- public commitment (bound to the audit tag's txHash) ---
    signal input commitment;

    signal output isCompliant;

    // 1. Commitment binding: c = Poseidon(amount, senderId, vaspId) == public commitment.
    component cHash = Poseidon(3);
    cHash.inputs[0] <== amount;
    cHash.inputs[1] <== senderId;
    cHash.inputs[2] <== vaspId;
    cHash.out === commitment;

    // 2. Amount range: 0 <= amount < 2^64.
    component amountBits = Num2Bits(64);
    amountBits.in <== amount;

    // 3. Signature validity: EdDSA-Poseidon over the commitment (HARD constraint).
    component sig = EdDSAPoseidonVerifier();
    sig.enabled <== 1;
    sig.Ax <== Ax;
    sig.Ay <== Ay;
    sig.S <== S;
    sig.R8x <== R8x;
    sig.R8y <== R8y;
    sig.M <== commitment;

    isCompliant <== 1;
}

component main {public [commitment]} = SimpleCompliance();
