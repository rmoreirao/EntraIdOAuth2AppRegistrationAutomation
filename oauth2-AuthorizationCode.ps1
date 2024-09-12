# https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow
# https://learn.microsoft.com/en-us/entra/identity-platform/howto-call-a-web-api-with-curl?tabs=dotnet6&pivots=no-api

## Comments:
# 1) Manually Create the App Registration with "Graph API" permissions "Application.ReadWrite.OwnedBy"
# 2) Manually Create Secret for the Application and update the parameters from this script
# 3) Execute the Script and 2 Applications will be created:
#    - HEI DI API ProductSample: Backend API exposing 2 roles
#    - HEI DI API ClientSample: Client API consuming the Backend API roles
# 4) The Client API will be granted permissions to the Backend API roles
#    - For the "Client Credentials" flow, APIs are not exposes via Scopes - they are exposed via App Roles
#    - This also impacts the Request: the scope is just the resource identifier (application ID URI) of the resource you want, affixed with the .default suffix.
#    - Example: https://graph.microsoft.com/.default or api://<app-id>/.default
# 5) The Client API will be granted permissions to the Microsoft Graph API "User.Read.All" permission
# 6) The Roles are returned to the JWT Token as "roles" claim - only if the Admin has consented to the permissions "Grant Admin Consent" from Client -> API Permissions
# 7) The Client API will request a JWT Token using the Client Credentials flow using api://<app-id>/.default
# 8) The Client API will request a JWT Token using the Client Credentials flow for the Microsoft Graph API "User.Read.All" permission
# 9) Manually navigate to the Client App and grant Admin Consent to the permissions
# 10) The Client API will request a JWT Token using the Client Credentials flow using api://<app-id>/.default

function Remove-AppRegistrationsByName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    # Connect to Microsoft Graph
    # This step assumes you have already connected to Microsoft Graph with the necessary permissions

    # Search for app registrations with the specified display name
    $appRegistrations = Get-MgApplication -Filter "displayName eq '$DisplayName'"

    # Check if any app registrations were found
    if ($appRegistrations -ne $null -and $appRegistrations.Count -gt 0) {
        # Loop through the found app registrations and delete them
        foreach ($app in $appRegistrations) {
            # Delete the app registration
            Remove-MgApplication -ApplicationId $app.Id
            Write-Host "Deleted app registration with ID: $($app.Id) and Name: $($app.DisplayName)"
        }
    }
    else {
        Write-Host "No app registrations found with the display name: $DisplayName"
    }
}

Function CreateScope( [string] $value, [string] $userConsentDisplayName, [string] $userConsentDescription, [string] $adminConsentDisplayName, [string] $adminConsentDescription, [string] $consentType) {
    $scope = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphPermissionScope
    $scope.Id = New-Guid
    $scope.Value = $value
    $scope.UserConsentDisplayName = $userConsentDisplayName
    $scope.UserConsentDescription = $userConsentDescription
    $scope.AdminConsentDisplayName = $adminConsentDisplayName
    $scope.AdminConsentDescription = $adminConsentDescription
    $scope.IsEnabled = $true
    $scope.Type = $consentType
    return $scope
}

Function CreateOptionalClaim([string] $name) {
    <#.Description
    This function creates a new Azure AD optional claims  with default and provided values
    #>  

    $appClaim = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphOptionalClaim
    $appClaim.AdditionalProperties = New-Object System.Collections.Generic.List[string]
    $appClaim.Source = $null
    $appClaim.Essential = $false
    $appClaim.Name = $name
    return $appClaim
}

Function CreateAppRole([string] $types, [string] $name, [string] $description) {
    $appRole = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphAppRole
    $appRole.AllowedMemberTypes = New-Object System.Collections.Generic.List[string]
    $typesArr = $types.Split(',')
    foreach ($type in $typesArr) {
        $appRole.AllowedMemberTypes += $type;
    }
    $appRole.DisplayName = $name
    $appRole.Id = New-Guid
    $appRole.IsEnabled = $true
    $appRole.Description = $description
    $appRole.Value = $name;
    return $appRole
}



# Adds the requiredAccesses (expressed as a pipe separated string) to the requiredAccess structure
# The exposed permissions are in the $exposedPermissions collection, and the type of permission (Scope | Role) is 
# described in $permissionType
Function AddResourcePermission($requiredAccess, `
        $exposedPermissions, [string]$requiredAccesses, [string]$permissionType) {
    foreach ($permission in $requiredAccesses.Trim().Split("|")) {
        foreach ($exposedPermission in $exposedPermissions) {
            if ($exposedPermission.Value -eq $permission) {
                $resourceAccess = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess
                $resourceAccess.Type = $permissionType # Scope = Delegated permissions | Role = Application permissions
                $resourceAccess.Id = $exposedPermission.Id # Read directory data
                $requiredAccess.ResourceAccess += $resourceAccess
            }
        }
    }
}

#
# Example: GetRequiredPermissions "Microsoft Graph"  "Graph.Read|User.Read"
# See also: http://stackoverflow.com/questions/42164581/how-to-configure-a-new-azure-ad-application-through-powershell
Function GetRequiredPermissions([string] $applicationDisplayName, [string] $requiredDelegatedPermissions, [string]$requiredApplicationPermissions, $servicePrincipal) {
    # If we are passed the service principal we use it directly, otherwise we find it from the display name (which might not be unique)
    if ($servicePrincipal) {
        $sp = $servicePrincipal
    }
    else {
        $sp = Get-MgServicePrincipal -Filter "DisplayName eq '$applicationDisplayName'"
    }
    $appid = $sp.AppId
    $requiredAccess = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
    $requiredAccess.ResourceAppId = $appid 
    $requiredAccess.ResourceAccess = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess]

    # $sp.Oauth2Permissions | Select Id,AdminConsentDisplayName,Value: To see the list of all the Delegated permissions for the application:
    if ($requiredDelegatedPermissions) {
        AddResourcePermission $requiredAccess -exposedPermissions $sp.Oauth2PermissionScopes -requiredAccesses $requiredDelegatedPermissions -permissionType "Scope"
    }
    
    # $sp.AppRoles | Select Id,AdminConsentDisplayName,Value: To see the list of all the Application permissions for the application
    if ($requiredApplicationPermissions) {
        AddResourcePermission $requiredAccess -exposedPermissions $sp.AppRoles -requiredAccesses $requiredApplicationPermissions -permissionType "Role"
    }
    return $requiredAccess
}


function Remove-AppRegistrationsByName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    # Connect to Microsoft Graph
    # This step assumes you have already connected to Microsoft Graph with the necessary permissions

    # Search for app registrations with the specified display name
    $appRegistrations = Get-MgApplication -Filter "displayName eq '$DisplayName'"

    # Check if any app registrations were found
    if ($appRegistrations -ne $null -and $appRegistrations.Count -gt 0) {
        # Loop through the found app registrations and delete them
        foreach ($app in $appRegistrations) {
            # Delete the app registration
            Remove-MgApplication -ApplicationId $app.Id
            Write-Host "Deleted app registration with ID: $($app.Id) and Name: $($app.DisplayName)"
        }
    }

    # Search for service principals with the specified display name
    $servicePrincipals = Get-MgServicePrincipal -Filter "displayName eq '$DisplayName'"

    # Check if any service principals were found
    if ($servicePrincipals -ne $null -and $servicePrincipals.Count -gt 0) {
        # Loop through the found service principals and delete them
        foreach ($sp in $servicePrincipals) {
            # Delete the service principal
            Remove-MgServicePrincipal -ServicePrincipalId $sp.Id
            Write-Host "Deleted service principal with ID: $($sp.Id) and Name: $($sp.DisplayName)"
        }
    }
}

function Get-GraphPermissionId {
    param(
        $servicePrincipal,
        [string]$permissionName
    )

    # If we are passed the service principal we use it directly, otherwise we find it from the display name (which might not be unique)
    if ($servicePrincipal) {
        $sp = $servicePrincipal
    }
    else {
        $sp = Get-MgServicePrincipal -Filter "DisplayName eq '$applicationDisplayName'"
    }

    $permission = $sp.AppRoles | Where-Object { $_.Value -eq $permissionName -and $_.AllowedMemberTypes -contains "Application" }
    if ($null -eq $permission) {
        $permission = $sp.Oauth2PermissionScopes | Where-Object { $_.Value -eq $permissionName }
    }
    return $permission.Id
}


# Define the necessary variables
## Heineken
$clientId = "f95461df-460f-45e5-a521-0c181e4ca48f"
$clientSecret = "{clientsecret1}"
$tenantId = "66e853de-ece3-44dd-9d66-ee6bdf4159d4"
$ownerId = "61e52d73-b984-4c84-9861-51b1be625171" # "ADMMOREIR23@heiway.net"

## Microsoft
# $clientId = "23114183-b5a8-4cf5-888b-802e09e3759a"
# $clientSecret = "{clientsecret2}"
# $tenantId = "4f9c4922-48df-47a5-bc62-bcb789e41b7b"
# $ownerId = "ab05cca3-00be-4302-8fc2-c1e5456b3e30" #


$SecuredPasswordPassword = ConvertTo-SecureString `
    -String $clientSecret -AsPlainText -Force

$ClientSecretCredential = New-Object `
    -TypeName System.Management.Automation.PSCredential `
    -ArgumentList $clientId, $SecuredPasswordPassword

Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential

Write-Output "User ID: $($user.Id)"

# Define application properties
$oauthBackendAppDisplayName = "HEI DI API ProductSample"

Remove-AppRegistrationsByName($oauthBackendAppDisplayName)



# Create the new application registration
$oauthBackendApp = New-MgApplication -DisplayName $oauthBackendAppDisplayName `
    -Web `
@{ `
                                                
} `
    -Api `
@{ `
        RequestedAccessTokenVersion = 2 `
                                                
} `
    -SignInAudience AzureADMyOrg

# Output the details of the newly created application
Write-Output "Application ID: $($oauthBackendApp.AppId)"
Write-Output "Application Display Name: $($oauthBackendApp.DisplayName)"

$oauthBackendAppId = $oauthBackendApp.AppId
$oauthBackendAppObjectId = $oauthBackendApp.Id


$serviceIdentifierUri = 'api://' + $oauthBackendAppId
Update-MgApplication -ApplicationId $oauthBackendAppObjectId -IdentifierUris @($serviceIdentifierUri)

# create the service principal of the newly created application     
$serviceServicePrincipal = New-MgServicePrincipal -AppId $oauthBackendAppId -Tags { WindowsAzureActiveDirectoryIntegratedApp }


New-MgApplicationOwnerByRef -ApplicationId $oauthBackendAppObjectId  -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$ownerId}" }
Write-Host "'$($ownerId)' added as an application owner to app '$($serviceServicePrincipal.DisplayName)'"


$roleName1 = "API.ReadWrite.All"
$appRoles = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphAppRole]
$newRole = CreateAppRole -types "Application" -name $roleName1 -description "e.g. Allows the app to read the signed-in user's files."
$appRoles.Add($newRole)
$roleName2 = "API.Read.All"
$newRole = CreateAppRole -types "Application" -name $roleName2 -description "e.g. Allows the app to read the signed-in user's files."
$appRoles.Add($newRole)
Update-MgApplication -ApplicationId $oauthBackendAppObjectId -AppRoles $appRoles

Write-Output "App Roles added: $($appRoles.Count)"

$scopes = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphPermissionScope]
$scope = CreateScope -value API.Read  `
    -userConsentDisplayName "API.Read"  `
    -userConsentDescription "eg. Allows the app to read your files."  `
    -adminConsentDisplayName "API.Read"  `
    -adminConsentDescription "e.g. Allows the app to read the signed-in user's files." `
    -consentType "User" `
        
            
$scopes.Add($scope)
$scope = CreateScope -value API.ReadWrite  `
    -userConsentDisplayName "API.ReadWrite"  `
    -userConsentDescription "eg. Allows the app to read your files."  `
    -adminConsentDisplayName "API.ReadWrite"  `
    -adminConsentDescription "e.g. Allows the app to read the signed-in user's files." `
    -consentType "User" `
        
            
$scopes.Add($scope)
    
# add/update scopes
Update-MgApplication -ApplicationId $oauthBackendAppObjectId -Api @{Oauth2PermissionScopes = @($scopes) }
Write-Host "Done Adding Roles."


$oauthClientAppDisplayName = "HEI DI API ClientSample"
Remove-AppRegistrationsByName($oauthClientAppDisplayName)

# Create the new application registration
$oauthClientApp = New-MgApplication -DisplayName $oauthClientAppDisplayName `
    -Web `
@{ `
    RedirectUris = @("https://api-portal.sandbox.az.heiway.com/signin-oauth/code/callback/oauthclientcredentials","https://api-portal.sandbox.az.heiway.com/signin-oauth/implicit/callback" ) `
} `
    -Api `
@{ `
        RequestedAccessTokenVersion = 2 `
                                                
} `
    -SignInAudience AzureADMyOrg


# Output the details of the newly created application
Write-Output "Client Application ID: $($oauthClientApp.AppId)"
Write-Output "Client Application Display Name: $($oauthClientApp.DisplayName)"

$oauthClientAppObjectId = $oauthClientApp.Id
$oauthClientAppId = $oauthClientApp.AppId

# create the service principal of the newly created application     
$clientServicePrincipal = New-MgServicePrincipal -AppId $oauthClientAppId -Tags { WindowsAzureActiveDirectoryIntegratedApp }

Write-Output "Client Service Principal ID: $($clientServicePrincipal.Id)"

New-MgApplicationOwnerByRef -ApplicationId $oauthClientAppObjectId  -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$ownerId}" }
Write-Host "'$($ownerId)' added as an application owner to app '$($clientServicePrincipal.DisplayName)'"

# Get a 6 months application key for the client Application
# $fromDate = [DateTime]::Now;
# $key = CreateAppKey -fromDate $fromDate -durationInMonths 6
$secret = Add-MgApplicationPassword -ApplicationId $oauthClientAppObjectId
$clientAppKey = $secret.SecretText
# Output the secret value
Write-Output "Client Secret Value: $clientAppKey"

$requiredResourcesAccess = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess]

# Add Required Resources Access (from 'client' to 'service')
Write-Host "Getting access from 'client' to 'service'"
$requiredPermission = GetRequiredPermissions -applicationDisplayName $oauthBackendAppDisplayName -requiredApplicationPermissions "$roleName1|$roleName2"
$requiredResourcesAccess.Add($requiredPermission)
# $requiredPermission = GetRequiredPermissions -applicationDisplayName $oauthBackendAppDisplayName -requiredApplicationPermissions $roleName2
# $requiredResourcesAccess.Add($requiredPermission)
$requiredPermission = GetRequiredPermissions -applicationDisplayName "Microsoft Graph" -requiredApplicationPermissions "User.Read.All"
$requiredResourcesAccess.Add($requiredPermission)
Write-Host "Added 'service' to the RRA list."

Update-MgApplication -ApplicationId $oauthClientAppObjectId -RequiredResourceAccess $requiredResourcesAccess
Write-Host "Granted permissions."


# Add Required Resources Access (from 'client' to 'service')
Write-Host "Getting access from 'client' to 'service'"
$requiredResourcesAccess = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess]
$requiredPermission = GetRequiredPermissions -applicationDisplayName $oauthBackendAppDisplayName -requiredDelegatedPermissions "API.Read|API.ReadWrite"

$requiredResourcesAccess.Add($requiredPermission)
Write-Host "Added 'service' to the RRA list."
# Useful for RRA additions troubleshooting
# $requiredResourcesAccess.Count
# $requiredResourcesAccess
    
Update-MgApplication -ApplicationId $oauthClientAppObjectId -RequiredResourceAccess $requiredResourcesAccess
Write-Host "Granted permissions."


# $oauthClientServicePrincipal = Get-MgServicePrincipal -Filter "DisplayName eq '$oauthClientAppDisplayName'"
# $oauthBackendServicePrincipal = Get-MgServicePrincipal -Filter "DisplayName eq '$oauthBackendAppDisplayName'"

# $scope = Get-GraphPermissionId -servicePrincipal $oauthBackendServicePrincipal -permissionName "API.Read"

# $oauth2PermissionGrant = @{
#     ClientId     = $oauthClientServicePrincipal.Id
#     ConsentType  = "AllPrincipals"
#     ResourceId   = $oauthBackendServicePrincipal.Id
#     Scope        = $scope
# }

# New-MgOauth2PermissionGrant -BodyParameter $oauth2PermissionGrant
# Write-Host "OAuth2 permission grant created for permission: $oauth2PermissionGrant"
    

# Update-MgApplication -ApplicationId $oauthClientAppObjectId -RequiredResourceAccess $requiredResourcesAccess
# Write-Host "Granted permissions."

# wait 5 seconds
Start-Sleep -Seconds 10

Write-Output curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=$clientAppKey&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=$clientAppKey&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

$encodedApiUrl = [System.Web.HttpUtility]::UrlEncode($serviceIdentifierUri + "/.default")

Write-Output "Encoded API URL: $encodedApiUrl"

Write-Output curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=$encodedApiUrl&client_secret=$clientAppKey&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=$encodedApiUrl&client_secret=$clientAppKey&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"


# Wait for user "Enter"
Write-Output "Press Enter to continue before we delete the App..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Remove-AppRegistrationsByName -DisplayName $oauthBackendAppDisplayName
Remove-AppRegistrationsByName -DisplayName $oauthClientAppDisplayName

Write-Output "Applications deleted."