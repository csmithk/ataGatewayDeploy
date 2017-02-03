<#
PLEASE READ, THIS IS DEPLOYED ON DOMAIN CONTROLLERS

This script will deploy ATA Lightweight Gateway to domain controllers.

Domain controllers must be enabled for PowerShell remoting (see Enable-PSRemote)
The script must be run with credentials that allow read, write and execute privileges on the domain controllers (usually a DADM).

The script transmits the local ATA center adminstrator account credentials in the clear.  Ensure that this low privileged account is used and consider changing the password.

The script will launch a job for each DC:
copy Microsoft ATA Gateway Setup.zip file 
extract Microsoft ATA Gateway Setup.zip file 
run the Microsoft ATA Gateway Setup.exe file with /q (quiet) parameter
    Prevents restart (/norestart).  If that is desired remove the /norestart parameter to the command line below

Assumes: 
User name and password provided are a valid user in the local ATA Center Microsoft Advanced Threat Analytics Administrators group.
Input and output files have valid locations.
Active Directory module has been installed

Parameters:
    Mandatory:
    $sourceFullName - full path and name to the zip file, e.g. "c:\temp\microsoft ata gateway setup.zip"
    $userName - user name with privileges to install gateway
    $userPwd - password for user
    $dcFileName file name that has the list of domain controllers to install.  There is code below that will get all dcs in the forest, it is commented out for now
   
    Defaults:
    
    Parameter $errorFile defaults to c:\temp\ATADeployErrors.csv
    Parameter $completedFile defaults to c:\temp\ATADeployCompleted.csv
    Parameter $destinationRootPath defaults to c$\temp\ - appends to UNC filepath
#>


param(
[Parameter(Mandatory=$true, Position=0, HelpMessage="Source name is the full path and file name for the installation zip file")]
[ValidateNotNullOrEmpty()]
[string] $sourceFullName,
[Parameter(Mandatory=$true, Position=1, HelpMessage="This is the user name that is in the local Microsoft Advanced Threat Analytics Administrators Group")]
[ValidateNotNullOrEmpty()]
[string] $userName,
[Parameter(Mandatory=$true, Position=2, HelpMessage="This is the password for the local user for installation" )]
[ValidateNotNullOrEmpty()]
[string] $userPwd,
[Parameter(HelpMessage="Please enter full file name to acquire domain controllers from file, or leave blank to get all DCs in the forest")]
[ValidateNotNullOrEmpty()]
[string] $dcFileName = $null,
[string] $errorFile = 'c:\temp\ATADeployErrors.csv',
[string] $completedFile = 'c:\temp\ATADeployCompleted.csv',
[string] $destinationRootPath = 'c$\temp'

)

#remove quotes, if any from source full name
$sourceFullName = $sourceFullName.Replace('"', '')
$sourceFullName = $sourceFullName.Replace("'", '')

#write failed jobs to file and remove jobs
function Clean-FaileddJobs(){
    $jobsFailed = Get-Job | Where {$_.State -eq "Failed"}
    if($jobsFailed.count -gt 0){
        foreach($job in $jobsFailed){
            $result = "$($job.Name),$($job.State)"
            foreach($child in $job.ChildJobs){
                $result += ",$($child.JobStateInfo.Reason.ToString())"
            }
            Add-Content $completedFile $result
        }
    }
                
    Write-Host Cleaning up $JobsFailed.count Failed
    $JobsFailed | Remove-Job
}

#write completed jobs to file and remove jobs
function Clean-CompletedJobs(){
    $jobsCompleted = Get-Job | Where {$_.State -eq "Completed"}
    if($jobsCompleted.count -gt 0){
        foreach($job in $jobsCompleted){
            $result = "$($job.Name),$($job.State)"
            Add-Content $completedFile $result
        }
    }          
    Write-Host Cleaning up $JobsCompleted.count completed
    $JobsCompleted | Remove-Job
}

function Clean-Jobs(){
    Clean-CompletedJobs
    Clean-FaileddJobs
}

<#
#Get all the domain controller names in the forest

function Get-ActiveDirectoryDomainControllers(){
$forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
$domainControllers = @()

$forest | ForEach-Object {$_.Domains} |
    ForEach-Object {$_.DomainControllers} | 
        ForEach-Object {
            $domainControllers += $_.Name
        }
    $domainControllers
}

#>

#if $dcFileName is provided, returns a list of domain controllers from filet
function Get-DomainControllers(){
    if($dcFileName -ne $null -or $dcFileName.Length -gt 0){
        Get-Content $dcFileName
    }
}

#will be run as a job for each domain controller
 $Scriptblock = {
    param ([string] $dcName,
            [string] $destionationRootPath,
            [string] $sourceFullName,
            [string] $userName,
            [string] $userPwd )

    function GetFileNameFromPath([string] $fullPath){
        $path = $fullPath.Split("\");
        $count = $path.Count

        if($count -gt 0){
            $path[$count-1]
        }
    }

    $VerbosePreference = 'Continue'
    $destinationPath = "\\$dcName\$destinationRootPath"
    Write-Verbose "Destination path = $destinationPath"

    #test the connection with one ping, suppress any error messages
    if(Test-Connection -ComputerName $dcName -Count 1 -Quiet){
        #create path if it doesn't exist
        if(!(Test-Path $destinationPath)){
            New-Item -Path $destinationPath -ItemType Directory -Value $destinationPath -force
        }
        
        Copy-Item -Path "$sourceFullName" -Destination "$destinationPath" -Force
        $fileName = GetFileNameFromPath $sourceFullName

        $destinationFullPath = Join-Path $destinationPath$fileName

        $shell = New-Object -ComObject shell.application

        $zip = $shell.NameSpace("$destinationFullPath”)
        foreach($item in $zip.Items()){
            $zipFileName = GetfileNameFromPath $item.Path
            $zipFullPath = Join-Path $destinationPath $zipFileName
            #if the file already exists, delete and replace
            if(Test-Path $zipFullPath){
                Remove-Item $zipFullPath
            }

            $shell.NameSpace("$destinationPath").CopyHere($item)
        } 
        
        $ataExe = $fileName.Replace("zip", "exe") 
        $ataExe = Join-Path $destionationRootPath $ataExe
        $ataExe = $ataExe.Replace('$', ':')
        $cmdArgs = "/q /norestart NetFrameWorkCommandLineArguments=`"/q`" Console-AccountName=`"$userName`" ConsoleAccountPassword=`"$userPwd`""

#here-strings don't like whitespace or tabs
$myScriptBlock = [ScriptBlock]::Create(@"
& cmd '$ataExe' $cmdArgs

"@)
    Write-Verbose "My script block: $myScriptBlock"

    $s = New-PSSession $dcName

    Invoke-Command -Session $s -ScriptBlock $myScriptBlock -asJob -ErrorAction Continue -WarningAction Continue
    Remove-PSSession $s
                    
    }
 }
  
$maxThreads = 20
$sleepSeconds = 60

#create the completed file to store results
if(!(Test-Path $completedFile)){
    New-Item -Path $completedFile -ItemType File
}

$domainControllers = Get-DomainControllers

Write-Host $domainControllers

foreach($dc in $domainControllers){
    Write-Host $dc deploying

    #wait until there are no more than $maxThreads running
    $runningcount = @(Get-Job | Where {$_.State -eq "Running"}).Count
    
    while($runningCount -ge $maxThreads){
        Write-Host "Waiting for open thread ... ($maxThreads Maximum) Running job count is $runningCount"
        Start-Sleep -s 60
        CleanUpCompletedJobs
        $runningcount = @(Get-Job | Where {$_.State -eq "Running"}).Count
    }
   
    Clean-CompletedJobs

    $job = Start-Job -Name $dc -ScriptBlock $ScriptBlock -ArgumentList $dc, $destinationPath, $sourceFullName $userName $userPwd
    Write-Host Started job $job.Name
    Write-Host "Running job count is $runningCount"
    $error.clear()

}

#wait for all the jobs to finish running
while((Get-Job | Where {$_.State -eq "Running"}).count -gt 0){
    Write-Host Jobs still running
    Get-Job | Where {$_.State -eq "running"}
    Write-Host Sleeping for $sleepSeconds seconds
    Start-Sleep -s $sleepSeconds
}

Clean-Jobs

$currentTime = Get-Date

Write-Host "Finished script $currentTime"
