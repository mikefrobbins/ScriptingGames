#Requires -Version 3.0
function Get-IISClientIP {
 
<#
.SYNOPSIS
    Returns a list of unique IP addresses of clients that have accessed websites on an IIS server based on information
found in the IIS log files.
 
.DESCRIPTION
    Get-IISClientIP is a function that retrieves a list of unique IP addresses of client machines that have accessed a
website on an Internet Information Services (IIS) server. This information is based off of the IIS log files which are
located in the 'c:\inetpub\logs\logfiles\' folder for IIS 7.0 and higher or "$env:windir\system32\LogFiles\" for IIS
6.0 and older by default. This tool is designed to only work with the IIS default W3C Extended log file format. Read
the help for the Path parameter for more information and to learn why a default path was not specified.
    I thought about the performance of querying the IIS log files and tested many different options to include
retrieving the client IPs using a regular expression with Select-String and I also tested runspaces, Foreach -Parallel
in a Workflow, and custom Foreach-Parallel functions. In the end I decided the best way to boost performance was to
add an optional Days parameter in an attempt to prevent the querying of unnecessary and irrelevant data. It's simple,
the less data you query the better your performance will be no matter which method of querying the data you choose.
    I determined it would be very difficult to use a regular expression to match the client ip address even when using
negative lookahead because with legacy IIS servers such as IIS 5, the client IP address is the first IP address on
each line in the log files where as it's the second IP address on each line with IIS 6.0 and higher.
    Import-CSV was chosen for code reusability because it makes it easy to add additional columns and/or filter on
them. Legacy versions of IIS have different column headers. Only four lines of each log file is read to determine if
it's the proper format (W3C Extended), if it's not the foreach loop continues to the next iteration without breaking
out of the pipeline (no continue keyword). The last column header in an IIS 5 log file is an empty string so -ne ''
was added to prevent adding it to the column header list which proactively prevents an error and allows this tool to
be fully compatible with log files from those legacy versions of IIS.
    Design Notes have been added to the code below. Those notes are not meant for the user of this tool which is why
they're not in the comment based help, they are meant for the person that comes behind me and needs to understand how
and why some of the decisions were made in the design of this tool.
 
.PARAMETER Path
    The full path to the directory location of the IIS log files. This is a mandatory parameter and a default has not
been set because it wouldn't be validated by the parameter validation. See this blog article to learn more about why a
default value wouldn't be validated: http://powershell.org/wp/2013/05/01/why-doesnt-my-validatescript-work-correctly/
    This function could be run on a non-IIS server specifying a network location for the log files so querying the
local machine for the location of the logfiles based on the version of IIS, a value in the registry, or a value in WMI
is not a valid test. This function searches the directory it is pointed to and all sub directories below that directory
in case the log files have been copied from their default location and exist in more that the single level sub folders
that IIS defaults to. This tool has been tested against IIS 5 and newer log files, although it should work with IIS 4
as well since it uses the W3C Extended log files as well. A mixture of IIS 5 and greater log files can coexist in the
path and this tool will properly query them and provide accurate results even though the log files are formatted
differently in IIS 5 versus IIS 6 and higher.
 
.PARAMETER IPAddress
    Filters the results down to a subset of IP Addresses. A complete IP Address and/or wildcards (four octets) may be
specified, although this is not a mandatory parameter. A custom regular expression was created and is used to validate
that the specified parameter input is a valid IP address and/or wildcards (asterisks). This proactively catches invalid
input instead of searching hundreds of log files for an invalid IP address that couldn't have possibly accessed a website
on the IIS server. A meaningful error message is returned if invalid input is specified. The default value is *.*.*.*
which returns all IP addresses. Valid values include: 192.168.1.1, 192.*.*.*, 192.168.*.*, 192.168.1.*, or *.*.*.*
    See this blog article to learn more about returning meaningful error messages when performing this type of parameter
validation: http://powershell.org/wp/2013/05/23/scripting-games-2013-event-4-notes/. 
 
.PARAMETER Days
    Specifies the number of days in the past to return client IP Addresses for in case you have log files dating back
years. Parameter validation prevents negative numbers from being entered because they would not return any data because
the date specified would be in the future. 7 is seven days in the past. Parameter validation also prevents a date prior
to the release of IIS 4.0, part of the Windows NT 4.0 Option Pack, from being entered because that is the first version
of IIS to use the W3C extended log file format so there would be no reason to search for log files prior to that date.
    Limiting the maximum number that can be entered also proactively prevents a large enough integer from being entered
that would generate an error because of attempting to create a datetime before 1/1/0001 with the Get-Date cmdlet when
the number entered for the Days parameter is subtracted from the current date.
    It's very possible that you may only want to see the unique IP addresses that have accessed your IIS server in the
past week, month, or year for example and there's no reason to kill the performance of the machine running this tool by
searching for client IP addresses in log files older than that. The default is no value which returnes all unique
client IP Addresses for all dates contained in the log files.
 
.EXAMPLE
    Get-IISClientIP -Path 'c:\inetpub\logs\logfiles\'
 
.EXAMPLE
    Get-IISClientIP -Path 'c:\inetpub\logs\logfiles\' -IPAddress '192.168.1.*'
 
.EXAMPLE
    Get-IISClientIP -Path 'c:\inetpub\logs\logfiles\' -Days 7
 
.EXAMPLE
    Get-IISClientIP -Path 'c:\inetpub\logs\logfiles\' -IPAddress '10.*.*.*' -Days 30
 
.INPUTS
    None
 
.OUTPUTS
    Selected.System.Management.Automation.PSCustomObject
#>
 
    [CmdletBinding()]
    param (
 
            #Design Note: Default value not provided because it wouldn't be validated and may not exist on the machine running this tool.
        [Parameter(Mandatory)]
        [ValidateScript({
            Test-Path $_ -PathType 'Container'
        })]
        [string]$Path,
 
            #Design Note: Only search log files for valid IP addresses if specified. Wildcards (asterisks) are also allowed. Default to searching for all IP Addresses.
        [ValidateScript({
            If ($_ -match "^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|\*)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|\*)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|\*)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|\*)$") {
                $True
            }
            else {
                Throw "$_ is either not a valid IPv4 Address or search value. All four octets are required. Example: '*.*.*.*' or '192.168.*.*'"
            }
        })]
        [string]$IPAddress = '*.*.*.*',
 
            #Design Note: A default value wouldn't trigger the $PSBoundParameters later in the code. See the comment based help for the days parameter for details of how and why this validation was chosen. 
        [ValidateScript({
            If ($_ -ge 1 -and $_ -le (New-TimeSpan -Start 12/02/1997).days) {
                $True
            }
            else {
                Throw "Invalid value of $_ specified. Try again and enter the number of days in the past between between 1 and $((New-TimeSpan -Start 12/02/1997).days) to scan log files for."
            }
        })]
        [int]$Days
 
    )
 
    $Problem = $false
 
    $Params = @{
        ErrorAction = 'Stop'
        ErrorVariable = 'Issue'
    }
 
    If ($PSBoundParameters['Days']) {
        $Date = (Get-Date).AddDays(-$Days)
        Write-Verbose -Message "Days parameter has been specified. Client IP Addresses since $Date will be returned."
    }
 
    try {
        Write-Verbose -Message "Attempting to obtain a list of IIS log files to query"
 
        $LogFiles = Get-ChildItem -Path $Path -Include '*.log' -File -Recurse @Params |
                    Where-Object LastWriteTime -gt $Date |
                    Select-Object -ExpandProperty FullName
 
        Write-Verbose -Message "The following IIS LogFiles will be queried for Client IP Addresses: $LogFiles"   
    }
    catch {
        $Problem = $True
        Write-Warning -Message "$Issue.Exception.Message"
    }
 
    If ($LogFiles -and (-not($Problem))) {
 
        $Results = foreach ($LogFile in $LogFiles) {
 
            try {
                    #Design Note: Read only the first 4 lines of the log file to obtain the column headers and determine if it's in W3C extended format. Added -ne '' for IIS 5 log file compatibility.         
                Write-Verbose -Message "Obtaining a list of column headers for $LogFile"
                $Headers = (Get-Content -Path $LogFile -TotalCount 4 @Params)[3] -split ' ' -notmatch '^#' -ne ''
 
                If ('c-ip' -in $Headers) {
                        #Design Note: Import-CSV was chosen for code reusability. Makes it easy to add additional columns and/or filter on them.
                    Write-Verbose -Message "Importing file contents into CSV format based on column headers: $Headers."
                    Import-Csv -Delimiter ' ' -Header $Headers -Path $LogFile @Params |
 
                        #Design Note: Filter IP Addresses down to a subset and filter down to a specific date range. This does work even if $Days was not specified.
                    Where-Object -FilterScript {$_.'c-ip' -like $IPAddress -and $_.date -notmatch '^#' -and $_.date -gt $Date} |
 
                        #Design Note: Finding unique IP Addresses as we go (duplicates in the same log file) to keep the result set as small and as efficient as possible.
                    Select-Object -Property 'c-ip' -Unique
                }
                else {
                    Write-Warning -Message "Non-IIS log file or non-W3C Extended log file format detected: $LogFile Continuing to the next file."
                }
            } 
            catch {
                $Problem = $True
                Write-Warning -Message "$Issue.Exception.Message"
            }
 
        }
 
        If (-not($Problem)) {
            Write-Verbose -Message "Performing final process to remove IP Addresses that are duplicated across multiple queried log files."
            $Results | Select-Object -Property @{Label='ClientIPAddress';Expression={$_.'c-ip'}} -Unique
        }
             
    }
    else {
        Write-Warning -Message "No LogFiles found in $Path within the specified date range: $($date) to $(Get-Date)"
    }
}