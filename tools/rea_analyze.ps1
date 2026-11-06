param(
    [Parameter(Mandatory=$true)][int]$Bank,
    [string]$OutDir = "out\rea"
)
# Reproducible REA/Ghidra analysis pass for one PRG bank.
# Requires Node/npm and Ghidra 12.1.x (see decomp/README.md).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$env:GHIDRA_INSTALL_DIR = "C:\PIG\ghidra-12.1.4"
$env:JAVA_HOME = "C:\Program Files\Zulu\zulu-25"
$base = if ($Bank -eq 15) { "0xC000" } else { "0x8000" }
$rom = Join-Path $root ("{0}\bank{1:D2}.bin" -f $OutDir, $Bank)
$json = Join-Path $root ("{0}\rea_bank{1:D2}.json" -f $OutDir, $Bank)
Push-Location $root
npx -y rea-agents@6.7.0 analyze $rom `
    --target-format raw-binary --architecture 6502 --entry-point $base `
    --format json --full-output > $json
Pop-Location
Write-Host "wrote $json"
