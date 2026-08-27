#Requires -Version 7.0
<#
.SYNOPSIS
    Moves the `latest` tag onto the TeamCity images built for the TC_VERSION in .env.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DotEnvFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env'

function Write-Ok  { param([string]$Message) Write-Host "OK   $Message" -ForegroundColor Green }
function Write-Err { param([string]$Message) Write-Host "FAIL $Message" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $DotEnvFile)) {
    Write-Err ".env file not found at $DotEnvFile"
    exit 1
}

$tcVersion = Get-Content -LiteralPath $DotEnvFile |
    Where-Object { $_ -match '^TC_VERSION=' } |
    ForEach-Object { ($_ -replace '^TC_VERSION=', '') -split '#' | Select-Object -First 1 } |
    ForEach-Object { $_.Trim() } |
    Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($tcVersion)) {
    Write-Err 'TC_VERSION is not set in .env'
    exit 1
}

function Set-LatestTag {
    param([string]$Image)

    $baseImage = $Image.Split(':')[0]
    & docker image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Image $Image does not exist locally."
        return $false
    }
    Write-Ok "Image $Image exists locally. Tagging as ${baseImage}:latest"
    & docker tag $Image "${baseImage}:latest"
    return ($LASTEXITCODE -eq 0)
}

foreach ($image in @("tolache/teamcity-server:$tcVersion", "tolache/teamcity-agent:$tcVersion")) {
    if (-not (Set-LatestTag $image)) { exit 1 }
}

Write-Ok 'Successfully tagged both images as latest.'
