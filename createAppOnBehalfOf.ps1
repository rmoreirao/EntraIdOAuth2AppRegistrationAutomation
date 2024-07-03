# Define the necessary variables
$clientId = "clientId"
$clientSecret = "clientSecret"
$tenantId = "tenantID"

# Obtain an access token
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
}

$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -ContentType "application/x-www-form-urlencoded" -Body $body
$accessToken = $tokenResponse.access_token

# Create the new application
$headers = @{
    Authorization = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

$applicationBody = @{
    displayName      = "HEI-DI-API-TestAppCreation"
    web              = @{}
    api              = @{
        requestedAccessTokenVersion = 2
    }
    signInAudience   = "AzureADMyOrg"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/applications" -Headers $headers -Body $applicationBody
    $currentAppId = $response.appId
    $currentAppObjectId = $response.id
    Write-Host "New application created with App ID: $currentAppId and Object ID: $currentAppObjectId"
} catch {
    Write-Host "Error creating application: $_"
}

# Wait for user "Enter"
Write-Host "Press Enter to continue before we delete the App..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Delete the App Registration
try {
    $response = Invoke-RestMethod -Method Delete -Uri "https://graph.microsoft.com/v1.0/applications/$currentAppObjectId" -Headers $headers
    Write-Host "Application deleted"
} catch {
    Write-Host "Error deleting application: $_"
}