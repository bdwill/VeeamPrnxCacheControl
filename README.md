# Veeam/PernixData Cache Control

This script enables integration between Veeam Backup & Replication and PernixData FVP to allow FVP write back enabled VMs associated with the Veeam backup or replication job to be transitioned to write through before the job runs. Conversely, it also will transition the VMs back to the previous write back state with the correct number of peers.

## Prerequisites 
*The following must be installed on your Veeam Backup & Replication server before continuing:*

* VMware PowerCLI
* Veeam PowerShell cmdlets
* PernixData PowerShell cmdlets

## Usage

#### This version of the script is to be used with FVP Enterprise.

* Download zip file or clone this repository to your machine.
* Open a Powershell command prompt on the Veeam server and execute: Read-Host -AsSecureString -prompt "Enter password" | ConvertFrom-SecureString | Out-File fvp_enc_pass.txt 
* Enter the username and password for the service account or username that is being used for FVP management server.
* Edit VeeamPrnxCacheControl.ps1 to include the username for connecting to vCenter and the PernixData management server as well as the IP address/FQDN of each server.
* Temporary files will be stored in c:\temp. Change this if necessary.
* Edit each Veeam Backup & Replication job, select Storage, Advanced, then Advanced again.
* In the pre-job script field, enter C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command C:\<FOLDER_WHERE_YOU_STORED_SCRIPT>\VeeamPrnxCacheControl.ps1 -JobName 'Your Veeam Job Name Here' -Mode WriteThrough
* In the post-job script field, enter C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command C:\<FOLDER_WHERE_YOU_STORED_SCRIPT>\VeeamPrnxCacheControl.ps1 -JobName 'Your Veeam Job Name Here' -Mode WriteBack