# .Net methods for hiding/showing the console in the background
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
function Hide-Console
{
    $consolePtr = [Console.Window]::GetConsoleWindow()
    #0 hide
    [Console.Window]::ShowWindow($consolePtr, 0)
}

function New-PSArray {
    [cmdletbinding()] 
    param([string]$type = 'object')
    New-Object -TypeName System.Collections.Generic.List[$type]
}

function Write-BackupLog {
    [cmdletbinding()] 
    param([string]$Log, [int]$Severity)
    
    $LogPath = $BackupPath
    $LogName = "backup.log"

    if ($GlobalWriteLog  -eq $true) {
        if (Test-Path $LogPath\$LogName) {
            Write-Verbose "Log file already exists."
        } else {
            New-Item -Path $LogPath -Name $LogName -ItemType File 
        }
    
        if ($Severity -eq 1) {
            Add-Content -Path $LogPath\$LogName -value "[INFO] $Log" -Force
        } elseif ($Severity -eq 2) {
            Add-Content -Path $LogPath\$LogName -value "[WARNING] $Log"
        } elseif ($Severity -eq 3) {
            Add-Content -Path $LogPath\$LogName -value "[ERROR] $Log"
        } else {
            Add-Content -Path $LogPath\$LogName -value "[INFO] $Log"
        }
    } else {
        Write-Verbose "Input specifies to not write to log file, continuing."
    }    
}

function Start-VHBackup {
    [cmdletbinding()]
    param([string][ValidateSet('Characters', 'Worlds')]$Type)

    if ($type -eq "Worlds") { $extensions = @("db","fwl") } 
    elseif ($type -eq "Characters") { $extensions = @("fch") }

    if (Test-Path $BackupPath\$Type\$Type.json) {
        Write-BackupLog -Log "$($Type).json detected, checking for hash differences." -Severity 1

        $Saves = Get-ChildItem $SavePath\$Type\*.$($extensions[0])
        $JSON = Get-Content $BackupPath\$Type\$Type.json | ConvertFrom-JSON

        foreach ($save in $Saves) {
            if ($JSON.BaseName -contains $save.BaseName) {
                $hash = ($save | Get-FileHash -Algorithm MD5).Hash
                $latest = $JSON | Where-Object BaseName -eq $save.baseName | Select-Object -ExpandProperty Hash
                if ($hash -eq $latest) {
                    Write-BackupLog "$($save.BaseName) hash matches in save and backup folders." -Severity 1
                } else {
                    Write-BackupLog "$($save.BaseName) hash does not match in save and backup folders. Backing up." -Severity 1
                    ($JSON | Where-Object BaseNAme -eq $save.baseName).Hash = $hash
                    Set-Content -Path $BackupPath\$Type\$Type.json -Value ($JSON | ConvertTo-JSON)
                    foreach ($extension in $extensions) {
                        Copy-Item -Path "$SavePath\$Type\$($save.BaseName).$extension" -Destination "$BackupPath\$Type\$($save.basename)_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').$extension" 
                    }
                }
            }
        }   
    } else {
        Write-BackupLog -Log "$($Type).json not detected, creating json." -Severity 1
        $listOfsaves = Get-ChildItem $Savepath\$type | Where-Object Extension -eq ".$($extensions[0])"
        $OutputArray = New-PSArray
        foreach ($save in $listOfsaves) {
                $SaveJson = New-Object PSCustomObject @{
                    BaseName = $save.BaseName
                    Hash = ($save | Get-FileHash -Algorithm MD5).Hash
                }
                $OutputArray.Add($SaveJson)
        }
        $OutputArray | ConvertTo-Json | Out-File -FilePath $BackupPath\$Type\$type.json
        foreach ($extension in $extensions) {
            Write-BackupLog -Log "Backing up all .$($extension) files." -Severity 1
            Get-ChildItem $SavePath\$Type\*.$extension | Copy-Item -Destination $BackupPath\$Type
            Write-BackupLog -Log "Renaming all backed up .$($extension) files to have timestamp." -Severity 1
            Get-ChildItem $BackupPath\$Type\*.$extension | Rename-Item -NewName { "$($_.basename)_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')$($_.Extension)" 
        }
    }
}
}

function Start-VHPurge {
    [cmdletbinding()]
    param([string][ValidateSet('Characters', 'Worlds')]$Type)

    if ($type -eq "Worlds") { $extensions = @("db","fwl"); $multiplyer = 2 } 
    elseif ($type -eq "Characters") { $extensions = @("fch"); $multiplyer = 1 }

    $AllSaves = Get-ChildItem $BackupPath\$Type
    $JSON = Get-Content $BackupPath\$Type\$Type.json | ConvertFrom-JSON
    foreach ($save in $JSON) {
        $AllSaves | Where-Object Name -like "$($save.BaseName)*" | Sort-Object LastWriteTime -Descending | Select-Object -Skip $($ScriptSettings.BackupsToKeep * $multiplyer) | Remove-Item
    }
}

Function Start-MonitoringForBackups
{
    [cmdletbinding()] 
    param([int]$Frequency, [int]$AmountToKeep)

    Write-Host "[INFO] Backups will be placed at $BackupPath."
    Write-Host "[INFO] This script will run continuously, checking if a backup is required every $Frequency seconds."
    Write-Host "[INFO] Config.json in the backup folder determines the frequency of backups, and whether or not a log file is written."
    Write-Host "[INFO] This window will hide itself in 2 minutes, and run under the process 'Valheim Backup.exe' in Task Manager"
    Write-Host "[INFO] Should you wish to stop the backups from running, kill the process via task manager."

    # Start-Sleep -Seconds 120
    # Hide-Console

    While ($true)
    {
        $CurrentRunTime = Get-Date -Format 'yyyyMMdd_HHmm'

        Write-BackupLog -Log "`$SavePath: $SavePath" -Severity 1
        Write-BackupLog -Log "`$BackupPath: $BackupPath" -Severity 1
        Write-BackupLog -Log "`$CurrentRunTime: $CurrentRunTime" -Severity 1

        # Determine if the latest copy is older than the current date modified of either worlds or characters

        #    Worlds Backup
        
        Start-VHBackup -Type Worlds
        Start-VHPurge -Type Worlds

        #    Characters Backup

        Start-VHBackup -Type Characters
        Start-VHPurge -Type Characters
        
        #    Sleep
        Write-BackupLog -Log "Next backup check: $((Get-Date).AddSeconds($Frequency))"

        Start-Sleep -Seconds $Frequency
    }
}

function New-BackupDirectory {
    # Establish Backup Directory
    try {
        if (Test-Path -Path $BackupPath) {
            Write-BackupLog -Log "ValheimBackup Folder exists, will not create." -Severity 1
        } else {        
            New-Item -Path $BackupPath -ItemType Directory
            New-Item -Path $BackupPath\worlds -ItemType Directory
            New-Item -Path $BackupPath\characters -ItemType Directory
            Write-BackupLog -Log "Creating ValheimBackup Folder at $BackupPath" -Severity 1

            New-Item -Path $BackupPath\config.json -ItemType File
            Write-BackupLog -Log "Creating config.json at $BackupPath" -Severity 1
                $Settings = New-Object PSCustomObject @{
                    WriteLog = $true
                    FrequencyInSeconds = 90
                    BackupsToKeep = 2
                } | ConvertTo-Json
            Add-Content -Path $BackupPath\config.json -Value $Settings          
            }
        }
    catch {
        $_
        # Write-BackupLog -Log $error[0].ToString() -Severity 3 -Write $WriteLog
    }
}

$SavePath = "$env:SystemDrive\Users\$env:USERNAME\AppData\LocalLow\IronGate\Valheim"
$BackupPath = "$env:SystemDrive\Users\$env:USERNAME\Desktop\Valheim Backups"

New-BackupDirectory

$ScriptSettings = Get-Content $BackupPath\config.json | ConvertFrom-Json

$GlobalWriteLog = $ScriptSettings.WriteLog

Start-MonitoringForBackups -Frequency $ScriptSettings.FrequencyInSeconds -AmountToKeep $ScriptSettings.BackupsToKeep
