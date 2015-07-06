Function WriteLog
{
   Param ([string]$logstring)
   $logstring = "$(Get-Date -format s) - " + $logstring
   $logstring | out-file -Filepath $logfile -append
}

Param ( 
    [Parameter(Mandatory=$true)][string]$JobName,
    [Parameter(Mandatory=$true)][ValidateSet("WriteBack", "WriteThrough")][string]$Mode
)
cls

Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue

# Initialize variables
$logfilepath = "C:\temp"
$logfile = $logfilepath + "\fvp_$(get-date -f yyyy_MM_dd_HH_mm_ss).log"
$passwordfile = $logfilepath + "\fvp_enc_pass.txt"
$fvp_server = "localhost"
$vcenter = "vcenter.domain.local"
$username = "domain\user"



WriteLog "Retrieving encrypted password from file $passwordfile"
Try { 
        $enc_pass = Get-Content $passwordfile | ConvertTo-SecureString
    }
Catch { 
        WriteLog "Error retrieving encrypted password"
        Exit 1
    }

Try { 
        $credential = New-Object System.Management.Automation.PsCredential($username, $enc_pass)
    }
Catch {
        WriteLog "Error creating credential object"
        Exit 1
    }

# Verify the job exists
$job = Get-VBRJob -Name $JobName
WriteLog "Verifying that the job exists"
if (!$job) {
    WriteLog "Backup job $jobname not found!"
    Exit 2
}

$SettingsFile = $logfilepath + "\Job."+$job.TargetFile+".Settings.csv"

# Running some initial tests
if ($Mode -eq "WriteThrough") {
    if (Test-Path $SettingsFile) {
        WriteLog "Remove $SettingsFile manually and re-run the job"
        Exit 2
    } else {
        WriteLog "Created peer settings file: $SettingsFile"
        $SettingsFileHandle = New-Item $SettingsFile -Type File
    }
} elseif ($Mode -eq "WriteBack") {
    if (Test-Path $SettingsFile) {
        WriteLog "Transitioning VMs to write back"
        $SettingsFileHandle = Get-Content $SettingsFile
    } else {
        Writelog "Nothing to change, normal exit"
        Exit 0
    }
}

# It's showtime!

if ($Mode -eq "WriteThrough") {
    WriteLog "Connecting to VMware vCenter Server"
    $vmware = Connect-VIServer -Server $vcenter -credential $credential
    writelog "Connected to VMware vCenter Server"

    WriteLog "Getting objects in backup job"
    $objects = $job.GetObjectsInJob() | ?{$_.Type -eq "Include"}
    $excludes = $job.GetObjectsInJob() | ?{$_.Type -eq "Exclude"}

    # Initiate empty array for VMs to exclude
    [System.Collections.ArrayList]$es = @()

    WriteLog "Building list of excluded job objects."
    # Skip if no exclusions were found.
    if ($excludes -gt 0) {

    foreach ($e in $excludes) {
        $e.Name

        # If the object added to the job is not a VM, find the contained VMs
        $view = Get-View -ViObject $e.Name | Get-VIObjectByVIView
        if ($view.GetType().Name -ne "VirtualMachineImpl") {
            foreach ($vm in ($view | Get-VM)) {
                $i = $es.Add($vm.Name)
            }
        } else {
            $i = $es.Add($view.Name)
        }

    }
}

WriteLog "Building list of included objects"
# Initiate empty array for VMs to include
[System.Collections.ArrayList]$is = @()

foreach ($o in $objects) {
    $o.Name 

    # If the object added to the job is not a VM, find the contained VMs
    $view = Get-View -ViObject $o.Name | Get-VIObjectByVIView
    if ($view.GetType().Name -ne "VirtualMachineImpl") {
        foreach ($vm in ($view | Get-VM)) {
            if ($es -notcontains $vm.Name) {
                $i = $is.Add($vm.Name)
            }
        }
    } else {
        $i = $is.Add($o.Name)
    }
}

WriteLog "Connecting to PernixData Management Server"

Try {
        import-module prnxcli -ea Stop
        $prnx = Connect-PrnxServer -credentials $credential -ea Stop > $null
    }
Catch {
        WriteLog "Error connecting to FVP Management Server: $($_.Exception.Message)"
        exit 1
    }

WriteLog "Connected to PernixData Management Server"
writelog "Getting list of included, powered on VMs with PernixData write-back mode enabled"
$prnxVMs = Get-PrnxVM | Where {($_.powerState -eq "poweredOn") -and ($_.effectivePolicy -eq "7")} | Where { $is -contains $_.Name }

foreach ($vm in $prnxVMs) {
    if ($vm.numWbExternalPeers -eq $null) {
        $ext_peers = 0
    } else {
        $ext_peers = $vm.numWbExternalPeers
    }

    $VMName = $vm.Name
    $VMWBPeers = $vm.NumWBPeers
    $VMWBExternalPeers = $ext_peers

    $WriteBackPeerInfo = @($VMName,$VMWBPeers,$VMWBExternalPeers)
    $WriteBackPeerInfo -join ',' | Out-File $SettingsFile -Append

    writelog "Transitioning $VMName (peers: $VMWBPeers, external: $VMWBExternalPeers) into write through"
        
    Try { 
        $CacheMode = Set-PrnxAccelerationPolicy -Name $VMName -WriteThrough -ea Stop
    }
    Catch {
        Write-Error "Failed to transition $VMName : $($_.Exception.Message)"
        Exit 2
    }
}

} elseif ($Mode -eq "WriteBack") {

writelog "Connecting to PernixData FVP Management Server"

Try {
        import-module prnxcli -ea Stop
        $prnx = Connect-PrnxServer -NameOrIPAddress localhost -UserName root -Password vmware -ea Stop
    }
Catch {
        WriteLog "Error connecting to FVP Management Server: $($_.Exception.Message)"
        exit 1
    }

WriteLog "Connected to PernixData Management Server"

foreach ($vm in $SettingsFileHandle) {
    $VMName            = $vm.split(",")[0]
    $VMWBPeers         = $vm.split(",")[1]
    $VMWBExternalPeers = $vm.split(",")[2]

    writelog "Transitioning $VMName into writeback mode with $VMWBPeers peers and $VMWBExternalPeers external peers"
        
    Try { 
        $CacheMode = Set-PrnxAccelerationPolicy -Name $VMName -WriteBack -NumWBPeers $VMWBPeers -NumWBExternalPeers $VMWBExternalPeers -ea Stop
    }
    Catch {
        WriteLog "Failed to transition $VMName : $($_.Exception.Message)"
        Exit 2
    }
}

Remove-Item -Path $SettingsFile
}

Disconnect-PrnxServer -Connection $prnx > $null