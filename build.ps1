# Builds Groth16 artifacts for the three compliance circuits AND measures:
#   witness time, prove time (avg/min/max over $ITER runs), verify time, proof size.
# Summary is printed at the end and written to circuits/metrics_summary.csv.
# Prerequisites: circom (>=2.2), snarkjs, node; run `npm install` first.
# Run from the repo ROOT:  powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = "Stop"

$PTAU_POWER = 16   # 2^16 constraints ceiling (complex needs ~19748, so 16 is safe)
$ITER        = 10  # number of `prove` runs used for timing (raise for stabler averages)

$results = @()

Push-Location (Join-Path $PSScriptRoot "circuits")
try {
    foreach ($name in @("simple", "medium", "complex")) {
        Write-Host "`n===== $name =====" -ForegroundColor Green
        $r1cs = "$name.r1cs"

        # 0. compile (idempotent)
        circom "$name.circom" --r1cs --wasm --sym -o .

        # 1. powers of tau (one-time; reused across circuits)
        if (-not (Test-Path "pot${PTAU_POWER}_final.ptau")) {
            snarkjs powersoftau new bn128 $PTAU_POWER "pot${PTAU_POWER}_0000.ptau" -v
            snarkjs powersoftau contribute "pot${PTAU_POWER}_0000.ptau" "pot${PTAU_POWER}_0001.ptau" --name="first" -v -e="seed-$name"
            snarkjs powersoftau beacon "pot${PTAU_POWER}_0001.ptau" "pot${PTAU_POWER}_beacon.ptau" 0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f 10 -n="final"
            snarkjs powersoftau prepare phase2 "pot${PTAU_POWER}_beacon.ptau" "pot${PTAU_POWER}_final.ptau" -v
        }

        # 2. groth16 setup + contribute (not timed)
        snarkjs groth16 setup $r1cs "pot${PTAU_POWER}_final.ptau" "${name}_0000.zkey" 2>&1 | Out-Null
        snarkjs zkey contribute "${name}_0000.zkey" "${name}_0001.zkey" --name="contrib" -v -e="rand-$name" 2>&1 | Out-Null
        snarkjs zkey beacon "${name}_0001.zkey" "${name}_final.zkey" 0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f 10 -n="final" 2>&1 | Out-Null
        snarkjs zkey export verificationkey "${name}_final.zkey" "${name}_verification_key.json" 2>&1 | Out-Null

        # 3. witness generation (timed)
        $witnessMs = (Measure-Command {
            node "${name}_js\generate_witness.js" "${name}_js\${name}.wasm" "input_${name}.json" "${name}.witness.wtns" 2>&1 | Out-Null
        }).TotalMilliseconds

        # 4. prove (timed, $ITER runs)
        $proveTimes = @()
        for ($i = 1; $i -le $ITER; $i++) {
            $proveTimes += (Measure-Command {
                snarkjs groth16 prove "${name}_final.zkey" "${name}.witness.wtns" "${name}_proof.json" "${name}_public.json" 2>&1 | Out-Null
            }).TotalMilliseconds
        }
        $proveAvg = ($proveTimes | Measure-Object -Average).Average
        $proveMin = ($proveTimes | Measure-Object -Minimum).Minimum
        $proveMax = ($proveTimes | Measure-Object -Maximum).Maximum

        # 5. verify (timed) + correctness check (prints OK!/FAIL)
        $verifyMs = (Measure-Command {
            snarkjs groth16 verify "${name}_verification_key.json" "${name}_public.json" "${name}_proof.json" 2>&1 | Out-Null
        }).TotalMilliseconds
        snarkjs groth16 verify "${name}_verification_key.json" "${name}_public.json" "${name}_proof.json"

        # 6. proof size (bytes)
        $proofSize = (Get-Item "${name}_proof.json").Length

        $results += [pscustomobject]@{
            Circuit      = $name
            Witness_ms   = [math]::Round($witnessMs, 2)
            Prove_avg_ms = [math]::Round($proveAvg, 2)
            Prove_min_ms = [math]::Round($proveMin, 2)
            Prove_max_ms = [math]::Round($proveMax, 2)
            Verify_ms    = [math]::Round($verifyMs, 2)
            Proof_bytes  = $proofSize
        }
    }

    # 7. summary
    Write-Host "`n================ METRICS SUMMARY ================" -ForegroundColor Magenta
    $results | Format-Table -AutoSize
    $results | Export-Csv -Path "metrics_summary.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote circuits/metrics_summary.csv" -ForegroundColor Cyan

    # 8. export Solidity verifiers (for optional on-chain gas measurement)
    snarkjs zkey export solidityverifier "simple_final.zkey" "simple_verifier.sol"
    snarkjs zkey export solidityverifier "medium_final.zkey" "medium_verifier.sol"
    snarkjs zkey export solidityverifier "complex_final.zkey" "complex_verifier.sol"
    Write-Host "Solidity verifiers exported to circuits/." -ForegroundColor Cyan
}
finally {
    Pop-Location
}
