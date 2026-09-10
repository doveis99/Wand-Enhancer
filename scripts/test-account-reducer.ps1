param([string[]]$BundlePaths = @())

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$inputs = @($BundlePaths | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
Push-Location $repo
try {
    dotnet run --project tests/AccountReducer/AccountReducer.Tests.csproj -- @inputs
    if ($LASTEXITCODE -ne 0) { throw 'Account reducer regression tests failed' }

    node .tmp/account-reducer/results/behavior.js
    if ($LASTEXITCODE -ne 0) { throw 'Account reducer behavior tests failed' }

    foreach ($inputPath in $inputs) {
        $outputPath = Join-Path '.tmp/account-reducer/results' (Split-Path -Leaf $inputPath)
        node --check $outputPath
        if ($LASTEXITCODE -ne 0) { throw "Patched bundle syntax check failed: $outputPath" }
    }
} finally {
    Pop-Location
}
