Param ( 
    [Parameter(Mandatory=$false)]$DeleteOldChain,
    [Parameter(Mandatory=$false)]$DeleteIncremental
)

Add-PSSnapIn VeeamPSSnapIn

# Thanks to Tom Sightler for these lines!
$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
$job = Get-VBRJob | ?{$parentcmd -like "*"+$_.Id.ToString()+"*"}
$session = Get-VBRBackupSession | ?{($_.OrigJobName -eq $job.Name) -and ($parentcmd -like "*"+$_.Id.ToString()+"*")}

if (!$job) {
    $job = Get-VBRJob -Name "copy-test"
}

$backup = Get-VBRBackup -Name $job.Name

$options = $job.GetOptions()
$restore_points = $options.GenerationPolicy.SimpleRetentionRestorePoints


# Go to this directory, which will be an SMB path
$target = $job.TargetDir+"\"+$job.TargetFile

$files = (Get-ChildItem $target |Where-Object { $_.Name -match ".vbk" -or $_.Name -match ".vib" })
$files_count = $files.Count

if ($files_count -ge $restore_points) {

	$new_directory = "Archive_" + $job.TargetFile
    $new_directory = $job.TargetDir+"\"+$new_directory

    Try {        
        if (-Not (Test-Path -Path $new_directory)) {
            Write-Host ("Creating directory {0}" -f $new_directory)
            New-Item $new_directory -Type Directory
        }

        $target_files = (Get-ChildItem $new_directory |Where-Object { $_.Name -match ".vbk" -or $_.Name -match ".vib" })

        foreach ($file in ($backup.GetStorages())) {
            Write-Host ("Moving file {0}" -f $file.FilePath)
            Move-Item $file.FilePath $new_directory
        }
    } Catch [System.Exception] {
        "An error occured!"
    } Finally {
        Write-Host ("Removing the empty folder {0}" -f $target)
        Remove-Item -Path $target -Recurse

        if ($DeleteOldChain -eq $true) {
            foreach ($f in $target_files) {
                Write-Host ("Removing old chain files: {$0}" -f $f.Name)
                Remove-Item $f.FullName
            }
        }

        if ($DeleteIncremental -eq $true) {
            foreach ($f in $target_files) {
                if ($f.Name -match ".vib") {
                    Write-Host ("Removing incremental: {$0}" -f $f.Name)
                    Remove-Item $f.FullName
                }
            }
        }
    }
}