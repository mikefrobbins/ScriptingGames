function Move-LogFile {
 
<#
.SYNOPSIS
Move files with a .log extension from the SourcePath to the DestinationPath that are older than Days. 
.DESCRIPTION
Move-LogFile is a function that moves files with a .log extension from the first level subfolders that are specified via
the SourcePath parameter to the same subfolder name in the DestinationPath parameter that are older than the number of days
specified in the Days parameter. If a subfolder does not exist in the destination with the same name as the source, it will
be created. This function requires PowerShell version 3.
.PARAMETER SourcePath
The parent path of the subfolders where the log files reside. Log files in the actual SourcePath folder will not be archived,
only first level subfolders of the specified SourcePath location.
.PARAMETER DestinationPath
Parent Path of the Destination folder to archive the log files. The name of the original subfolder where the log files reside
will be created if it doesn't already exist in the Destination folder. Destination subfolders are only created if one or more
files need to be archived based on the days parameter. Empty subfolders are not created until needed.
.PARAMETER Days
Log files not written to in more than the number of days specified in this parameter are moved to the destination folder location.
.PARAMETER Force
Switch parameter that when specified overwrites destination files if they already exist.
.EXAMPLE
Move-LogFile -SourcePath 'C:\Application\Log' -DestinationPath '\\NASServer\Archives' -Days 90
.EXAMPLE
Move-LogFile -SourcePath 'C:\Application\Log' -DestinationPath '\\NASServer\Archives' -Days 90 -Force
#>
 
    [CmdletBinding()]
    param (
        [string]$SourcePath = 'C:\Application\Log',
        [string]$DestinationPath = '\\NASServer\Archives',
        [int]$Days = 90,
        [switch]$Force
    )
 
    BEGIN {        
        Write-Verbose "Retrieving a list of files to be archived that are older than $($Days) days"
        try {
            $files = Get-ChildItem -Path (Join-Path -Path $SourcePath -ChildPath '*\*.log') -ErrorAction Stop |
                     Where-Object LastWriteTime -lt (Get-Date).AddDays(-$days)
        }
        catch {
            Write-Warning $_.Exception.Message
        }
 
        $folders = $files.directory.name | Select-Object -Unique
        Write-Verbose "A total of $($files.Count) files have been found in $($folders.Count) folders that require archival"
    }
 
    PROCESS {
        foreach ($folder in $folders) {
         
            $problem = $false
            $ArchiveDestination = Join-Path -Path $DestinationPath -ChildPath $folder
            $ArchiveSource = Join-Path -Path $SourcePath -ChildPath $folder
            $ArchiveFiles = $files | Where-Object directoryname -eq $ArchiveSource
 
            if (-not (Test-Path $ArchiveDestination)) {
                Write-Verbose "Creating a directory named $($folder) in $($DestinationPath)"
                try {
                    New-Item -ItemType directory -Path $ArchiveDestination -ErrorAction Stop | Out-Null
                }
                catch {
                    $problem = $true
                    Write-Warning $_.Exception.Message
                }
            }
 
            if (-not $problem) {
                Write-Verbose "Archiving $($ArchiveFiles.Count) files from $($ArchiveSource) to $($ArchiveDestination)"
                try {
                    If ($Force) {
                        $ArchiveFiles | Move-Item -Destination $ArchiveDestination -Force -ErrorAction Stop
                    }
                    Else {
                        $ArchiveFiles | Move-Item -Destination $ArchiveDestination -ErrorAction Stop
                    }
                }
                catch {
                    Write-Warning $_.Exception.Message
                }
            }
 
        }
    }
 
    END {
        Remove-Variable -Name SourcePath, DestinationPath, Days, Force, files, folders, folder,
        problem, ArchiveDestination, ArchiveSource, ArchiveFiles -ErrorAction SilentlyContinue
    }
 
}