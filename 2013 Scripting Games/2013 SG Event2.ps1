#Requires -Version 3.0
 
function Get-SystemInventory {
 
<#
.SYNOPSIS
Retrieves hardware and operating system information for systems running Windows 2000 and higher. 
.DESCRIPTION
Get-SystemInventory is a function that retrieves the computer name, operating system version, amount of physical memory
(RAM) in megabytes, and number of processors (CPU's) sockets from one or more hosts specified via the ComputerName parameter
or via pipeline input. The TotalPhysicalMemory property of Win32_ComputerSystem was initially used, but that property is not
the total amount of physical system memory. It is the amount of system memory available to Windows after the OS takes some
out for video if necessary or if the OS doesn't support the amount of RAM in the machine which is common when running an older
32 bit operating system on hardware with a lot of physical memory. Displaying the amount of memory in megabytes was chosen
because this function can be run against older hosts where less than half a gigabyte of memory is common and casting 256MB for
example to an integer in gigabytes would display zero which is not useful information. The amount of processor sockets was
chosen for similar reasons because older operating systems aren't aware of CPU cores and that information wouldn't be reliably
provided across all operating systems this function could be run against. Initially, the NumberOfProcessors property in the
Win32_ComputerSystem class was used, but it does not provide an accurate count of CPU sockets on older operating systems with
multi-core processors per this MSDN article: http://msdn.microsoft.com/en-us/library/windows/desktop/aa394102(v=vs.85).aspx
The Cim cmdlets have been used to gain maximum efficiency so only one connection will be made to each computer. This tool has
also been future proofed so as more hosts are upgraded to newer Windows operating systems, they will be able to take advantage
of the WSMAN protocol because DCOM is blocked by default in the firewall of newer operating systems and possibly on firewalls
between the computer running this tool and the destination host. A ShowProtocol switch parameter has been provided so the
results can be filtered (Where-Object) or sorted (Sort-Object) to determine which computers are not being communicated with
using WSMAN which is another means of finding older hosts. A Credential parameter has been provided because it's best practice
to run PowerShell as a non-domain admin and provide the domain admin credentials specified in the scenario on an as needed per
individual command basis. This function requires PowerShell version 3 on the computer it is being run from, but PowerShell is
not required to be installed or enabled on the remote computers that it is being run against.
.PARAMETER ComputerName
Specifies the name of a target computer(s). The local computer is the default. You can also pipe this parameter value.
.PARAMETER Credential
Specifies a user account that has permission to perform this action. The default is the current user.
.EXAMPLE
Get-SystemInventory
.EXAMPLE
Get-SystemInventory -ComputerName 'Server1'
.EXAMPLE
Get-SystemInventory -ComputerName 'Server1', 'Server2' -Credential 'Domain\UserName'
.EXAMPLE
'Server1', 'Server2' | Get-SystemInventory
.EXAMPLE
(Get-Content c:\ComputerNames.txt) | Get-SystemInventory
.EXAMPLE
(Get-Content c:\ComputerNames.txt, c:\ServerNames.txt) | Get-SystemInventory -Credential (Get-Credential) -ShowProtocol
.INPUTS
System.String
.OUTPUTS
System.Management.Automation.PSCustomObject
#>
 
    param(
        [Parameter(ValueFromPipeline=$True)]
        [ValidateNotNullorEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,
 
        [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty,
 
        [switch]$ShowProtocol
    )
 
    BEGIN {
        $Opt = New-CimSessionOption -Protocol Dcom
    }
 
    PROCESS {
        foreach ($Computer in $ComputerName) {
 
            Write-Verbose "Attempting to Query $Computer"
            $Problem = $false
            $SessionParams = @{
                ComputerName  = $Computer
                ErrorAction = 'Stop'
            }
 
            If ($PSBoundParameters['Credential']) {
               $SessionParams.credential = $Credential
            }
     
            if ((Test-WSMan -ComputerName $Computer -ErrorAction SilentlyContinue).productversion -match 'Stack: 3.0') {
                try {
                    $CimSession = New-CimSession @SessionParams
                    $CimProtocol = $CimSession.protocol
                    Write-Verbose "Successfully created a CimSession to $Computer using the $CimProtocol protocol."
                }
                catch {
                    $Problem = $True
                    Write-Verbose "Unable to connect to $Computer using the WSMAN protocol. Verify your credentials and try again."
                }
            }
 
            elseif (Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                $SessionParams.SessionOption = $Opt
                try {
                    $CimSession = New-CimSession @SessionParams
                    $CimProtocol = $CimSession.protocol
                    Write-Verbose "Successfully created a CimSession to $Computer using the $CimProtocol protocol."
                }
                catch {
                    $Problem = $True
                    Write-Verbose  "Unable to connect to $Computer using the DCOM protocol. Verify your credenatials and that DCOM is allowed in the firewall on the remote host."
                }
            }
 
            else {
                $Problem = $True
                Write-Verbose "Unable to connect to $Computer using the WSMAN or DCOM protocol. Verify $Computer is online and try again."
            }
 
            if (-not($Problem)) {
                $OperatingSystem = Get-CimInstance -CimSession $CimSession -Namespace root/CIMV2 -ClassName Win32_OperatingSystem -Property CSName, Caption, Version
                $PhysicalMemory = Get-CimInstance -CimSession $CimSession -Namespace root/CIMV2 -ClassName Win32_PhysicalMemory -Property Capacity |
                                  Measure-Object -Property Capacity -Sum
                $Processor = Get-CimInstance -CimSession $CimSession -Namespace root/CIMV2 -ClassName Win32_Processor -Property SocketDesignation |
                             Select-Object -Property SocketDesignation -Unique
                Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
            }
 
            else {
                $OperatingSystem = @{
                    CSName= $Computer
                    Caption = 'Failed to connect to computer'
                    Version = 'Unknown'
                }
                $PhysicalMemory = @{
                    Sum = 0
                }
                $Processor = @{
                }
                $CimProtocol = 'NA'
            }
 
            $SystemInfo = [ordered]@{
                ComputerName = $OperatingSystem.CSName
                'OS Name' = $OperatingSystem.Caption
                'OS Version' = $OperatingSystem.Version
                'Memory(MB)' =  $PhysicalMemory.Sum/1MB -as [int]
                'CPU Sockets' = $Processor.SocketDesignation.Count
            }
 
            If ($PSBoundParameters['ShowProtocol']) {
               $SystemInfo.'Connection Protocol' = $CimProtocol
            }
 
            New-Object PSObject -Property $SystemInfo
        }
    }
}