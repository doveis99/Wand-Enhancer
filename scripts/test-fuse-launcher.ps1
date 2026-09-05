# Windows integration tests; requires VS C++ tools, Windows SDK and .NET 9 SDK.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio C++ tools are required' }
$vc = (Get-ChildItem "$vs\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$kits = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots').KitsRoot10
$sdk = (Get-ChildItem "$kits\Lib" -Directory | Where-Object { Test-Path "$($_.FullName)\um\x64\kernel32.lib" } | Sort-Object Name -Descending | Select-Object -First 1).Name
$testDir = Join-Path $repo 'tests\FuseLauncher'
$outDir = Join-Path $repo '.tmp\fuse-tests'
New-Item -ItemType Directory -Force $outDir | Out-Null
$exe = Join-Path $outDir 'fixture.exe'
& "$vc\bin\Hostx64\x64\cl.exe" /nologo "$testDir\fixture.cpp" "/I$vc\include" "/I$kits\Include\$sdk\ucrt" "/I$kits\Include\$sdk\shared" "/I$kits\Include\$sdk\um" "/Fe:$exe" "/Fo:$outDir\fixture.obj" /link "/LIBPATH:$vc\lib\x64" "/LIBPATH:$kits\Lib\$sdk\ucrt\x64" "/LIBPATH:$kits\Lib\$sdk\um\x64" kernel32.lib
if ($LASTEXITCODE -ne 0) { throw 'Native fixture compilation failed' }
dotnet run --project "$testDir\FuseLauncher.Tests.csproj" -- $exe
if ($LASTEXITCODE -ne 0) { throw 'Fuse launcher regression tests failed' }
