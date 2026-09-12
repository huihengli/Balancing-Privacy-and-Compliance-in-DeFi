// Tier 2 (medium): simple + AML threshold check.
// Signature / range / binding remain HARD constraints; the AML threshold is a
// soft predicate: amount < amlThreshold -> isCompliant, else auditRequired.
pragma circom 2.1.4;

include "../node_modules/circomlib/circuits/eddsaposeidon.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template MediumCompliance() {
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

    auditRequired <== 1 - aml.out;
    isCompliant <== aml.out;
}

component main {public [commitment, amlThreshold]} = MediumCompliance();
