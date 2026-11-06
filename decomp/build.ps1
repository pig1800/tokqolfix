$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    & python ".\build.py" @args
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
