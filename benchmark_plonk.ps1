# PLONK benchmark (Groth16 vs PLONK comparison, paper Table `tab:zksys`).
# Reuses the r1cs / witness / pot16_final.ptau produced by build.ps1.
# NOTE: snarkjs's reference PLONK prover takes minutes per proof (the complex
# circuit needs ~35 min per prove), so $ITER is intentionally small.
# Run from the repo ROOT:  powershell -ExecutionPolicy Bypass -File benchmark_plonk.ps1
$ErrorActionPreference = "Stop"
$ITER = 3   # number of prove runs per circuit (default 3 for a stable min/avg/max)

$results = @()
Push-Location (Join-Path $PSScriptRoot "circuits")
try {
    foreach ($name in @("simple", "medium", "complex")) {
        Write-Host "`n===== PLONK $name =====" -ForegroundColor Green

        # 1. PLONK setup (reuse pot16_final.ptau from build.ps1)
        if (-not (Test-Path "${name}_plonk.zkey")) {
            snarkjs plonk setup "$name.r1cs" "pot16_final.ptau" "${name}_plonk.zkey" 2>&1 | Out-Null
            snarkjs zkey export verificationkey "${name}_plonk.zkey" "${name}_plonk_vk.json" 2>&1 | Out-Null
        }

        # 2. prove (timed, $ITER runs)
        $proveTimes = @()
        for ($i = 1; $i -le $ITER; $i++) {
            $proveTimes += (Measure-Command {
                snarkjs plonk prove "${name}_plonk.zkey" "$name.witness.wtns" "${name}_plonk_proof.json" "${name}_plonk_public.json" 2>&1 | Out-Null
            }).TotalMilliseconds
        }
        $proveAvg = [math]::Round(($proveTimes | Measure-Object -Average).Average, 2)
        $proveMin = [math]::Round(($proveTimes | Measure-Object -Minimum).Minimum, 2)
        $proveMax = [math]::Round(($proveTimes | Measure-Object -Maximum).Maximum, 2)

        # 3. verify (timed) + correctness check (prints OK!/FAIL)
        $verifyMs = [math]::Round((Measure-Command {
            snarkjs plonk verify "${name}_plonk_vk.json" "${name}_plonk_public.json" "${name}_plonk_proof.json" 2>&1 | Out-Null
        }).TotalMilliseconds, 2)
        snarkjs plonk verify "${name}_plonk_vk.json" "${name}_plonk_public.json" "${name}_plonk_proof.json"

        # 4. serialized proof size (bytes)
        $proofSize = (Get-Item "${name}_plonk_proof.json").Length

        $results += [pscustomobject]@{
            Circuit       = $name
            Prove_avg_ms  = $proveAvg
            Prove_min_ms  = $proveMin
            Prove_max_ms  = $proveMax
            Verify_ms     = $verifyMs
            Proof_bytes   = $proofSize
        }
        Write-Host ("{0}: prove avg {1} ms [min {2}, max {3}], verify {4} ms, proof {5} B" -f $name, $proveAvg, $proveMin, $proveMax, $verifyMs, $proofSize)

        # 5. export PLONK Solidity verifier (optional on-chain gas measurement)
        snarkjs zkey export solidityverifier "${name}_plonk.zkey" "${name}_plonk_verifier.sol"
    }

    Write-Host "`n================ PLONK METRICS SUMMARY ================" -ForegroundColor Magenta
    $results | Format-Table -AutoSize
    $results | Export-Csv -Path "plonk_metrics_summary.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote circuits/plonk_metrics_summary.csv" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
