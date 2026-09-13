# Ablation suite (paper Tables `tab:abl_circuit`, `tab:zksys`, `tab:abl_component`)

Three experiment groups reproduce the ablation and proof-system comparisons of the paper.
Run everything from the repo root; prerequisites are the same as the main `README.md`.

## 1. Compliance-module ablation (circuit tiers)

`build.ps1` already produces the three-tier numbers (8,757 / 8,825 / 19,748 constraints;
1.05–1.41 s prove). The paper's `tab:abl_circuit` reads the marginal costs directly:
AML threshold `+68` constraints, blacklist `+10,923` constraints, `+358.64 ms` prove time.

## 2. Proof-system comparison (Groth16 vs PLONK)

```powershell
# requires build.ps1 to have produced *.r1cs / *.witness.wtns / pot16_final.ptau
powershell -ExecutionPolicy Bypass -File benchmark_plonk.ps1
```

- Writes `circuits/plonk_metrics_summary.csv` (prove avg/min/max, verify, proof bytes).
- Exports `circuits/*_plonk_verifier.sol` for optional on-chain gas measurement.
- **Note**: the first proof after PLONK setup carries a one-time proving-key preprocessing
  step (minutes in our environment) and is excluded from the averages; steady-state
  proving is 13.2–24.7 s across the three circuits. Results are tracked in
  `results/plonk_metrics_summary.csv` (6 runs: two batches of three).

Optional on-chain PLONK gas: export calldata
(`snarkjs zkey export soliditycalldata <public>.json <proof>.json`), drop the
`*_plonk_verifier.sol` into `hardhat/contracts/` as `PlonkVerifier.sol`, and call
`verifyProof(...)` from a test.

## 3. Component-level ablation

### 3a. Light-client verification cost

```powershell
cd hardhat
npm install
npx hardhat test test/ablation_lightclient.mjs
```

Prints `syncHeader` gas, `release` gas with Merkle verification, `release` gas
without verification, and the delta (measured: **7,826 gas**).

### 3b. Threshold-decryption cost

```powershell
pip install pycryptodome
python threshold/threshold_ablation.py
```

Compares three paths (results tracked in `threshold/threshold_ablation_summary.csv`):

| Path | Mean | Meaning |
|---|---|---|
| single-key | 0.0611 ms | baseline: one regulator holds the full key |
| threshold-local | 0.0715 ms | t-of-n reconstruction + decrypt, no network |
| threshold-p2p | 8.4700 ms | loopback share exchange + combine + decrypt (collaboration cost lower bound; the paper's Flask multi-node setup measures 188.29 ms) |

## Results artifacts

| File | Contents |
|---|---|
| `results/metrics_summary.csv` | Groth16 witness/prove/verify/proof-size (30-trial averages, paper `tab:zkproof`) |
| `results/plonk_metrics_summary.csv` | PLONK prove/verify/proof-size (paper `tab:zksys`) |
| `threshold/threshold_ablation_summary.csv` | single-key vs threshold decryption (paper `tab:abl_component`) |
| `inputs/` | deterministic test inputs for the three circuits (all-compliant transaction) |
