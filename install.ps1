<#
.SYNOPSIS
    Offline installer for Basic Memory (bm) on Windows x64, no PyPI access needed.

.DESCRIPTION
    Installs basic-memory 0.24.1 from the bundled wheel set with uv, then wires up
    the Pi integration (extension + setup skills) and the memory-onboarding skill.

    Everything here resolves from local files: uv is pointed at the wheel folders
    with --no-index --offline --no-build, so a machine that can only reach GitHub
    (to fetch this repo / bundle) and npm needs nothing else.

.PARAMETER Bundle
    Path to the wheel bundle zip or an already-extracted bundle directory.
    Default: the zip next to this script, else the GitHub release asset.

.PARAMETER PyVersion
    Target interpreter, "3.13" or "3.12". Default: auto-detect (3.13 first).

.PARAMETER ProjectName
    Optional: create/point a Basic Memory project at -ProjectPath and make it default.

.PARAMETER ProjectPath
    Optional: directory that holds the markdown notes for -ProjectName.

.PARAMETER SkipPi
    Do not run `bm install pi` (skip the Pi extension + setup skills).

.PARAMETER Force
    Reinstall bm even if the same version is already present (uv tool install --force).

.PARAMETER NoPath
    Do not touch the user PATH; only print the export line to run manually.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Bundle C:\temp\basic-memory-0.24.1-win_amd64-wheels.zip -PyVersion 3.12
    .\install.ps1 -ProjectName main -ProjectPath D:\notes\main
#>
[CmdletBinding()]
param(
    [string]$Bundle = "",
    [string]$PyVersion = "",
    [string]$ProjectName = "",
    [string]$ProjectPath = "",
    [switch]$SkipPi,
    [switch]$Force,
    [switch]$NoPath
)

$ErrorActionPreference = "Stop"
$Version = "0.24.1"
$ReleaseTag = "v$Version"
$ReleaseAsset = "basic-memory-$Version-win_amd64-wheels.zip"
$ReleaseUrl = "https://github.com/wangpanchn/basic-memory-offline/releases/download/$ReleaseTag/$ReleaseAsset"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    ok: $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "    warn: $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- 1. locate bundle
Write-Step "Locating the wheel bundle"

if ($Bundle -eq "") {
    $candidate = Join-Path $ScriptRoot $ReleaseAsset
    if (Test-Path $candidate) {
        $Bundle = $candidate
    } elseif ((Test-Path (Join-Path $ScriptRoot "wheels-pure")) -and (Test-Path (Join-Path $ScriptRoot "wheels-cp313"))) {
        $Bundle = $ScriptRoot
    } else {
        $Bundle = $ReleaseUrl
    }
}

$WorkRoot = Join-Path $env:LOCALAPPDATA "basic-memory-offline"
$WheelRoot = Join-Path $WorkRoot "wheels-$Version"

if (Test-Path $Bundle -PathType Container) {
    $WheelRoot = (Resolve-Path $Bundle).Path
    Write-Ok "using extracted bundle at $WheelRoot"
} else {
    if (-not (Test-Path $Bundle)) {
        Write-Host "    downloading $Bundle"
        New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
        $zipPath = Join-Path $WorkRoot $ReleaseAsset
        try {
            Invoke-WebRequest -Uri $Bundle -OutFile $zipPath -UseBasicParsing
        } catch {
            Fail "cannot download the bundle. Copy $ReleaseAsset here by hand (or pass -Bundle <path>) and rerun. Original error: $($_.Exception.Message)"
        }
        $Bundle = $zipPath
    }
    Write-Host "    extracting $(Split-Path -Leaf $Bundle)"
    if (Test-Path $WheelRoot) { Remove-Item -Recurse -Force $WheelRoot }
    New-Item -ItemType Directory -Force -Path $WheelRoot | Out-Null
    Expand-Archive -Path $Bundle -DestinationPath $WheelRoot -Force
    if (Test-Path (Join-Path $WheelRoot "wheels-pure")) {
        Write-Ok "extracted to $WheelRoot"
    } elseif (Test-Path (Join-Path $WheelRoot "basic-memory-$Version-win_amd64")) {
        $WheelRoot = Join-Path $WheelRoot "basic-memory-$Version-win_amd64"
        Write-Ok "extracted to $WheelRoot"
    } else {
        Fail "unexpected bundle layout under $WheelRoot (no wheels-pure directory)"
    }
}

$PureDir = Join-Path $WheelRoot "wheels-pure"
if (-not (Test-Path $PureDir)) { Fail "missing $PureDir" }

# ------------------------------------------------------------- 2. verify checksums
Write-Step "Verifying wheel checksums"
$sumFile = Join-Path $WheelRoot "SHA256SUMS.txt"
if (Test-Path $sumFile) {
    $bad = 0
    foreach ($line in Get-Content $sumFile) {
        if ($line.Trim() -eq "" -or $line.StartsWith("#")) { continue }
        $parts = $line -split '\s+', 2
        if ($parts.Length -ne 2) { continue }
        $expected = $parts[0]
        $rel = $parts[1].Trim()
        $file = Join-Path $WheelRoot $rel
        if (-not (Test-Path $file)) { Write-Warn2 "missing $rel"; $bad++; continue }
        $actual = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
        if ($actual -ne $expected.ToLower()) { Write-Warn2 "checksum mismatch: $rel"; $bad++ }
    }
    if ($bad -gt 0) { Fail "$bad wheel(s) failed verification; re-download the bundle" }
    Write-Ok "all wheel checksums match"
} else {
    Write-Warn2 "no SHA256SUMS.txt in the bundle; skipping verification"
}

# ------------------------------------------------------------------- 3. find uv
Write-Step "Checking uv"
$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
    Fail @"
uv is not on PATH. Install it first (GitHub access is enough):

  Invoke-WebRequest https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip -OutFile uv.zip
  Expand-Archive uv.zip -DestinationPath "$env:LOCALAPPDATA\uv"
  setx PATH "%PATH%;$env:LOCALAPPDATA\uv"

...then open a new shell and rerun this script.
"@
}
$uvExe = $uv.Source
Write-Ok "uv $(& $uvExe --version)"

# ---------------------------------------------------------------- 4. pick python
Write-Step "Picking a Python interpreter"
$candidates = @()
if ($PyVersion -ne "") { $candidates += $PyVersion } else { $candidates += @("3.13", "3.12") }

$pyFound = ""
foreach ($cand in $candidates) {
    $cp = "cp" + ($cand -replace '\.', '')
    if (-not (Test-Path (Join-Path $WheelRoot "wheels-$cp"))) {
        Write-Warn2 "no wheel set for $cand in this bundle (wheels-$cp missing); skipping"
        continue
    }
    $out = & $uvExe python find $cand --no-python-downloads 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
        $pyFound = $cand
        Write-Ok "python $cand at $($out | Select-Object -First 1)"
        break
    }
    Write-Warn2 "python $cand not installed"
}

if ($pyFound -eq "") {
    Fail @"
No supported interpreter found. Either

  a) install one where GitHub is reachable:   uv python install 3.13
     (uv downloads standalone builds from github.com/astral-sh/python-build-standalone)
  b) or point at an existing install:          .\install.ps1 -PyVersion 3.12

Supported by this bundle: 3.13, 3.12. basic-memory 0.24.1 pins litellm<1.92 which
does not support 3.14, so 3.14 is not an option.
"@
}

$cpFound = "cp" + ($pyFound -replace '\.', '')
$CpDir = Join-Path $WheelRoot "wheels-$cpFound"

# ------------------------------------------------------ 5. install bm from wheels
Write-Step "Installing basic-memory $Version into an isolated uv tool environment"
$installArgs = @(
    "tool", "install",
    "--python", $pyFound,
    "--no-index", "--offline", "--no-build",
    "--find-links", $PureDir,
    "--find-links", $CpDir,
    "basic-memory==$Version",
    "--with", "socksio"
)
if ($Force) { $installArgs += "--force" }
Write-Host "    uv $($installArgs -join ' ')"

$output = & $uvExe @installArgs 2>&1
$code = $LASTEXITCODE
$output | ForEach-Object { Write-Host "    $_" }
if ($code -ne 0) {
    Fail "uv tool install failed (exit $code). If it complains about a missing package, the bundle is incomplete or the interpreter is not one of $($candidates -join '/' )."
}
Write-Ok "installed"

# -------------------------------------------------------------- 6. make bm usable
Write-Step "Making bm reachable"
$toolBin = Join-Path $env:USERPROFILE ".local\bin"
if (-not (Test-Path (Join-Path $toolBin "bm.exe"))) {
    Write-Warn2 "bm.exe not found in $toolBin — check 'uv tool dir --bin'"
}
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrEmpty($userPath)) { $userPath = "" }
if ($userPath -notlike "*$toolBin*") {
    if ($NoPath) {
        Write-Warn2 "add this to PATH yourself: $toolBin"
    } else {
        $newPath = if ($userPath -eq "") { $toolBin } else { "$userPath;$toolBin" }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$toolBin"
        Write-Ok "appended $toolBin to the user PATH (open a new shell later)"
    }
} else {
    Write-Ok "$toolBin already on the user PATH"
}
$env:Path = "$env:Path;$toolBin"
$bmExe = Join-Path $toolBin "bm.exe"
if (Test-Path $bmExe) {
    $verOut = & $bmExe --version 2>&1 | Select-Object -First 1
    Write-Ok "$verOut"
}

# ------------------------------------------------------- 7. optional local project
if ($ProjectName -ne "" -and $ProjectPath -ne "") {
    Write-Step "Registering project '$ProjectName' at $ProjectPath"
    New-Item -ItemType Directory -Force -Path $ProjectPath | Out-Null
    & $bmExe project add $ProjectName $ProjectPath
    if ($LASTEXITCODE -ne 0) { Write-Warn2 "project add failed; run 'bm project add $ProjectName $ProjectPath' manually" }
    else { Write-Ok "project registered" }
}

# ------------------------------------------------------------ 8. Pi integration
Write-Step "Pi integration"
if ($SkipPi) {
    Write-Warn2 "skipped (-SkipPi). Later: bm install pi --yes"
} else {
    $pi = Get-Command pi -ErrorAction SilentlyContinue
    if (-not $pi) {
        Write-Warn2 "pi is not on PATH — skipping 'bm install pi'. Install Pi (npm i -g @earendil-works/pi-coding-agent) then run: bm install pi --yes"
    } else {
        & $bmExe install pi --yes
        if ($LASTEXITCODE -ne 0) { Write-Warn2 "'bm install pi' failed; rerun it manually" }
        else { Write-Ok "Pi extension + skills registered (restart Pi afterwards)" }
    }
}

# --------------------------------------------------- 9. onboarding skill for Pi
Write-Step "Installing the memory-onboarding skill"
$skillSrc = Join-Path $ScriptRoot "skills\memory-onboarding"
if (-not (Test-Path $skillSrc)) {
    $skillSrc = Join-Path $WheelRoot "skills\memory-onboarding"
}
$skillDst = Join-Path $env:USERPROFILE ".pi\agent\skills\memory-onboarding"
if (-not (Test-Path $skillSrc)) {
    Write-Warn2 "skill payload not found (looked in $ScriptRoot and $WheelRoot); copy skills/memory-onboarding from the repo by hand"
} elseif ((Test-Path $skillDst) -and -not $Force) {
    Write-Warn2 "$skillDst exists; kept as is (use -Force to overwrite)"
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillDst) | Out-Null
    if (Test-Path $skillDst) { Remove-Item -Recurse -Force $skillDst }
    Copy-Item -Recurse -Force $skillSrc $skillDst
    Write-Ok "installed to $skillDst"
}

# ------------------------------------------------------------------ 10. next steps
Write-Step "Done. Next steps"
@"
  1. Open a new shell so PATH and the uv shims are picked up.
  2. Create/point a project:
       bm project add main D:\notes\main       # or: bm project add main %USERPROFILE%\notes\main
       bm status
  3. Offline embedding: leave semantic search off, or follow docs/offline-embedding.md
     before running anything that embeds notes.
  4. In Pi: restart, then run  /skill:basic-memory-pi-setup   (project routing)
     and for a brand new knowledge base:  /skill:memory-onboarding
  5. `bm update` will fail here by design (it talks to PyPI). Upgrade by fetching a
     newer bundle from the GitHub release page and rerunning this script.
"@ | Write-Host
