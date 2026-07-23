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

function Assert-Missing {
    param(
        [string]$RelativePath,
        [string]$Message
    )

    $path = Join-Path $repoRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        throw $Message
    }
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
$mirrorWorkflow = Read-RepoFile '.github\workflows\mirror.yml'
$syncWorkflow = Read-RepoFile '.github\workflows\sync-upstream.yml'
$webPanelPackage = Read-RepoFile 'web-panel\package.json'
$pnpmWorkspace = Read-RepoFile 'web-panel\pnpm-workspace.yaml'
$constants = Read-RepoFile 'WandEnhancer\Constants.cs'
$project = Read-RepoFile 'WandEnhancer\WandEnhancer.csproj'
$mainWindow = Read-RepoFile 'WandEnhancer\View\MainWindow\MainWindow.xaml'
$mainWindowVm = Read-RepoFile 'WandEnhancer\View\MainWindow\MainWindowVm.cs'
$updater = Read-RepoFile 'WandEnhancer\Utils\Updater.cs'

Assert-Contains $buildWorkflow '(?ms)on:\s+.*push:\s+.*branches:\s*\[\s*"?master"?' 'build.yml must run automatically on pushes to master.'
Assert-Contains $buildWorkflow 'workflow_dispatch:' 'build.yml must keep manual dispatch.'
Assert-Contains $buildWorkflow '(?ms)pnpm/action-setup@v\d+\s+with:\s+version:\s+10\.17\.0' 'build.yml must use the pnpm version pinned by the web panel.'
Assert-Contains $webPanelPackage '"packageManager"\s*:\s*"pnpm@10\.17\.0"' 'web-panel/package.json must pin the same pnpm version as build.yml.'

Assert-Contains $mirrorWorkflow "github\.repository == 'k1tbyte/Wand-Enhancer'" 'mirror.yml must not try to mirror from this fork without the upstream GitLab secret.'

Assert-Contains $syncWorkflow 'k1tbyte/Wand-Enhancer\.git' 'sync-upstream.yml must fetch from the original upstream repository.'
Assert-Contains $syncWorkflow 'gh\s+workflow\s+run\s+build\.yml' 'sync-upstream.yml must dispatch the build workflow after an automated sync.'
if ($syncWorkflow -match 'git\s+push\s+origin\s+--tags') {
    throw 'sync-upstream.yml must not push upstream tags with GITHUB_TOKEN because workflow-changing historical tags are rejected.'
}
Assert-Contains $syncWorkflow 'git\s+diff\s+--name-only\s+--diff-filter=U' 'sync-upstream.yml must inspect merge conflicts before resolving fork-policy conflicts.'
Assert-Contains $syncWorkflow '\.github/workflows/release\.yml' 'sync-upstream.yml must resolve upstream release workflow conflicts by keeping the fork private-only policy.'
Assert-Contains $syncWorkflow 'git\s+rm\s+-f\s+"\$allowed_conflict"' 'sync-upstream.yml must delete the upstream public release workflow when it is the only merge conflict.'
if ($syncWorkflow -match 'softprops/action-gh-release|gh\s+release\s+(create|upload|edit)') {
    throw 'sync-upstream.yml must not publish public GitHub releases.'
}

Assert-Missing '.github\workflows\release.yml' 'The public fork must not contain a release workflow that can publish public executable assets.'
Assert-Contains $pnpmWorkspace '(?ms)onlyBuiltDependencies:\s+-\s+esbuild' 'pnpm-workspace.yaml must allow the esbuild install script under pnpm 10.'

Assert-Contains $constants 'public const string Owner = "doveis99";' 'Constants.Owner must point updater links at the fork.'
Assert-Contains $constants 'public const string UpdateOwner = "doveis99";' 'Constants.UpdateOwner must point private updater checks at the release owner.'
Assert-Contains $constants 'public const string UpdateRepoName = "Wand-Enhancer-Releases";' 'Constants.UpdateRepoName must point updater checks at the private release repository.'
Assert-Contains $project 'System\.Net\.Http' 'WandEnhancer.csproj must reference System.Net.Http for the updater.'
Assert-Contains $project 'Utils\\Updater\.cs' 'WandEnhancer.csproj must compile the updater.'
Assert-Contains $project 'View\\Popups\\UpdatePopup\.xaml\.cs' 'WandEnhancer.csproj must compile the update popup code-behind.'
Assert-Contains $project 'View\\Popups\\UpdatePopup\.xaml' 'WandEnhancer.csproj must include the update popup XAML.'
Assert-Contains $mainWindow 'Command="\{Binding UpdateCommand\}"' 'MainWindow.xaml must expose the update command.'
Assert-Contains $mainWindowVm 'UpdateCommand\s*=\s*new RelayCommand\(OnUpdate\);' 'MainWindowVm must initialize UpdateCommand.'
Assert-Contains $updater 'releases/latest' 'Updater must query GitHub releases.'
Assert-Contains $updater 'WAND_ENHANCER_GITHUB_TOKEN' 'Updater must read a local GitHub token instead of embedding one.'
Assert-Contains $updater 'AuthenticationHeaderValue\("Bearer"' 'Updater must authenticate to the private release repository.'
Assert-Contains $updater 'Constants\.UpdateOwner' 'Updater must query the private release repository owner.'
Assert-Contains $updater 'Constants\.UpdateRepoName' 'Updater must query the private release repository name.'
Assert-Contains $updater 'application/octet-stream' 'Updater must download private release assets through the GitHub asset API.'

Write-Host 'Fork automation and updater wiring validated.'
