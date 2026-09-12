// Hand-written Poseidon Merkle tree primitives (circomlib 2.x removed merkleTree.circom).
pragma circom 2.1.4;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

// Prove that `leaf` is a member of a Poseidon(2) Merkle tree of depth `levels`.
template PoseidonMerkleMembership(levels) {
    signal input leaf;
    signal input root;
    signal input pathElements[levels];
    signal input pathIndices[levels];
    signal output isMember;

    component hashers[levels];
    signal cur[levels + 1];
    cur[0] <== leaf;

    for (var i = 0; i < levels; i++) {
        pathIndices[i] * (pathIndices[i] - 1) === 0;   // pathIndices[i] in {0,1}
        hashers[i] = Poseidon(2);
        // pathIndices[i] == 0 -> hash(cur, sibling); == 1 -> hash(sibling, cur)
        hashers[i].inputs[0] <== pathIndices[i] * (pathElements[i] - cur[i]) + cur[i];
        hashers[i].inputs[1] <== pathIndices[i] * (cur[i] - pathElements[i]) + pathElements[i];
        cur[i + 1] <== hashers[i].out;
    }

    component eq = IsEqual();
    eq.in[0] <== cur[levels];
    eq.in[1] <== root;
    isMember <== eq.out;
}

// Prove that `v` is NOT in a *sorted* Poseidon(2) Merkle tree, via two adjacent
// bracketing leaves L < v < R. The tree must be padded with sentinel leaves
// 0 and p-1 so that every v is bracketed by an interior pair of consecutive leaves.
// All leaf values and v must be < 2^252 (enforced implicitly by LessThan(252)).
template SortedNonMembership(levels) {
    signal input v;
    signal input root;
    signal input L;
    signal input L_pathElements[levels];
    signal input L_pathIndices[levels];
    signal input R;
    signal input R_pathElements[levels];
    signal input R_pathIndices[levels];
    signal output notInTree;

    // 1. L and R are both leaves of the tree.
    component mL = PoseidonMerkleMembership(levels);
    mL.leaf <== L;
    mL.root <== root;
    component mR = PoseidonMerkleMembership(levels);
    mR.leaf <== R;
    mR.root <== root;
    for (var i = 0; i < levels; i++) {
        mL.pathElements[i] <== L_pathElements[i];
        mL.pathIndices[i] <== L_pathIndices[i];
        mR.pathElements[i] <== R_pathElements[i];
        mR.pathIndices[i] <== R_pathIndices[i];
    }

    // 2. Bracketing: L < v < R.
    component ltL = LessThan(252);
    ltL.in[0] <== L;
    ltL.in[1] <== v;
    component ltR = LessThan(252);
    ltR.in[0] <== v;
    ltR.in[1] <== R;

    // 3. Adjacency: L and R occupy consecutive leaf positions, pos(R) == pos(L) + 1.
    //    pathIndices are LSB-first (leaf level first), consistent with PoseidonMerkleMembership.
    var posL = 0;
    var posR = 0;
    for (var i = 0; i < levels; i++) {
        posL += L_pathIndices[i] * (1 << i);
        posR += R_pathIndices[i] * (1 << i);
    }
    posR === posL + 1;

    signal bothMembers <== mL.isMember * mR.isMember;
    signal bothBounds <== ltL.out * ltR.out;
    notInTree <== bothMembers * bothBounds;
}
