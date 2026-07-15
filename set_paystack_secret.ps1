Set-Location "C:\Users\BOK\limpopo_voice"

# Securely prompt for the key without showing it in the script code
$key = Read-Host "Paste your Paystack Secret Key"
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Error "Paystack Secret Key is empty."
  exit 1
}

Set-Content -Path .\paystack_secret.txt -NoNewline -Value $key

Get-Item .\paystack_secret.txt | Select-Object Name,Length | Format-Table -AutoSize

# Set the secret in Firebase
firebase functions:secrets:set PAYSTACK_SECRET_KEY --data-file .\paystack_secret.txt
if ($LASTEXITCODE -ne 0) {
  Remove-Item .\paystack_secret.txt -ErrorAction SilentlyContinue
  exit $LASTEXITCODE
}

# Deploy all Paystack related functions to apply the new secret
# Using the africa-south1 region prefix for 2nd gen functions
firebase deploy --only functions:africa-south1:createPaystackTransaction,functions:africa-south1:createPaystackTransactionHttp,functions:africa-south1:paystackWebhook
$deployExit = $LASTEXITCODE

# Clean up the temporary file
Remove-Item .\paystack_secret.txt -ErrorAction SilentlyContinue

if ($deployExit -ne 0) { 
    Write-Warning "Specific function deployment failed. Retrying with general functions filter..."
    firebase deploy --only functions
    $deployExit = $LASTEXITCODE
}

if ($deployExit -ne 0) { exit $deployExit }

firebase functions:log --only createPaystackTransaction --lines 15
