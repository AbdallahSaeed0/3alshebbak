$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath 'F:\3alShebbak\scraper'
$logDirectory = 'F:\3alShebbak\scraper\out\local-presales-logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory ((Get-Date -Format 'yyyy-MM-dd') + '.log')
try {
  "$(Get-Date -Format o) Starting local booking presales" | Out-File -LiteralPath $logPath -Append -Encoding utf8
  & node --import tsx src/run.ts elcinema-presales *>> $logPath
  if ($LASTEXITCODE -ne 0) { throw 'Scrape failed; existing server data was retained' }
  & node --import tsx src/sync.ts elcinema-presales *>> $logPath
  if ($LASTEXITCODE -ne 0) { throw 'Sync failed' }
  "$(Get-Date -Format o) Completed successfully" | Out-File -LiteralPath $logPath -Append -Encoding utf8
  exit 0
} catch {
  "$(Get-Date -Format o) FAILED: $_" | Out-File -LiteralPath $logPath -Append -Encoding utf8
  exit 1
}
