Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = 'C:\Users\BOK\limpopo_voice'
$KeyFile = Join-Path $root 'narakeet_key.txt'

Set-Location $root

$key = Read-Host "Paste new Narakeet API key"
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Error "Narakeet API key is empty."
  exit 1
}

$key = $key.Trim()
Set-Content -Path $KeyFile -NoNewline -Value $key

if (-not (Test-Path $KeyFile)) {
  Write-Error "Failed to create temporary key file at $KeyFile"
  exit 1
}

Get-Item $KeyFile | Select-Object Name, Length | Format-Table -AutoSize

firebase functions:secrets:set NARAKEET_API_KEY --data-file $KeyFile
if ($LASTEXITCODE -ne 0) {
  Remove-Item $KeyFile -ErrorAction SilentlyContinue
  exit $LASTEXITCODE
}

firebase deploy --only functions:processSpeech
$deployExit = $LASTEXITCODE

Remove-Item $KeyFile -ErrorAction SilentlyContinue

if ($deployExit -ne 0) { exit $deployExit }

firebase functions:log --only processSpeech --lines 20
