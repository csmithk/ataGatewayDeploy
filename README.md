# Advanced Threat Analytics Lightweight Gateway Deploy
PowerShell script to deploy the Advanced Threat Analytics Lightweight Gateway to domain controllers
PLEASE READ, THIS IS DEPLOYED ON DOMAIN CONTROLOLLERS!
This has been tested in my lab, it is strongly suggested that the user test this in their own environment.

This script will deploy ATA Lightweight Gateway to domain controllers.
If the $dcFileName parameter is provided, the script will obtain the DC names from the file, otherwise it will pull all DCs in the forest.

Domain controllers must be enabled for PowerShell remoting (see Enable-PSRemote)
The script must be run with credentials that allow read, write and execute privileges on the domain controllers (usually a DADM).

The script transmits the local ATA center adminstrator account credentials in the clear.  Ensure that this low privileged account is used and consider changing the password.

The script will launch a job for each DC:
copy Microsoft ATA Gateway Setup.zip file 
extract Microsoft ATA Gateway Setup.zip file 
run the Microsoft ATA Gateway Setup.exe file with /q (quiet) parameter
    Prevents restart (/norestart).  If that is desired, remove the /norestart parameter to the command line below

Assumes: 
User name and password provided are a valid user in the local ATA Center Microsoft Advanced Threat Analytics Administrators group.
Input and output files have valid locations.
Active Directory module has been installed

Parameters:
    
    $sourceFullName - full path and name to the zip file, e.g. "c:\temp\microsoft ata gateway setup.zip"
    $userName - user name with privileges to install gateway
    $userPwd - password for user
    $dcFileName file name that has the list of domain controllers to install.  There is code below that will get all dcs in the forest, it is commented out for now
   
    Defaults:
    
    Parameter $errorFile defaults to c:\temp\ATADeployErrors.csv
    Parameter $completedFile defaults to c:\temp\ATADeployCompleted.csv
    Parameter $destinationRootPath defaults to c$\temp\ - appends to UNC filepath 
