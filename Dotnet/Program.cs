// https://github.com/microsoftgraph/msgraph-sdk-dotnet

using Azure.Identity;
using Microsoft.Graph;
using Microsoft.Graph.Applications.Item.AddPassword;
using Microsoft.Graph.Models;


//  dotnet add package Microsoft.Graph
// dotnet add package Microsoft.Identity.Client

// See https://aka.ms/new-console-template for more information
Console.WriteLine("Hello, World!");

// Microsoft Credentials
var tenantId = "4f9c4922-48df-47a5-bc62-bcb789e41b7b";
var clientId = "23114183-b5a8-4cf5-888b-802e09e3759a";
var clientSecret = "{secret}";

var sampleUserId = "ab05cca3-00be-4302-8fc2-c1e5456b3e30";

var clientSecretCredential = new ClientSecretCredential(
                tenantId, clientId, clientSecret);
var graphClient = new GraphServiceClient(clientSecretCredential);


var oauthBackendAppDisplayName = "HEI DI API ProductSample";

RemoveAppRegistrationsByName(oauthBackendAppDisplayName);

const string APP_ROLE_NAME = "API.ReadWrite";
// Add Role "API.ReadWrite" to the App Registration
var oauthBackendAppRole = new AppRole
{
    AllowedMemberTypes = new List<string> { "Application" },
    DisplayName = APP_ROLE_NAME,
    Id = Guid.NewGuid(),
    Description = "Read and write access to the API",
    Value = APP_ROLE_NAME,
    IsEnabled = true,
};

var oauthBackendApplication = new Application
        {
            DisplayName = oauthBackendAppDisplayName,
            Web = new WebApplication(),
            Api = new ApiApplication
            {
                RequestedAccessTokenVersion = 2
            },
            SignInAudience = "AzureADMyOrg",
            AppRoles = new List<AppRole> { oauthBackendAppRole },
        };

oauthBackendApplication = await graphClient.Applications.PostAsync(oauthBackendApplication);

Console.WriteLine($"Created app registration with Object ID: {oauthBackendApplication.Id} and App Id: {oauthBackendApplication.AppId}");

var oauthBackendServiceIdentifierUri = $"api://{oauthBackendApplication.AppId}";
oauthBackendApplication.IdentifierUris = new List<string> { oauthBackendServiceIdentifierUri };

Console.WriteLine($"Added service identifier URI: {oauthBackendServiceIdentifierUri}");
await graphClient.Applications[oauthBackendApplication.Id].PatchAsync(oauthBackendApplication);

var oauthBackendServicePrincipal = new ServicePrincipal
{
    AppId = oauthBackendApplication.AppId,
    DisplayName = oauthBackendAppDisplayName,
    Tags = [$"{sampleUserId}"],
    // Setting the app role assignment required to true to ensure that the app role assignment is required for Token generation
    // Clients are not able to generate a token without the app role assignment
    AppRoleAssignmentRequired = true,
};

oauthBackendServicePrincipal = await graphClient.ServicePrincipals.PostAsync(oauthBackendServicePrincipal);

Console.WriteLine($"Created service principal with Object ID: {oauthBackendServicePrincipal.Id}");

var oauthClientAppDisplayName = "HEI DI API ClientSample";
RemoveAppRegistrationsByName(oauthClientAppDisplayName);

var appRoleToGrantAccess = oauthBackendApplication.AppRoles.FirstOrDefault(role => role.DisplayName == APP_ROLE_NAME);

var requiredResourceAccess = new List<RequiredResourceAccess>
        {
            new RequiredResourceAccess
            {
                ResourceAppId = oauthBackendApplication.AppId,
                ResourceAccess = new List<ResourceAccess>
                {
                    new ResourceAccess
                    {
                        Id = appRoleToGrantAccess.Id,
                        Type = "Role"
                    }
                }
            }
        };

var oauthClientApplication = new Application
{
    DisplayName = oauthClientAppDisplayName,
    Web = new WebApplication(),
    Api = new ApiApplication
    {
        RequestedAccessTokenVersion = 2
    },
    SignInAudience = "AzureADMyOrg",
    RequiredResourceAccess = requiredResourceAccess,
};

oauthClientApplication = await graphClient.Applications.PostAsync(oauthClientApplication);

Console.WriteLine($"Created app registration with Object ID: {oauthClientApplication.Id} and App Id: {oauthClientApplication.AppId}");

// Create a password credential for the client application
var passwordCredentialRequest = new AddPasswordPostRequestBody
{
    PasswordCredential = new PasswordCredential
    {
        DisplayName = "Client Secret",
        EndDateTime = DateTime.UtcNow.AddYears(3),
        StartDateTime = DateTime.UtcNow,
    }
};

var passwordCredentialResponse = await graphClient.Applications[oauthClientApplication.Id].AddPassword.PostAsync(passwordCredentialRequest);
var passwordSecretText = passwordCredentialResponse.SecretText;
Console.WriteLine($"Created password credential with Secret Text: {passwordSecretText}");


Console.WriteLine($"Granting permissions to the client application {oauthClientApplication.Id} to access the backend application {oauthBackendApplication.Id}");
// Create a service principal for the client application
var oauthClientServicePrincipal = new ServicePrincipal
{
    AppId = oauthClientApplication.AppId,
    DisplayName = oauthClientAppDisplayName,
    Tags = [$"{sampleUserId}"]
};

oauthClientServicePrincipal = await graphClient.ServicePrincipals.PostAsync(oauthClientServicePrincipal);

// Performing "Grant Admin Consent" for the client application
var appRoleAssignment =
        new AppRoleAssignment
        {
            PrincipalId = Guid.Parse(oauthClientServicePrincipal.Id) ,
            ResourceId = Guid.Parse(oauthBackendServicePrincipal.Id),
            AppRoleId = appRoleToGrantAccess.Id
        };

graphClient.ServicePrincipals[oauthClientServicePrincipal.Id].AppRoleAssignments.PostAsync(appRoleAssignment).Wait();

// sleep for 10 seconds
System.Threading.Thread.Sleep(10000);

oauthClientApplication = await graphClient.Applications[oauthClientApplication.Id].GetAsync();
Console.WriteLine($"Created service principal with Object ID: {oauthClientServicePrincipal.Id}");

foreach (var key in oauthClientApplication.PasswordCredentials)
{
    Console.WriteLine($"Password Credential: {key.KeyId} - {key.DisplayName} - {key.SecretText}");
}

Console.WriteLine("Press any key to retrieve the Token...");
Console.ReadLine();

string tokenEndpoint = $"https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token";

using (var httpClient = new HttpClient())
{
    var request = new HttpRequestMessage(HttpMethod.Post, tokenEndpoint);

    var content = new FormUrlEncodedContent(new[]
    {
        new KeyValuePair<string, string>("grant_type", "client_credentials"),
        new KeyValuePair<string, string>("client_id", oauthClientApplication.AppId),
        new KeyValuePair<string, string>("client_secret", passwordSecretText),
        new KeyValuePair<string, string>("scope", oauthBackendServiceIdentifierUri + "/.default"),
    });

    request.Content = content;

    var response = await httpClient.SendAsync(request);
    var responseContent = await response.Content.ReadAsStringAsync();
    Console.WriteLine("Token response:");
    Console.WriteLine(responseContent);
}



// wait user input
Console.WriteLine("Press any key to delete the apps...");
Console.ReadLine();

RemoveAppRegistrationsByName(oauthBackendAppDisplayName);
RemoveAppRegistrationsByName(oauthClientAppDisplayName);


void RemoveAppRegistrationsByName(string displayName)
{
    Console.WriteLine($"Removing app registrations with display name: {displayName}");

    // Search for app registrations with the specified display name
    var appRegistrationsResponse = graphClient.Applications
        .GetAsync( x => x.QueryParameters.Filter = $"displayName eq '{displayName}'").Result;

    if (appRegistrationsResponse != null && appRegistrationsResponse.Value != null){
        appRegistrationsResponse.Value.ForEach( app => {
            Console.WriteLine($"Deleted app registration with ID: {app.Id} and Name: {app.DisplayName}");
            graphClient.Applications[app.Id].DeleteAsync().Wait();
        });
    }
    
    var servicePrincipalsResponse = graphClient.ServicePrincipals
        .GetAsync( x => x.QueryParameters.Filter = $"displayName eq '{displayName}'").Result;

    if (servicePrincipalsResponse != null && servicePrincipalsResponse.Value != null){
        servicePrincipalsResponse.Value.ForEach( sp => {
            Console.WriteLine($"Deleted service principal with ID: {sp.Id} and Name: {sp.DisplayName}");
            graphClient.ServicePrincipals[sp.Id].DeleteAsync().Wait();
        });
    }
}