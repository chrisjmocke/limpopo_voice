Set-Location "C:\Users\BOK\limpopo_voice"

$secretRoot = Join-Path $env:LOCALAPPDATA 'LimpopoVoice\secrets'
New-Item -ItemType Directory -Force -Path $secretRoot | Out-Null
$keyFile = Join-Path $secretRoot 'paystack_secret.txt'

# Securely prompt for the key without showing it in the script code
$key = Read-Host "Paste your Paystack Secret Key"
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Error "Paystack Secret Key is empty."
  exit 1
}

Set-Content -Path $keyFile -NoNewline -Value $key

Get-Item $keyFile | Select-Object Name,Length | Format-Table -AutoSize

# Set the secret in Firebase
firebase functions:secrets:set PAYSTACK_SECRET_KEY --data-file $keyFile
if ($LASTEXITCODE -ne 0) {
  Remove-Item $keyFile -ErrorAction SilentlyContinue
  exit $LASTEXITCODE
}

# Deploy all Paystack related functions to apply the new secret
# Using the africa-south1 region prefix for 2nd gen functions
firebase deploy --only functions:africa-south1:createPaystackTransaction,functions:africa-south1:createPaystackTransactionHttp,functions:africa-south1:paystackWebhook
$deployExit = $LASTEXITCODE

# Clean up the temporary file
Remove-Item $keyFile -ErrorAction SilentlyContinue

if ($deployExit -ne 0) { 
    Write-Warning "Specific function deployment failed. Retrying with general functions filter..."
    firebase deploy --only functions
    $deployExit = $LASTEXITCODE
}

if ($deployExit -ne 0) { exit $deployExit }

firebase functions:log --only createPaystackTransaction --lines 15
