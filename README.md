# Veeam/PernixData Cache Control

This script enables integration between Veeam Backup & Replication and PernixData FVP to allow FVP write back enabled VMs associated with the Veeam backup or replication job to be transitioned to write through before the job runs. Conversely, it also will transition the VMs back to the previous write back state with the correct number of peers.

## Prerequisites 
*The following must be installed on your Veeam Backup & Replication server before continuing:*

* VMware PowerCLI
* Veeam PowerShell cmdlets
* PernixData PowerShell cmdlets

## Usage

#### This version of the script is to be used with FVP Enterprise.

* Download the zip file or clone this repository to the Veeam backup server.
* Extract both files: VeeamPrnxCacheControl.ps1 and SetPassword.ps1 to c:\veeamprnx or the directory of your choice.
* Open a Powershell command prompt on the Veeam server, cd to c:\veeamprnx and run .\SetPassword.ps1 and enter the password for the username that is used to connect to the PernixData Management Server. A new file will be created: fvp_enc_pass.txt. This contains an encrypted copy of the password and will be used by the script to run.
* Edit VeeamPrnxCacheControl.ps1 to include the username for connecting to vCenter and the PernixData Management Server as well as the IP address/FQDN of each server.
* Files will be stored in c:\veeamprnx. Change this if necessary.
* Edit each Veeam Backup & Replication job to use VeeamPrnxCacheControl.ps1 for pre and post job processing. To do this, edit the job then select Storage, Advanced, then Advanced again.
* In the pre-job script field, enter C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command C:\veeamprnx\VeeamPrnxCacheControl.ps1 -Mode WriteThrough
* In the post-job script field, enter C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -Command C:\veeamprnx\VeeamPrnxCacheControl.ps1 -Mode WriteBack