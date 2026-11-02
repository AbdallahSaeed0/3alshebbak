# Premiere's showtimes, from this computer: Cloudflare turns GitHub's runners
# away from premiere-cinemas.com, but an ordinary home connection gets through.
# Adds the presale days past elCinema's week for the branches elCinema lists,
# and every day for the ones it doesn't (Nile Cinema, Galaxy elManial).
# Alerts for what this adds go out with the next GitHub run.
#
# Run by hand, or every few hours from Task Scheduler:
#   powershell -NoProfile -ExecutionPolicy Bypass -File <repo>\scraper\scripts\presales.ps1
# Needs scraper\.env (Supabase + TMDB keys) and `npx playwright install chromium` once.

param(
  # Temp files and the log go here, not on C:.
  [string]$WorkDir = 'D:\3alShebbak-presales'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force (Join-Path $WorkDir 'tmp') | Out-Null
$env:TEMP = Join-Path $WorkDir 'tmp'
$env:TMP = $env:TEMP
$log = Join-Path $WorkDir 'presales.log'

Set-Location (Join-Path $PSScriptRoot '..')
"=== $(Get-Date -Format s)" | Out-File -Append -Encoding utf8 $log
npm run pipeline -- premiere 2>&1 | Out-File -Append -Encoding utf8 $log
"exit $LASTEXITCODE" | Out-File -Append -Encoding utf8 $log
exit $LASTEXITCODE
