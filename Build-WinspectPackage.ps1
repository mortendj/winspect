<#
.SYNOPSIS
Builds a distributable zip package of Winspect.

.DESCRIPTION
Packages Invoke-Winspect.ps1, src/, README.md, and LICENSE - everything needed to actually run
the tool - into dist/winspect-vX.Y.Z.zip, with the version read from src/Constants.ps1 so the
package name can't drift out of sync with the code. Deliberately excludes Tests/ and the old-*
legacy reference material, neither of which a shipped copy of the tool needs.
#>

[CmdletBinding()]
param()

$repoRoot = $PSScriptRoot
. (Join-Path $repoRoot "src\Constants.ps1")

$packageName = "winspect-v$SCRIPT_VERSION"
$distDir = Join-Path $repoRoot "dist"
$zipPath = Join-Path $distDir "$packageName.zip"
$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) $packageName
$packageRoot = Join-Path $stagingDir "Winspect"

if (Test-Path $stagingDir) {
    Remove-Item -Path $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $packageRoot | Out-Null

Copy-Item -Path (Join-Path $repoRoot "Invoke-Winspect.ps1") -Destination $packageRoot
Copy-Item -Path (Join-Path $repoRoot "src") -Destination $packageRoot -Recurse
Copy-Item -Path (Join-Path $repoRoot "README.md") -Destination $packageRoot
Copy-Item -Path (Join-Path $repoRoot "LICENSE") -Destination $packageRoot

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}
Compress-Archive -Path $packageRoot -DestinationPath $zipPath

Remove-Item -Path $stagingDir -Recurse -Force

Write-Host "Built $zipPath"
