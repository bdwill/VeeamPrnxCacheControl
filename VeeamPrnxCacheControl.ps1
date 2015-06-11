# Parameter to check for not being present to determine if customer is running ent or std?

Param ( 
    [Parameter(Mandatory=$true)][string]$JobName,
    [Parameter(Mandatory=$true)][ValidateSet("WriteBack", "WriteThrough")][string]$Mode
)
cls

function WriteLog
{
   Param ([string]$logstring)
   $logstring = "$(Get-Date -format s) - " + $logstring
   $logstring | out-file -Filepath $logfile -append
}

Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue

$job = Get-VBRJob -Name $JobName

# Verify the job exists
if (!$job) {
    WriteLog "Backup job not found!"
    Exit 2
}

$SettingsFile = "C:\Temp\Job."+$job.TargetFile+".Settings.csv"

# Write through mode
if ($Mode -eq "WriteThrough") {
    if (Test-Path $SettingsFile) {
        # Remove $SettingsFile if still present when attempting to transition to write through
        Remove-Item -Path $SettingsFile
    } else {
        WriteLog "Creating the peer settings file: $SettingsFile"
        try {
          $SettingsFileHandle = New-Item $SettingsFile -Type File  
        }
        catch {
            WriteLog "Failed to create settings file : $($_.Exception.Message)"
            Exit 2
        }
            
    }
} 

elseif ($Mode -eq "WriteBack") {
    if (Test-Path $SettingsFile) {
        WriteLog "Open settings file for write back transition"
        $SettingsFileHandle = Get-Content $SettingsFile
    } else {
        WriteLog "Unable to open settings file"
        Exit 0
    }
}

# Begin code for transitioning VMs

if ($Mode -eq "WriteThrough") {
    WriteLog "Connecting to VMware vCenter Server"
    try {
        $vmware = Connect-VIServer -Server localhost -User root -Password vmware -ea stop
    }
    catch {
        WriteLog "Error connecting to vCenter : $($_.Exception.Message)"
        Exit 1
    }
    WriteLog "Connected to VMware vCenter Server"

    WriteLog "Getting objects in Veeam backup job: $JobName"
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
    WriteLog "Connecting to PernixData FVP Management Server"
    Try {
            import-module prnxcli -ea Stop
            $prnx = Connect-PrnxServer -NameOrIPAddress localhost -UserName root -Password vmware
        }
    Catch {
            WriteLog "Error connecting to FVP Management Server: $($_.Exception.Message)"
            exit 1
        }

    WriteLog "Getting list of included, powered on VMs with PernixData write-back caching enabled"
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

    WriteLog "Transitioning $VMName (peers: $VMWBPeers, external: $VMWBExternalPeers) into write through mode"
        
    Try { 
        $CacheMode = Set-PrnxAccelerationPolicy -Name $VMName -WriteThrough -ea Stop
        }

    Catch {
        WriteLog "Failed to transition $VMName : $($_.Exception.Message)"
        Exit 2
        }
    }

} elseif ($Mode -eq "WriteBack") {
    WriteLog "Connecting to PernixData FVP Management Server"
    Try {
        import-module prnxcli -ea Stop
        $prnx = Connect-PrnxServer -NameOrIPAddress localhost -UserName root -Password vmware
    }
    Catch {
        WriteLog "Error connecting to FVP Management Server: $($_.Exception.Message)"
        exit 1
    }
    WriteLog "Connected to PernixData FVP Management Server"

    foreach ($vm in $SettingsFileHandle) {
        $VMName            = $vm.split(",")[0]
        $VMWBPeers         = $vm.split(",")[1]
        $VMWBExternalPeers = $vm.split(",")[2]

        WriteLog "Transitioning $VMName into write back mode with $VMWBPeers peers and $VMWBExternalPeers external peers"
            
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