param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

function Read-RepoFile {
    param([string]$RelativePath)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file is missing: $RelativePath"
    }

    return Get-Content -LiteralPath $path -Raw
}

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Message
    )

    if ($Content -notmatch $Pattern) {
        throw $Message
    }
}

$buildWorkflow = Read-RepoFile '.github\workflows\build.yml'
$releaseWorkflow = Read-RepoFile '.github\workflows\release.yml'
$syncWorkflow = Read-RepoFile '.github\workflows\sync-upstream.yml'
$pnpmWorkspace = Read-RepoFile 'web-panel\pnpm-workspace.yaml'
$constants = Read-RepoFile 'WandEnhancer\Constants.cs'
$project = Read-RepoFile 'WandEnhancer\WandEnhancer.csproj'
$mainWindow = Read-RepoFile 'WandEnhancer\View\MainWindow\MainWindow.xaml'
$mainWindowVm = Read-RepoFile 'WandEnhancer\View\MainWindow\MainWindowVm.cs'
$updater = Read-RepoFile 'WandEnhancer\Utils\Updater.cs'

Assert-Contains $buildWorkflow '(?ms)on:\s+.*push:\s+.*branches:\s*\[\s*"?master"?' 'build.yml must run automatically on pushes to master.'
Assert-Contains $buildWorkflow 'workflow_dispatch:' 'build.yml must keep manual dispatch.'
Assert-Contains $buildWorkflow '(?ms)pnpm/action-setup@v4\s+with:\s+version:\s+11' 'build.yml must use pnpm 11 to honor allowBuilds.'

Assert-Contains $syncWorkflow 'k1tbyte/Wand-Enhancer\.git' 'sync-upstream.yml must fetch from the original upstream repository.'
Assert-Contains $syncWorkflow 'gh\s+workflow\s+run\s+build\.yml' 'sync-upstream.yml must dispatch the build workflow after an automated sync.'
Assert-Contains $syncWorkflow 'gh\s+workflow\s+run\s+release\.yml' 'sync-upstream.yml must dispatch release publishing for synced tags.'

Assert-Contains $releaseWorkflow 'workflow_dispatch:' 'release.yml must support explicit dispatch for synced tags.'
Assert-Contains $releaseWorkflow 'release_tag' 'release.yml must accept a release_tag input.'
Assert-Contains $releaseWorkflow "github\.repository == 'doveis99/Wand-Enhancer'" 'release.yml must be enabled for the fork repository.'
Assert-Contains $releaseWorkflow 'WandEnhancer/bin/Release/WandEnhancer\.exe' 'release.yml must publish the executable asset for the updater.'
Assert-Contains $releaseWorkflow '(?ms)pnpm/action-setup@v4\s+with:\s+version:\s+11' 'release.yml must use pnpm 11 to honor allowBuilds.'
Assert-Contains $pnpmWorkspace '(?ms)allowBuilds:\s+esbuild:\s+true' 'pnpm-workspace.yaml must allow esbuild install scripts for reproducible builds.'

Assert-Contains $constants 'public const string Owner = "doveis99";' 'Constants.Owner must point updater links at the fork.'
Assert-Contains $project 'System\.Net\.Http' 'WandEnhancer.csproj must reference System.Net.Http for the updater.'
Assert-Contains $project 'Utils\\Updater\.cs' 'WandEnhancer.csproj must compile the updater.'
Assert-Contains $project 'View\\Popups\\UpdatePopup\.xaml\.cs' 'WandEnhancer.csproj must compile the update popup code-behind.'
Assert-Contains $project 'View\\Popups\\UpdatePopup\.xaml' 'WandEnhancer.csproj must include the update popup XAML.'
Assert-Contains $mainWindow 'Command="\{Binding UpdateCommand\}"' 'MainWindow.xaml must expose the update command.'
Assert-Contains $mainWindowVm 'UpdateCommand\s*=\s*new RelayCommand\(OnUpdate\);' 'MainWindowVm must initialize UpdateCommand.'
Assert-Contains $updater 'releases/latest' 'Updater must query GitHub releases.'
Assert-Contains $updater 'Assets\.FirstOrDefault\(o => o\.Name\.EndsWith\("\.exe"\)\)' 'Updater must download an executable release asset.'

Write-Host 'Fork automation and updater wiring validated.'
