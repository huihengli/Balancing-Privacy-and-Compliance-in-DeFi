# C2 ablation — light-client verification cost

Companion to the paper's component-level ablation (Table `tab:abl_component`).
Deploys two minimal execution contracts and measures the gas delta between
trust-minimized release (Merkle inclusion verified) and trusted-relayer release
(no verification):

| Contract | What it does |
|---|---|
| `LightClientRelease` | stores a source-chain tx root (relayer `syncHeader`), releases only after a Merkle inclusion proof verifies |
| `NoLightClientRelease` | releases unconditionally (trust-the-relayer baseline) |

Measured on the same 16-leaf tree: **`release` (verify+execute) − `release` (no verify) = 7,826 gas**.

## Run

```powershell
cd hardhat
npm install
npx hardhat test test/ablation_lightclient.mjs
```

The test prints `[LC] syncHeader gas`, `[LC] release gas`, `[No-LC] release gas`
and the `[Delta]`; with `hardhat-gas-reporter` installed it also prints a
per-function gas table.

> This folder is a minimal standalone Hardhat project (Hardhat 3.x, Solidity 0.8.28).
> The same three files can also be dropped into any existing Hardhat project.
