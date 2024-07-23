# https://learn.microsoft.com/en-us/entra/identity-platform/howto-call-a-web-api-with-curl?tabs=dotnet6&pivots=no-api


Function CreateScope( [string] $value, [string] $userConsentDisplayName, [string] $userConsentDescription, [string] $adminConsentDisplayName, [string] $adminConsentDescription, [string] $consentType)
{
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

Function CreateOptionalClaim([string] $name)
{
    <#.Description
    This function creates a new Azure AD optional claims  with default and provided values
    #>  

    $appClaim = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphOptionalClaim
    $appClaim.AdditionalProperties =  New-Object System.Collections.Generic.List[string]
    $appClaim.Source =  $null
    $appClaim.Essential = $false
    $appClaim.Name = $name
    return $appClaim
}

Function CreateAppRole([string] $types, [string] $name, [string] $description)
{
    $appRole = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphAppRole
    $appRole.AllowedMemberTypes = New-Object System.Collections.Generic.List[string]
    $typesArr = $types.Split(',')
    foreach($type in $typesArr)
    {
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
                               $exposedPermissions, [string]$requiredAccesses, [string]$permissionType)
{
    foreach($permission in $requiredAccesses.Trim().Split("|"))
    {
        foreach($exposedPermission in $exposedPermissions)
        {
            if ($exposedPermission.Value -eq $permission)
                {
                $resourceAccess = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess
                $resourceAccess.Type = $permissionType # Scope = Delegated permissions | Role = Application permissions
                $resourceAccess.Id = $exposedPermission.Id # Read directory data
                $requiredAccess.ResourceAccess += $resourceAccess
                }
        }
    }
}

Function GetRequiredPermissions([string] $applicationDisplayName, [string] $requiredDelegatedPermissions, [string]$requiredApplicationPermissions, $servicePrincipal)
{
    # If we are passed the service principal we use it directly, otherwise we find it from the display name (which might not be unique)
    if ($servicePrincipal)
    {
        $sp = $servicePrincipal
    }
    else
    {
        $sp = Get-MgServicePrincipal -Filter "DisplayName eq '$applicationDisplayName'"
    }

    # if $sp is empty - throw an error
    if ($null -eq $sp)
    {
        throw "Service Principal with display name $applicationDisplayName not found"
    }
    else 
    {
        Write-Host "Service Principal found: $($sp.DisplayName)"
    }


    $appid = $sp.AppId
    $requiredAccess = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
    $requiredAccess.ResourceAppId = $appid 
    $requiredAccess.ResourceAccess = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess]

    # $sp.Oauth2Permissions | Select Id,AdminConsentDisplayName,Value: To see the list of all the Delegated permissions for the application:
    if ($requiredDelegatedPermissions)
    {
        AddResourcePermission $requiredAccess -exposedPermissions $sp.Oauth2PermissionScopes -requiredAccesses $requiredDelegatedPermissions -permissionType "Scope"
    }
    
    # $sp.AppRoles | Select Id,AdminConsentDisplayName,Value: To see the list of all the Application permissions for the application
    if ($requiredApplicationPermissions)
    {
        AddResourcePermission $requiredAccess -exposedPermissions $sp.AppRoles -requiredAccesses $requiredApplicationPermissions -permissionType "Role"
    }
    return $requiredAccess
}

function Remove-AppRegistrationsByName {
    param (
        [Parameter(Mandatory=$true)]
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


$serviceIdentifierUri = 'api://'+$oauthBackendAppId
Update-MgApplication -ApplicationId $oauthBackendAppObjectId -IdentifierUris @($serviceIdentifierUri)

# create the service principal of the newly created application     
$serviceServicePrincipal = New-MgServicePrincipal -AppId $oauthBackendAppId -Tags {WindowsAzureActiveDirectoryIntegratedApp}


New-MgApplicationOwnerByRef -ApplicationId $oauthBackendAppObjectId  -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$ownerId}"}
Write-Host "'$($ownerId)' added as an application owner to app '$($serviceServicePrincipal.DisplayName)'"



$optionalClaims = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphOptionalClaims
$optionalClaims.AccessToken = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphOptionalClaim]
$optionalClaims.IdToken = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphOptionalClaim]
$optionalClaims.Saml2Token = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphOptionalClaim]

# Add Optional Claims

$newClaim =  CreateOptionalClaim  -name "idtyp" 
$optionalClaims.AccessToken += ($newClaim)
$newClaim =  CreateOptionalClaim  -name "acct" 
$optionalClaims.AccessToken += ($newClaim)
Update-MgApplication -ApplicationId $oauthBackendAppObjectId -OptionalClaims $optionalClaims

Write-Output "Service Principal ID: $($serviceServicePrincipal.Id)"

$scopeName = "HeinekenAPI.ReadWrite"

$roleName = "HeinekenAPI.ReadWrite.All"

# Publish Application Permissions
$appRoles = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphAppRole]
$newRole = CreateAppRole -types "Application" -name $roleName -description "e.g. Allows the app to read the signed-in user's files."
$appRoles.Add($newRole)
Update-MgApplication -ApplicationId $oauthBackendAppObjectId -AppRoles $appRoles



$scopes = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphPermissionScope]

$scope = CreateScope -value HeinekenAPI.ReadWrite  `
    -userConsentDisplayName $scopeName  `
    -userConsentDescription "Allow ReadWrite access to the APIs of Product $oauthBackendAppDisplayName "  `
    -adminConsentDisplayName $scopeName `
    -adminConsentDescription "e.g. Allow ReadWrite access to the APIs of Product $oauthBackendAppDisplayName" `
    -consentType "User" `
        
$scopes.Add($scope)

Update-MgApplication -ApplicationId $oauthBackendAppObjectId -Api @{Oauth2PermissionScopes = @($scopes)}

Write-Output "Scopes created: $scopes"


$oauthClientAppDisplayName = "HEI DI API ClientSample"
Remove-AppRegistrationsByName($oauthClientAppDisplayName)

# Create the new application registration
$oauthClientApp = New-MgApplication -DisplayName $oauthClientAppDisplayName `
                                                -Web `
                                                @{ `
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
$clientServicePrincipal = New-MgServicePrincipal -AppId $oauthClientAppId -Tags {WindowsAzureActiveDirectoryIntegratedApp}

Write-Output "Client Service Principal ID: $($clientServicePrincipal.Id)"

New-MgApplicationOwnerByRef -ApplicationId $oauthClientAppObjectId  -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$ownerId}"}
Write-Host "'$($ownerId)' added as an application owner to app '$($clientServicePrincipal.DisplayName)'"

$secret = Add-MgApplicationPassword -ApplicationId $oauthClientAppObjectId
# Output the secret value
Write-Output "Client Secret Value: $($secret.SecretText)"


$requiredResourcesAccess = New-Object System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess]

# Add Required Resources Access (from 'client' to 'service')
Write-Host "Getting access from 'client' to 'service'"
$requiredPermission = GetRequiredPermissions -applicationDisplayName $oauthBackendAppDisplayName -requiredDelegatedPermissions $scopeName 

$requiredResourcesAccess.Add($requiredPermission)
Write-Host "Added 'service' to the RRA list."
# Useful for RRA additions troubleshooting
# $requiredResourcesAccess.Count
# $requiredResourcesAccess

Update-MgApplication -ApplicationId $oauthClientAppObjectId -RequiredResourceAccess $requiredResourcesAccess
Write-Host "Granted permissions."


function Remove-AppRegistrationsByName {
    param (
        [Parameter(Mandatory=$true)]
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
    } else {
        Write-Host "No app registrations found with the display name: $DisplayName"
    }
}

# Write-Output curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=$($secret.SecretText)&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
# curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=$($secret.SecretText)&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

$encodedApiUrl = [System.Web.HttpUtility]::UrlEncode($serviceIdentifierUri + "/" + $scopeName + "/.default")

Write-Output "Encoded API URL: $encodedApiUrl"

Write-Output curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=$encodedApiUrl&client_secret=$($secret.SecretText)&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$oauthClientAppId&scope=$encodedApiUrl&client_secret=$($secret.SecretText)&grant_type=client_credentials" "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"


# Wait for user "Enter"
Write-Output "Press Enter to continue before we delete the App..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Remove-AppRegistrationsByName -DisplayName $oauthBackendAppDisplayName
Remove-AppRegistrationsByName -DisplayName $oauthClientAppDisplayName

Write-Output "Applications deleted."