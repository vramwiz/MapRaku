$ErrorActionPreference = 'Stop'

$packageName = 'SYNC_MapRaku'
$projectDir = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectDir 'Win64\Plugin\Release'
$stagingDir = Join-Path $PSScriptRoot '.release-staging'
$workDir = Join-Path $stagingDir $packageName
$zipFile = Join-Path $PSScriptRoot "$packageName.zip"

$packageFiles = @(
  @{
    Source = Join-Path $releaseDir 'SYNC_MapRaku_Filter.auf2'
    Destination = 'SYNC_MapRaku_Filter.auf2'
    Description = 'AviUtl2 filter plugin'
  },
  @{
    Source = Join-Path $releaseDir 'sk4d.dll'
    Destination = 'sk4d.dll'
    Description = 'Skia runtime'
  },
  @{
    Source = Join-Path $projectDir 'README.md'
    Destination = 'README.md'
    Description = 'usage guide'
  },
  @{
    Source = Join-Path $projectDir 'Docs\PLUGIN.md'
    Destination = 'Docs\PLUGIN.md'
    Description = 'plugin guide'
  },
  @{
    Source = Join-Path $projectDir 'Docs\AI_PIPE.md'
    Destination = 'Docs\AI_PIPE.md'
    Description = 'AI pipe guide'
  },
  @{
    Source = Join-Path $projectDir 'Tools\Automation\MapRakuPipe.psm1'
    Destination = 'Tools\Automation\MapRakuPipe.psm1'
    Description = 'AI pipe client module'
  }
)

foreach ($item in $packageFiles) {
  if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) {
    Write-Host "$($item.Description) not found:"
    Write-Host "  $($item.Source)"
    Write-Host 'Build the Release plugin before creating the distribution ZIP.'
    exit 1
  }
}

# Cleanup is restricted to the generated staging directory under Setup; the
# checked-in Setup/SYNC_MapRaku files are never used as temporary output.
$expectedWorkDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.release-staging\SYNC_MapRaku'))
if ([IO.Path]::GetFullPath($workDir) -ne $expectedWorkDir) {
  throw 'Unexpected package staging directory.'
}
if (Test-Path -LiteralPath $workDir) {
  $existingWorkDir = Get-Item -LiteralPath $workDir
  if ($existingWorkDir.FullName -ne $expectedWorkDir -or
      ($existingWorkDir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Package staging directory must be a regular directory under Setup.'
  }
  Remove-Item -LiteralPath $workDir -Recurse -Force
}

if (Test-Path -LiteralPath $zipFile) {
  Remove-Item -LiteralPath $zipFile -Force
}

try {
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null
  foreach ($item in $packageFiles) {
    $destination = Join-Path $workDir $item.Destination
    $destinationDir = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
      New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $item.Source -Destination $destination -Force
  }
  Compress-Archive -Path $workDir -DestinationPath $zipFile -Force
}
finally {
  if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
  }
}

Write-Host 'Created:'
Write-Host "  $zipFile"
