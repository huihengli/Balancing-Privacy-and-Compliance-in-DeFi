# zk-auditable-crosschain

Zero-knowledge compliance circuits for a **privacy-preserving, auditable cross-chain framework**. The circuits realize the compliance assertions of the accompanying paper *"Balancing Privacy and Compliance in DeFi: A Zero-Knowledge-Based Auditable Cross-Chain Framework"*:

| Assertion | Circuit mechanism | Tier |
|---|---|---|
| Commitment binding | `commitment === Poseidon(3)(amount, senderId, vaspId)` (public input) | all |
| Amount validity | `Num2Bits(64)` range proof (0 ≤ amount < $2^{64}$) | all |
| Signature validity | **EdDSA-Poseidon** over the commitment (circomlib `EdDSAPoseidonVerifier`) | all |
| AML threshold (Compliance Mark) | `LessThan(64)`: `amount < amlThreshold → isCompliant`; else `auditRequired=1` | medium+ |
| VASP blacklist | **sorted Poseidon-Merkle non-membership proof** (adjacent leaves `L < v < R`, `pos(R)=pos(L)+1`) | complex |

Signature / range / binding are **hard constraints** (no valid witness exists if violated); AML threshold and blacklist are **soft predicates** (produce `isCompliant` / `auditRequired` outputs).

## Repository layout

```
.
├── circuits/                       # compliance circuits
│   ├── merkle.circom     # hand-written Poseidon Merkle membership + sorted non-membership
│   ├── simple.circom     # commitment binding + range + EdDSA-Poseidon signature
│   ├── medium.circom     # + AML threshold
│   └── complex.circom    # + VASP blacklist non-membership
├── hardhat/                       # Solidity contracts + Hardhat measurements
│   ├── contracts/        # AuditContract, LightClient, LightClientRelease, NoLightClientRelease
│   ├── scripts/measure_sepolia.ts        # cross-chain gas (Table tab:xchainver)
│   └── test/ablation_lightclient.mjs     # light-client ablation (Table tab:abl_component)
├── threshold/
│   ├── flask_simulator/  # Flask multi-node threshold simulator (Table tab:thresdecrypt)
│   └── threshold_ablation.py        # single-key vs threshold loopback ablation
├── inputs/               # deterministic test inputs for the three circuits
├── results/              # measured metrics (Groth16 + PLONK + threshold CSVs)
├── gen_input.js          # generates witness inputs (test transaction)
├── build.ps1             # compile → powers-of-tau → zkey → prove/verify → metrics summary
├── benchmark_plonk.ps1   # PLONK benchmark (Groth16 vs PLONK, Table tab:zksys)
├── ablation_notes.md     # full ablation-suite runbook
├── package.json
└── README.md
```

## Prerequisites

- [circom](https://docs.circom.io/) ≥ 2.2 (global)
- [snarkjs](https://github.com/iden3/snarkjs) (global `npm i -g snarkjs`)
- Node.js ≥ 18

## Quick start

```powershell
# 1. install JS dependencies (circomlib for circuits, circomlibjs for input generation)
npm install

# 2. generate witness inputs (a test transaction, all-compliant)
node gen_input.js
#    -> circuits/input_simple.json, input_medium.json, input_complex.json

# 3. compile + setup + prove + verify + measure (writes circuits/metrics_summary.csv)
powershell -ExecutionPolicy Bypass -File build.ps1
```

`build.ps1` prints a summary table and writes `circuits/metrics_summary.csv`:

| Column | Meaning |
|---|---|
| `Witness_ms` | witness generation time |
| `Prove_avg/min/max_ms` | proof generation time over `$ITER` runs |
| `Verify_ms` | on-chain verifier runtime |
| `Proof_bytes` | Groth16 proof size |

To measure **on-chain verification gas**, deploy the exported `circuits/*_verifier.sol` on Ethereum (Sepolia) with Hardhat; Groth16 verification gas is essentially constant (~215 k) regardless of constraint count.

## Reproducing the paper's experiments

| Paper table | Command |
|---|---|
| `tab:zkproof` (Groth16) | `powershell -ExecutionPolicy Bypass -File build.ps1` → `circuits/metrics_summary.csv` |
| `tab:zksys` (Groth16 vs PLONK) | `powershell -ExecutionPolicy Bypass -File benchmark_plonk.ps1` → `circuits/plonk_metrics_summary.csv` |
| `tab:xchainver` (cross-chain gas) | `cd hardhat && npm install`, then `npx hardhat run scripts/measure_sepolia.ts --network sepolia` (requires `SEPOLIA_RPC_URL` / `SEPOLIA_PRIVATE_KEY` env vars) |
| `tab:abl_component` (light client) | `cd hardhat && npx hardhat test test/ablation_lightclient.mjs` |
| `tab:thresdecrypt` (threshold) | `pip install -r threshold/flask_simulator/requirements.txt && python threshold/flask_simulator/benchmark.py --trials 30` |
| `tab:abl_component` (threshold loopback) | `python threshold/threshold_ablation.py` |

See `ablation_notes.md` for the full runbook, measurement scopes, and result artifacts.

## Constraint counts (circom 2.2.3, `--O1`)

| Circuit | Non-linear + linear = total | Public inputs | Public outputs |
|---|---|---|---|
| simple | 7707 + 1050 = **8757** | 1 (`commitment`) | 1 |
| medium | 7772 + 1053 = **8825** | 2 (`+amlThreshold`) | 2 |
| complex | 13206 + 6542 = **19748** | 3 (`+blacklistRoot`) | 2 |

> ⚠️ These replace the placeholder circuits (36 / 133 / 297 constraints) that only contained dummy checks (`valid <== 1`, a fake signature, and no blacklist). The real EdDSA signature and Merkle non-membership proof are substantially larger, so proof-generation times are correspondingly higher.

## Blacklist semantics and assumptions

- The blacklist is a **sorted** Poseidon(2) Merkle tree (depth 10) whose leaves are `[sentinel 0, ...blacklist ids..., sentinel MAX]`, padded with `MAX =` $2^{252}$ `−1`.
- `vaspId` $\notin$ `blacklist` is proven by two adjacent leaves `L < vaspId < R` with `pos(R) == pos(L) + 1` (consecutive leaves), plus membership proofs for `L` and `R`.
- **Assumptions**: all ids and leaves are `<` $2^{252}$ (implicitly enforced by `LessThan(252)`); the tree is maintained sorted by the blacklist authority. Non-membership soundness follows from the standard sorted-tree bracketing argument.

## Test vector

`gen_input.js` uses a deterministic test key (32-byte seed) and the all-compliant transaction:

```
amount = 5000, senderId = 12345, vaspId = 30, amlThreshold = 10000
blacklist = {10, 20, 40, 50}   →  vaspId = 30 is NOT blacklisted
```

## License

GPL-3.0. The circuits `include` [circomlib](https://github.com/iden3/circomlib) (GPL-3.0), so the combined work is distributed under GPL-3.0. See `LICENSE`.