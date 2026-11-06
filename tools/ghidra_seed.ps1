param(
    [Parameter(Mandatory=$true)][int]$Bank,
    [string]$OutDir = "out\rea"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$env:JAVA_HOME = "C:\Program Files\Zulu\zulu-25"
$env:GHIDRA_INSTALL_DIR = "C:\PIG\ghidra-12.1.4"
$base = if ($Bank -eq 15) { 0xC000 } else { 0x8000 }
$entries = Join-Path $root ("{0}\entries_bank{1:D2}.txt" -f $OutDir, $Bank)
$json = Join-Path $root ("{0}\bank{1:D2}_ghidra.json" -f $OutDir, $Bank)
$rom = Join-Path $root ("{0}\bank{1:D2}.bin" -f $OutDir, $Bank)
$projRoot = "C:\Users\pig18\AppData\Local\Temp\opencode\ghidra_proj"
New-Item -ItemType Directory -Force $projRoot | Out-Null
Push-Location $root
python tools\gen_entries.py $Bank -o $entries
$count = (Get-Content $entries).Count
Write-Host "bank $Bank entries: $count"
& "C:\PIG\ghidra-12.1.4\support\analyzeHeadless.bat" $projRoot ("bank{0:D2}" -f $Bank) `
    -import $rom -loader BinaryLoader -loader-baseAddr ("0x{0:X}" -f $base) `
    -processor 6502:LE:16:default -scriptPath tools\ghidra_scripts `
    -postScript SeedExport.java $entries $json -deleteProject
Pop-Location
