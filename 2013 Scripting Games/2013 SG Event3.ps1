<#
.SYNOPSIS
This is a script, not a function! It creates one HTML file per specified ComputerName that contains logical
disk information which are saved in the Path location.
.DESCRIPTION
    New-HTMLDiskReport.ps1 is a script that outputs HTML reports, one HTML file per computer is saved to the
folder specified in via the Path parameter for each computer that is provided via the ComputerName parameter.
A force parameter is was added because this script will probably be setup to run as a scheduled task, running
periodically and the files will need to be overwritten. The default is not to overwrite.
    Why was a script chosen instead of a function for the main functionality? It will probably be setup as a
scheduled tasks and you would have to write a script or embed some PowerShell into the scheduled tasks to dot
source a function and then run it where a script like this one can simply be called directly with the scheduled
task using PowerShell.exe.
    A separate function was chosen for retrieving the disk related data because it is now a reusable function
that could be used with other commands that are written and not just this one. Ultimately, it could be moved
into a module. PowerShell version 2.0 is required to run this script.
    The date will be generated once per computer instead placing it in the begin block and generating it once
for the entire script because the date on the report will not be accurate if this script is run against a
million computers. Calculating the date is a cheap operation which should not impede performance even when
calculating it once per computer.
.PARAMETER ComputerName
Specifies the name of a target computer(s). The local computer is the default. You can also pipe this parameter
value.
.PARAMETER Path
Specifies the file system path where the HTML files will be saved to. This is a mandatory parameter.
.PARAMETER Force
Switch parameter that when specified overwrites destination files if they already exist.
.EXAMPLE
.\New-HTMLDiskReport.ps1 -Path 'c:\inetpub\wwwroot'
.EXAMPLE
.\New-HTMLDiskReport.ps1 -ComputerName 'Server1, 'Server2' -Path 'c:\inetpub\wwwroot' -Force
.EXAMPLE
'Server1', 'Server2' | .\New-HTMLDiskReport.ps1 -Path 'c:\inetpub\wwwroot'
.EXAMPLE
'Server1', 'Server2' | .\New-HTMLDiskReport.ps1 -Path 'c:\inetpub\wwwroot' -Force
.EXAMPLE
Get-Content -Path c:\ServerNames.txt | .\New-HTMLDiskReport.ps1 -Path 'c:\inetpub\wwwroot' -Force
.INPUTS
System.String
.OUTPUTS
None
#>
 
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$True)]
    [ValidateNotNullorEmpty()]
    [string[]]$ComputerName = $env:COMPUTERNAME,
         
    [Parameter(Mandatory=$True)]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    [string]$Path,
     
    [switch]$Force
)
 
BEGIN {
    $Params = @{
        ErrorAction = 'Stop'
        ErrorVariable = 'Issue'
    }
     
    function Get-DiskInformation {
 
    <#
    .SYNOPSIS
    Retrieves logical disk information to include SystemName, Drive, Size in Gigabytes, and FreeSpace in Megabytes.
    .DESCRIPTION
    Get-DiskInformation is a function that retrieves logical disk information from machines that are provided via the
    computer name parameter. This function is designed for re-usability and could possibly be moved into a module at
    a later date. PowerShell version 2.0 is required to run this function.
    .PARAMETER ComputerName
    Specifies the name of a target computer. The local computer is the default. 
    .EXAMPLE
    Get-DiskInformation -ComputerName 'Server1'
    .INPUTS
    None
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
 
        [CmdletBinding()]
        param(
            [ValidateNotNullorEmpty()]
            [string]$ComputerName = $env:COMPUTERNAME
        )
 
        $Params = @{
            ComputerName = $ComputerName
            NameSpace = 'root/CIMV2'
            Class = 'Win32_LogicalDisk'
            Filter = 'DriveType = 3'
            Property = 'DeviceID', 'Size', 'FreeSpace', 'SystemName'
            ErrorAction = 'Stop'
            ErrorVariable = 'Issue'
        }
 
        try {
            Write-Verbose -Message "Attempting to query logical disk information for $ComputerName."
            $LogicalDisks = Get-WmiObject @Params
            Write-Verbose -Message "Test-Connection was not used because it does not test DCOM connectivity, only ping."
        }
        catch {
            Write-Warning -Message "$Issue.Message.Exception"
        }
 
        foreach ($disk in $LogicalDisks){
 
        $DiskInfo = @{
            'SystemName' = $disk.SystemName
            'Drive' = $disk.DeviceID
            'Size(GB)' = "{0:N2}" -f ($disk.Size / 1GB)
            'FreeSpace(MB)' = "{0:N2}" -f ($disk.FreeSpace / 1MB)
        }
 
        New-Object PSObject -Property $DiskInfo
 
        }
    }
 
}
 
PROCESS {
    foreach ($Computer in $ComputerName) {
 
        $Problem = $false
        $Params.ComputerName = $Computer
 
        try {
            Write-Verbose -Message "Calling the Get-DiskInformation function."
            $DiskSpace = Get-DiskInformation @Params 
        }
        catch {
            $Problem = $True
            Write-Warning -Message "$Issue.Exception.Message"
        }
 
        if (-not($Problem)) {
             
            $DiskHTML = $DiskSpace | Select-Object -Property Drive, 'Size(GB)', 'FreeSpace(MB)' | ConvertTo-HTML -Fragment | Out-String
            $MachineName = $DiskSpace | Select-Object -ExpandProperty SystemName -Unique
            $Params.remove("ComputerName")
 
            $HTMLParams = @{
                'Title'="Drive Free Space Report"
                'PreContent'="<H2>Local Fixed Disk Report for $($MachineName) </H2>"
                'PostContent'= "$DiskHTML <HR> $(Get-Date)"
            }
 
            try {
                Write-Verbose -Message "Attempting to create the filepath variable."
                $FilePath = Join-Path -Path $Path -ChildPath "$($MachineName.ToLower()).html" @Params
 
                Write-Verbose -Message "Attempting to convert to HTML and write the file to the $FilePath folder for $Computer"
                ConvertTo-HTML @HTMLParams | Out-File -FilePath $FilePath -NoClobber:(-not($Force)) @Params
            }
            catch {
                Write-Warning -Message "Use the -Force parameter to overwrite existing files. Error details: $Issue.Message.Exception"
            }
        }
    }
}