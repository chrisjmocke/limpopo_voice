Set-Location "C:\Users\BOK\limpopo_voice"

$secretRoot = Join-Path $env:LOCALAPPDATA 'LimpopoVoice\secrets'
New-Item -ItemType Directory -Force -Path $secretRoot | Out-Null
$keyFile = Join-Path $secretRoot 'gemini_key.txt'

$key = Read-Host "Paste new Gemini API key"
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Error "Gemini API key is empty."
  exit 1
}

Set-Content -Path $keyFile -NoNewline -Value $key

Get-Item $keyFile | Select-Object Name,Length | Format-Table -AutoSize

firebase functions:secrets:set GEMINI_API_KEY --data-file $keyFile
if ($LASTEXITCODE -ne 0) {
  Remove-Item $keyFile -ErrorAction SilentlyContinue
  exit $LASTEXITCODE
}

firebase deploy --only functions:processSpeech
$deployExit = $LASTEXITCODE

Remove-Item $keyFile -ErrorAction SilentlyContinue

if ($deployExit -ne 0) { exit $deployExit }

firebase functions:log --only processSpeech --lines 15
