#Requires -Version 7.0
<#
.SYNOPSIS
    Generates this lab's TLS material from the developer's own local mkcert CA.
.DESCRIPTION
    certs\docker-host-mkcert-rootCA.crt     -> baked into the TeamCity server/agent images
    certs\nginx.pem + certs\nginx-key.pem   -> served by nginx (MinIO, Garage, LDAPS)

    None of it is committed - you generate your own. Re-running is a no-op.
.PARAMETER Force
    Re-mint the certificate and re-copy the root CA regardless of their current state.
#>
[CmdletBinding()]
param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Hostnames the nginx certificate is valid for. Adding one here re-mints on the next run.
# Vhost-style S3 needs '*.s3.nginx': a bare '*.nginx' fails hostname verification (see garage.toml).
$CertHosts = @('nginx', '*.nginx', 's3.nginx', '*.s3.nginx', 'localhost', '127.0.0.1', '::1',
               'host.docker.internal')
# Re-mint when the certificate is within this many days of expiring.
$RenewBeforeDays = 30

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$CertsDir   = Join-Path $RepoRoot 'certs'
$RootCaDest = Join-Path $CertsDir 'docker-host-mkcert-rootCA.crt'
$LeafCert   = Join-Path $CertsDir 'nginx.pem'
$LeafKey    = Join-Path $CertsDir 'nginx-key.pem'

function Write-Ok   { param([string]$Message) Write-Host "OK   $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "!    $Message" -ForegroundColor Yellow }

# --- 1. mkcert ----------------------------------------------------------------------
if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
    Write-Host 'mkcert not found. Install mkcert first (see README.md), then re-run this script.' `
        -ForegroundColor Red
    exit 1
}

# --- 2. Local CA --------------------------------------------------------------------
# `mkcert -install` adds the CA to the OS (and browser) trust store, which is what makes
# https://localhost:9001 trusted on this machine. CAROOT is %LOCALAPPDATA%\mkcert on
# Windows, so never hardcode it - always ask mkcert.
$caRoot    = (& mkcert -CAROOT).Trim()
$rootCaPem = Join-Path $caRoot 'rootCA.pem'
if (-not (Test-Path -LiteralPath $rootCaPem)) {
    Write-Warn "No mkcert CA in $caRoot - running 'mkcert -install'."
    Write-Warn "Windows shows a 'Security Warning - install this certificate?' dialog: choose Yes."
    & mkcert -install
    if ($LASTEXITCODE -ne 0) {
        throw "mkcert -install failed (exit $LASTEXITCODE). Try again from an elevated pwsh."
    }
}
if (-not (Test-Path -LiteralPath $rootCaPem)) {
    throw "mkcert -install did not produce $rootCaPem"
}

New-Item -ItemType Directory -Force -Path $CertsDir | Out-Null

# --- 3. Root CA copy for the TeamCity image builds ----------------------------------
# Copy-Item, not Get-Content/Set-Content: the latter would add a BOM and break
# update-ca-certificates and keytool inside the images. Only copied when it actually
# differs, so re-running does not bust the Docker build cache.
$rootCaChanged = $false
if (-not (Test-Path -LiteralPath $RootCaDest) -or
    (Get-FileHash -LiteralPath $rootCaPem).Hash -ne (Get-FileHash -LiteralPath $RootCaDest).Hash) {
    Copy-Item -LiteralPath $rootCaPem -Destination $RootCaDest -Force
    $rootCaChanged = $true
}

# --- 4. nginx leaf certificate ------------------------------------------------------
function Test-LeafCurrent {
    if (-not (Test-Path -LiteralPath $LeafCert) -or -not (Test-Path -LiteralPath $LeafKey)) {
        return $false
    }

    try {
        # CreateFromPem, not CreateFromPemFile: the latter demands a cert+key pair and
        # these PEMs are cert-only (the key lives in a separate file).
        $leaf = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem(
            (Get-Content -Raw -LiteralPath $LeafCert))
        $ca   = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem(
            (Get-Content -Raw -LiteralPath $rootCaPem))
    } catch { return $false }

    if ($leaf.NotAfter -lt (Get-Date).AddDays($RenewBeforeDays)) { return $false }

    # Catches "I reinstalled mkcert, so my CA changed but the old leaf is still lying here".
    if ($leaf.Issuer -ne $ca.Subject) { return $false }

    # Catches edits to $CertHosts above. IPv6 literals are skipped: ::1 is rendered in
    # expanded form, which would never match and would re-mint every run.
    $sanExt = $leaf.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
    if (-not $sanExt) { return $false }
    $sans = $sanExt.Format($false)
    foreach ($certHost in $CertHosts) {
        if ($certHost -like '*:*') { continue }
        if ($sans -notlike "*$certHost*") { return $false }
    }

    return $true
}

$leafChanged = $false
if ($Force -or -not (Test-LeafCurrent)) {
    # Splatting passes *.nginx verbatim - PowerShell does not glob arguments.
    & mkcert -cert-file $LeafCert -key-file $LeafKey @CertHosts
    if ($LASTEXITCODE -ne 0) { throw "mkcert failed (exit $LASTEXITCODE)" }
    $leafChanged = $true
}

# --- 5. Report ----------------------------------------------------------------------
if ($rootCaChanged) {
    Write-Ok   "Wrote $(Split-Path -Leaf $RootCaDest)"
    Write-Warn 'Root CA changed - rebuild the images:'
    Write-Host '       docker compose up -d --build teamcity teamcity-agent'
} else {
    Write-Ok 'Root CA already up to date'
}

if ($leafChanged) {
    Write-Ok   "Wrote $(Split-Path -Leaf $LeafCert) and $(Split-Path -Leaf $LeafKey)"
    Write-Warn 'Certificate changed - recreate nginx:'
    Write-Host '       docker compose up -d --force-recreate nginx'
} else {
    $leaf = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem(
        (Get-Content -Raw -LiteralPath $LeafCert))
    Write-Ok "nginx certificate valid until $($leaf.NotAfter.ToUniversalTime().ToString('u'))"
}
