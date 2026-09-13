# Flask multi-node threshold audit simulator

Faithful rebuild of the paper's threshold-decryption simulator (Table
`tab:thresdecrypt`): **n = 5 regulator nodes** (separate Flask processes on
localhost ports 5100–5104), **t = 3** of which must cooperate to decrypt.

## Run

```powershell
pip install -r requirements.txt
python benchmark.py --trials 30 --n 5 --t 3
```

Output (30 trials):

| Metric | Meaning |
|---|---|
| Key Distribution Time | dealer posts the n Shamir shares to the nodes (one-time) |
| Average Fragment Exchange Time | combiner pulls t shares over HTTP |
| Average Full Decryption Time | exchange + Lagrange reconstruction + AES-GCM decrypt |
| Decryption Success Rate | t-of-n correct shares → plaintext recovered |

Results are written to `flask_threshold_metrics.csv`.

## Notes

- The paper's originally reported figures (547.36 / 188.29 ± 20.04 / 190.31 ± 19.53 ms)
  came from an earlier simulator instance; re-run this script to refresh them.
- The `shamir.py` module is self-contained (stdlib only); Flask is used only for
  the multi-node HTTP transport, matching the paper's simulator description.
