Set-Location "C:\Users\BOK\limpopo_voice"

$key = Read-Host "Paste new Narakeet API key"
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Error "Narakeet API key is empty."
  exit 1
}

Set-Content -Path .\narakeet_key.txt -NoNewline -Value $key

Get-Item .\narakeet_key.txt | Select-Object Name, Length | Format-Table -AutoSize

firebase functions:secrets:set NARAKEET_API_KEY --data-file .\narakeet_key.txt
if ($LASTEXITCODE -ne 0) {
  Remove-Item .\narakeet_key.txt -ErrorAction SilentlyContinue
  exit $LASTEXITCODE
}

firebase deploy --only functions:processSpeech
$deployExit = $LASTEXITCODE

Remove-Item .\narakeet_key.txt -ErrorAction SilentlyContinue

if ($deployExit -ne 0) { exit $deployExit }

firebase functions:log --only processSpeech --lines 20
