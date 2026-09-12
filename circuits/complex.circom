// Tier 3 (complex): medium + VASP blacklist non-membership.
// The blacklist is a *sorted* Poseidon Merkle tree; compliance requires a valid
// non-membership proof that vaspId is not in the tree (see merkle.circom).
pragma circom 2.1.4;

include "../node_modules/circomlib/circuits/eddsaposeidon.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "merkle.circom";

template ComplexCompliance() {
    signal input amount;
    signal input senderId;
    signal input vaspId;
    signal input Ax;
    signal input Ay;
    signal input S;
    signal input R8x;
    signal input R8y;

    signal input commitment;      // public
    signal input amlThreshold;    // public
    signal input blacklistRoot;   // public

    // --- blacklist non-membership proof (private) ---
    signal input L;
    signal input L_pathElements[10];
    signal input L_pathIndices[10];
    signal input R;
    signal input R_pathElements[10];
    signal input R_pathIndices[10];

    signal output isCompliant;
    signal output auditRequired;

    component cHash = Poseidon(3);
    cHash.inputs[0] <== amount;
    cHash.inputs[1] <== senderId;
    cHash.inputs[2] <== vaspId;
    cHash.out === commitment;

    component amountBits = Num2Bits(64);
    amountBits.in <== amount;

    component sig = EdDSAPoseidonVerifier();
    sig.enabled <== 1;
    sig.Ax <== Ax;
    sig.Ay <== Ay;
    sig.S <== S;
    sig.R8x <== R8x;
    sig.R8y <== R8y;
    sig.M <== commitment;

    component aml = LessThan(64);
    aml.in[0] <== amount;
    aml.in[1] <== amlThreshold;

    component bl = SortedNonMembership(10);
    bl.v <== vaspId;
    bl.root <== blacklistRoot;
    bl.L <== L;
    bl.R <== R;
    for (var i = 0; i < 10; i++) {
        bl.L_pathElements[i] <== L_pathElements[i];
        bl.L_pathIndices[i] <== L_pathIndices[i];
        bl.R_pathElements[i] <== R_pathElements[i];
        bl.R_pathIndices[i] <== R_pathIndices[i];
    }

    auditRequired <== 1 - aml.out;
    isCompliant <== aml.out * bl.notInTree;
}

component main {public [commitment, amlThreshold, blacklistRoot]} = ComplexCompliance();
