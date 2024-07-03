# CreateEntraIdAppOnBehalf

Objective here is to be able to create Entra ID App Registrations "On Behalf" of another App Registration with "Application.ReadWrite.OwnedBy"

1) Create an App Registration and grant access "Application.ReadWrite.OwnedBy"
 - This will enable the App Registration to create and manage other Applications

2) Update the variables on createAppOnBehalfOf.ps1 and execute the script
 - Script will request the Token from the original App Registration
 -  Create and Delete a new App on behalf of the original App Registration