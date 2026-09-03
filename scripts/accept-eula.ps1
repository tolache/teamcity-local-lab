# Optional. Records your acceptance of the TeamCity license agreement in
# internal.properties so the setup wizard skips its license page. Run it before
# docker compose up -d, or skip it and accept in the wizard instead.
$ErrorActionPreference = 'Stop'

$config = Join-Path (Split-Path -Parent $PSScriptRoot) 'services/teamcity/server/data/config'
$target = Join-Path $config 'internal.properties'
$property = 'teamcity.licenseAgreement.accepted'
$eulaUrl = 'https://www.jetbrains.com/legal/docs/teamcity/license/'

if ((Test-Path -LiteralPath $target) -and
    (Select-String -LiteralPath $target -Pattern "$property=true" -SimpleMatch -Quiet)) {
    Write-Host 'License agreement already accepted.'
    exit 0
}

Write-Host 'TeamCity requires you to accept its license agreement:'
Write-Host ''
Write-Host "    $eulaUrl"
Write-Host ''
$answer = Read-Host 'Do you accept it? [y/N]'

# A failed read leaves $answer null, and `$null -notmatch ...` is $false, so match
# the affirmative answer and treat everything else as a decline.
if ([string]$answer -match '^\s*y(es)?\s*$') {
    # (?m)^ so the property line is matched, never the comments mentioning it.
    $content = (Get-Content -LiteralPath "$target.dist" -Raw) -replace "(?m)^$property=.*", "$property=true"
    # Java's property loader treats a BOM as part of the first key, so write without one.
    [System.IO.File]::WriteAllText($target, $content, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'Accepted. Now run: docker compose up -d'
}
else {
    [Console]::Error.WriteLine('Declined. You can accept in the TeamCity setup wizard instead.')
    exit 1
}
