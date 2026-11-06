#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Device,
    [switch]$Baseline,
    [switch]$MainPage,
    [switch]$InlineSoftSpace,
    [ValidateSet('native', 'legacy', 'both')]
    [string]$Backend = 'both',
    [ValidateSet('baseline', 'long-text', 'semantic', 'ruby-gaps', 'language', 'ruby-nested', 'ruby-mixed-nested', 'ruby-nested-columns')]
    [string]$Corpus = 'baseline',
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$profileRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.local/renderer_profile'))
$profileId = 'com.adws.y300.renderer_profile'
$markerPath = Join-Path $profileRoot '.profile-owner.json'
if (-not $profileRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Profile target must stay inside the repository.'
}
if (-not $PrepareOnly -and [string]::IsNullOrWhiteSpace($Device)) {
    throw 'Provide -Device (the Flutter device ID).'
}
if ($InlineSoftSpace -and -not $MainPage) {
    throw '-InlineSoftSpace requires -MainPage.'
}
if ($Corpus -ne 'baseline' -and -not $MainPage) {
    throw "-Corpus $Corpus requires -MainPage."
}

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}
function Write-Utf8([string]$Path, [string]$Value) {
    [IO.File]::WriteAllText($Path, $Value, $utf8)
}
function Assert-NativeSuccess([string]$Operation) {
    if ($LASTEXITCODE -ne 0) { throw "$Operation failed ($LASTEXITCODE)." }
}
function Read-LockedVersions([string]$Path) {
    $versions = @{}
    $packageName = ''
    foreach ($line in (Read-Utf8 $Path).Split("`n")) {
        if ($line -match '^  ([a-z0-9_]+):\s*$') { $packageName = $Matches[1] }
        if ($line -match '^    version: "([^"]+)"') { $versions[$packageName] = $Matches[1] }
    }
    return $versions
}

Push-Location $repoRoot
try {
    & git check-ignore --quiet -- .local/renderer_profile/pubspec.yaml
    if ($LASTEXITCODE -ne 0) { throw 'Ignore .local/renderer_profile locally before generating the profile target.' }
    $revision = (& git rev-parse --short HEAD).Trim()
    Assert-NativeSuccess 'Read revision'
    $branch = (& git branch --show-current).Trim()
    if ([string]::IsNullOrEmpty($branch)) { $branch = "detached-$revision" }
    if (& git status --porcelain --untracked-files=no) { $revision += '-dirty' }
    $mainGradle = Read-Utf8 (Join-Path $repoRoot 'android/app/build.gradle.kts')
    $mainId = [regex]::Match($mainGradle, 'applicationId\s*=\s*"([^"]+)"').Groups[1].Value
    if ([string]::IsNullOrEmpty($mainId) -or $profileId -eq $mainId) {
        throw 'Cannot prove the profile application ID is separate from the App.'
    }

    if (Test-Path -LiteralPath $profileRoot) {
        if (-not (Test-Path -LiteralPath $markerPath)) { throw 'Existing profile directory is not owned by this script.' }
        $owner = (Read-Utf8 $markerPath) | ConvertFrom-Json
        if ($owner.repository -ne $repoRoot -or $owner.applicationId -ne $profileId) {
            throw 'Profile ownership marker does not match this repository.'
        }
    } else {
        & flutter create --empty --no-pub --platforms android --org com.adws.y300 --project-name renderer_profile $profileRoot
        Assert-NativeSuccess 'Create profile target'
        Write-Utf8 $markerPath (@{ repository = $repoRoot; applicationId = $profileId } | ConvertTo-Json)
    }

    # Share the toolchain while keeping the generated independent app/signing.
    foreach ($relative in @('android/settings.gradle.kts', 'android/build.gradle.kts', 'android/gradle/wrapper/gradle-wrapper.properties')) {
        Write-Utf8 (Join-Path $profileRoot $relative) (Read-Utf8 (Join-Path $repoRoot $relative))
    }
    $desugar = [regex]::Match($mainGradle, 'coreLibraryDesugaring\("([^"]+)"\)').Groups[1].Value
    if ([string]::IsNullOrEmpty($desugar)) { throw 'Cannot resolve the production desugaring dependency.' }
    $modulePath = Join-Path $profileRoot 'android/app/build.gradle.kts'
    $module = Read-Utf8 $modulePath
    $generatedId = [regex]::Match($module, 'applicationId\s*=\s*"([^"]+)"').Groups[1].Value
    if ($generatedId -ne $profileId) { throw 'Generated profile module has an unexpected application ID.' }
    if ($module -notmatch 'id\("org.jetbrains.kotlin.android"\)') {
        $module = $module.Replace('id("com.android.application")', "id(`"com.android.application`")`n    id(`"org.jetbrains.kotlin.android`")")
    }
    if ($module -notmatch 'isCoreLibraryDesugaringEnabled') {
        $module = $module.Replace('compileOptions {', "compileOptions {`n        isCoreLibraryDesugaringEnabled = true")
    }
    $existingDesugar = [regex]::Match($module, 'coreLibraryDesugaring\("[^"]+"\)').Value
    if ([string]::IsNullOrEmpty($existingDesugar)) {
        $module += "`ndependencies {`n    coreLibraryDesugaring(`"$desugar`")`n}`n"
    } else {
        $module = $module.Replace($existingDesugar, "coreLibraryDesugaring(`"$desugar`")")
    }
    Write-Utf8 $modulePath $module
    Write-Utf8 (Join-Path $profileRoot 'pubspec.yaml') @'
name: renderer_profile
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  y300:
    path: ../..
dev_dependencies:
  flutter_lints: ^6.0.0
flutter:
  uses-material-design: true
'@
    $entry = if ($MainPage) { 'tool/novel_main_page_profile.dart' } else { 'tool/novel_pagination_profile.dart' }
    $target = ([Uri]::new((Join-Path $repoRoot $entry))).AbsoluteUri.Replace("'", '%27')
    Write-Utf8 (Join-Path $profileRoot 'lib/main.dart') "import '$target' as benchmark;`n`nvoid main() => benchmark.main();`n"
    Write-Utf8 (Join-Path $profileRoot 'pubspec.lock') (Read-Utf8 (Join-Path $repoRoot 'pubspec.lock'))

    Push-Location $profileRoot
    try {
        & flutter pub get --offline
        Assert-NativeSuccess 'Resolve profile dependencies from the production lock'
        $rootVersions = Read-LockedVersions (Join-Path $repoRoot 'pubspec.lock')
        $targetVersions = Read-LockedVersions (Join-Path $profileRoot 'pubspec.lock')
        foreach ($name in $targetVersions.Keys) {
            if ($rootVersions.ContainsKey($name) -and $rootVersions[$name] -ne $targetVersions[$name]) {
                throw "Profile dependency differs from the App: $name."
            }
        }
        if ($PrepareOnly) { return }
        $logRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot ".local/agent-notes/$branch"))
        if (-not $logRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Profile log must stay inside the repository.'
        }
        [IO.Directory]::CreateDirectory($logRoot) | Out-Null
        $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $logPath = Join-Path $logRoot "novel-profile-$stamp.log"
        $runArguments = @('run', '--profile', '-d', $Device, '--no-pub', '--machine',
            "--dart-define=PROFILE_REVISION=$revision", "--dart-define=PROFILE_DEVICE=$Device",
            '--dart-define=PROFILE_AUTO_EXIT=true')
        if ($Baseline) { $runArguments += '--dart-define=PROFILE_BASELINE=true' }
        if ($MainPage) { $runArguments += "--dart-define=PROFILE_BACKEND=$Backend" }
        if ($MainPage) { $runArguments += "--dart-define=PROFILE_CORPUS=$Corpus" }
        if ($InlineSoftSpace) { $runArguments += '--dart-define=PROFILE_INLINE_SOFT_SPACE=true' }
        $script:profileSuiteResult = $null
        $script:profileFrameReports = 0
        & flutter @runArguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $line | Out-File -LiteralPath $logPath -Append -Encoding utf8
            Write-Host $line
            $index = $line.IndexOf('NOVEL_PROFILE ')
            if ($index -ge 0) {
                try {
                    $record = $line.Substring($index + 14) | ConvertFrom-Json
                    if ($record.event -eq 'suite_done') { $script:profileSuiteResult = $record }
                    if ($record.event -in @('phase_frames', 'phase_frame_over_50ms')) {
                        $script:profileFrameReports++
                    }
                } catch { }
            }
        }
        Assert-NativeSuccess 'Run profile target'
        if ($null -eq $script:profileSuiteResult -or -not $script:profileSuiteResult.suitePassed) {
            throw "Profile suite did not pass. See $logPath"
        }
        if ($MainPage -and $script:profileSuiteResult.frameReportCount -ne $script:profileFrameReports) {
            throw "Incomplete profile frame output. Expected $($script:profileSuiteResult.frameReportCount), received $script:profileFrameReports. See $logPath"
        }
        Write-Host "Profile results: $logPath"
    } finally { Pop-Location }
} finally { Pop-Location }
