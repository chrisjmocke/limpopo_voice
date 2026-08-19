Set-Location "C:\Users\BOK\limpopo_voice"

# Securely prompt for the keys
$clientId = Read-Host "Paste your PayPal Client ID" -AsSecureString
$clientSecret = Read-Host "Paste your PayPal Secret" -AsSecureString

$clientIdPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientId))
$clientSecretPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientSecret))

if ([string]::IsNullOrWhiteSpace($clientIdPlain) -or [string]::IsNullOrWhiteSpace($clientSecretPlain)) {
  Write-Error "PayPal credentials cannot be empty."
  exit 1
}

# Write to temporary files
Set-Content -Path .\paypal_client_id.txt -NoNewline -Value $clientIdPlain
Set-Content -Path .\paypal_secret.txt -NoNewline -Value $clientSecretPlain

# Set the secrets in Firebase
firebase functions:secrets:set PAYPAL_CLIENT_ID --data-file .\paypal_client_id.txt
firebase functions:secrets:set PAYPAL_SECRET --data-file .\paypal_secret.txt

# Deploy PayPal related functions
firebase deploy --only functions:africa-south1:createPayPalOrderHttp,functions:africa-south1:capturePayPalOrderHttp
$deployExit = $LASTEXITCODE

# Clean up
Remove-Item .\paypal_client_id.txt -ErrorAction SilentlyContinue
Remove-Item .\paypal_secret.txt -ErrorAction SilentlyContinue

if ($deployExit -ne 0) { exit $deployExit }
