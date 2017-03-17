<#
.SYNOPSIS
This script will deploy the ATA Gateway to domain controllers or standalone ATA Gateway servers.

.DESCRIPTION
ATA Gateway servers must be enabled for PowerShell remoting (see Enable-PSRemoting)
The script will prompt for credentials.  These credentials require read, write and execute privileges on the gateway servers (usually a DADM).

The script's userName and userPwd are the local account created on the ATA Server that is a member of Microsoft Advanced Threat Analytics Administrator group. 
Ensure that this low privileged account is used and consider changing the password afterward, as the script transmits this in the clear to the servers.

The script will launch a job for each server:
copy Microsoft ATA Gateway Setup.zip file 
extract Microsoft ATA Gateway Setup.zip file 
run the Microsoft ATA Gateway Setup.exe file with /q (quiet) parameter
    Prevents restart (/norestart).  If that is desired remove the /norestart parameter to the command line below

Assumes: 
User name and password provided are a valid user in the local ATA Center Microsoft Advanced Threat Analytics Administrators group.
Input and output files have valid locations.
Active Directory module has been installed
ATA prerequisites are installed on target server.

.PARAMETER zipMediaName 
Mandatory: Full path and name to the zip file, e.g. "c:\temp\microsoft ata gateway setup.zip"
.PARAMETER userName 
Mandatory: User name with privileges to install gateway
.PARAMETER userPwd 
Mandatory: Password for user
.PARAMETER serverFileName 
Mandatory: File name that has the list of domain controllers/standalone servers to install. 
.PARAMETER destinationRootPath 
Mandatory: File name on destination server where files will be unzipped. Defaults to c$\temp\ - appends to UNC filepath
.PARAMETER completedFile 
Mandatory: File name to store completed server names. Defaults to c:\temp\ATADeployCompleted.csv

.EXAMPLE
./RunLightweightGatewayInstallation.ps1 "c:\temp\ATA Gateway Installation.zip" localUserName localPassword dcList.txt c$\temp c$\temp c:\temp\ATADeployCompleted.csv
.EXAMPLE
./RunLightweightGatewayInstallation.ps1 "c:\temp\ATA Gateway Installation.zip" localUserName localPassword dcList.txt 

 .LINK
 https://github.com/csmithk/ataGatewayDeploy
#>

param(
[Parameter(Mandatory=$true, Position=0, HelpMessage="Source name is the full path and file name for the installation zip file")]
[ValidateNotNullOrEmpty()]
[string] $zipMediaName,
[Parameter(Mandatory=$true, Position=1, HelpMessage="This is the user name that is in the local Microsoft Advanced Threat Analytics Administrators Group")]
[ValidateNotNullOrEmpty()]
[string] $userName,
[Parameter(Mandatory=$true, Position=2, HelpMessage="This is the password for the local user for installation" )]
[ValidateNotNullOrEmpty()]
[string] $userPwd,
[Parameter(Mandatory=$true, Position=3, HelpMessage="Please enter full file name to acquire ATA Gateway servers text file")]
[ValidateNotNullOrEmpty()]
[string] $serverFileName,
[Parameter(HelpMessage="Please enter destination directory for installation media (UNC path,. e.g., c$\temp")]
[ValidateNotNullOrEmpty()]
[string] $destinationRootPath = 'c$\temp',
[string] $completedFile = 'c:\temp\ATADeployCompleted.csv'
)

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

#cleans up completed and failed jobs
function Clean-Jobs(){
    Clean-CompletedJobs
    Clean-FaileddJobs
}

#returns a list of ATA Gateway servers from file
function Get-Servers([Parameter(Mandatory=$true)][string] $serverFileName){
    if($serverFileName -ne $null -or $serverFileName.Length -gt 0){
        Get-Content $serverFileName
    }
}

function GetFileNameFromPath([Parameter(Mandatory=$true)][string] $fullPath){
        $path = $fullPath.Split("\");
        $count = $path.Count

        if($count -gt 0){
            $path[$count-1]
        }
}

#will be run as a job for each server
 function New-ATADeployment {[CmdletBinding()]
    param ([Parameter(Mandatory=$true)] [string] $serverName,
           [Parameter(Mandatory=$true)] [string] $destionationRootPath,
           [Parameter(Mandatory=$true)] [string] $zipMediaName,
           [Parameter(Mandatory=$true)] [string] $userName,
           [Parameter(Mandatory=$true)] [string] $userPwd,
           [Parameter(Mandatory=$true)] [System.Management.Automation.PSCredential] $credential )

    $destinationPath = "\\$serverName\$destinationRootPath"
    Write-Verbose "Destination path = $destinationPath"

    #test the connection with one ping, suppress any error messages
    if(Test-Connection -ComputerName $serverName -Count 1 -Quiet){
        #create path if it doesn't exist
        if(!(Test-Path $destinationPath)){
            New-Item -Path $destinationPath -ItemType Directory -Value $destinationPath -force
        }
        
        Copy-Item -Path "$zipMediaName" -Destination "$destinationPath" -Force
        $fileName = GetFileNameFromPath $zipMediaName

        $destinationFullPath = Join-Path $destinationPath $fileName

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
        $cmdArgs = "/q /norestart NetFrameWorkCommandLineArguments=`"'/q`" ConsoleAccountName=`"$userName`" ConsoleAccountPassword=`"$userPwd`""
    
#here-strings don't like whitespace or tabs
$myScriptBlock = [ScriptBlock]::Create(@"
& '$ataExe' $cmdArgs

"@)

    $s = New-PSSession $serverName -Credential $credential
    Invoke-Command -Session $s -ScriptBlock $myScriptBlock -asJob -ErrorAction Continue -WarningAction Continue
    Remove-PSSession $s                  
    }
 }
  
$maxThreads = 20
$sleepSeconds = 60
$credential = Get-Credential

#remove quotes, if any from source full name
$zipMediaName = $zipMediaName.Replace('"', '')
$zipMediaName = $zipMediaName.Replace("'", '')

#create the completed file to store results
if(!(Test-Path $completedFile)){
    New-Item -Path $completedFile -ItemType File
}

$servers = Get-Servers $serverFileName

foreach($server in $servers){
    Write-Host $server deploying

    #wait until there are no more than $maxThreads running
    $runningcount = @(Get-Job | Where {$_.State -eq "Running"}).Count
    
    while($runningCount -ge $maxThreads){
        Write-Host "Waiting for open thread ... ($maxThreads Maximum) Running job count is $runningCount"
        Start-Sleep -s 60
        CleanUpCompletedJobs
        $runningcount = @(Get-Job | Where {$_.State -eq "Running"}).Count
    }
   
    Clean-CompletedJobs

    New-ATADeployment $server $destinationRootPath $zipMediaName $userName $userPwd $credential

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

