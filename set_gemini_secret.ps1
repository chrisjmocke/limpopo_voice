Set-Location "C:\Users\BOK\limpopo_voice"

$key = Read-Host "Paste new Gemini API key"
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Error "Gemini API key is empty."
  exit 1
}

Set-Content -Path .\gemini_key.txt -NoNewline -Value $key

Get-Item .\gemini_key.txt | Select-Object Name,Length | Format-Table -AutoSize

firebase functions:secrets:set GEMINI_API_KEY --data-file .\gemini_key.txt
if ($LASTEXITCODE -ne 0) {
  Remove-Item .\gemini_key.txt -ErrorAction SilentlyContinue
  exit $LASTEXITCODE
}

firebase deploy --only functions:processSpeech
$deployExit = $LASTEXITCODE

Remove-Item .\gemini_key.txt -ErrorAction SilentlyContinue

if ($deployExit -ne 0) { exit $deployExit }

firebase functions:log --only processSpeech --lines 15
