#Requires -Version 3.0
#Requires -Modules DhcpServer
function Add-DomainComputer {
 
<#
.SYNOPSIS
    Adds computers running Windows Server 2012 to a domain based on MAC Address for computers that receive their IP
address via DHCP.
 
.DESCRIPTION
    Add-DomainComputer is a function that adds computers running Windows Server 2012 to a domain. PowerShell 3.0 is
required to run this tool.The Windows Server 2012 computer that you want to add to the domain must receive its IP
address via DHCP. This tool accepts the MAC address of the computer(s) you wish to add to the domain via pipeline
or paramter input. Those MAC addresses are translated to IP addresses using the Get-DhcpServerv4Lease function that
is part of the DhcpServer module which is installed as part of the Remote Server Administration Tools (RSAT):
http://www.microsoft.com/en-us/download/details.aspx?id=28972.
    The current list of trusted hosts for the machine running this tool is captured, and then all of the IP addresses
of the machines you are adding to the domain are added to the trustedhosts list. The last step once this tool
completes is to restore the trusted host list to the state it was in prior to this tool being run to prevent any
issues with machines that may have already existed in the trusted host list and to prevent the permenant reduction
of security for the machine running this tool.
    A workflow is used to add all of the machines to the domain in parallel.    
 
.PARAMETER MACAddress
    The Media Access Control Address of the network card in the Windows Server 2012 computer that is receiving its
IP address via a DHCP server that you're attempting to add to the domain. The value(s) for this parameter must be
specified in MAC-48 format which is six groups of two hexadecimal digits separated by dashes: 01-23-45-67-89-AB.
 
.PARAMETER NewNameBase
    The base name for the new name to be used for the Servers. Numbers starting with 1 are appended to this base
name and used to rename the server when adding them to the domain. The default is "SERVER" which will cause the
servers to be named "SERVER1", "SERVER2", etc.
 
.PARAMETER DHCPServer
    The name of the DHCP Server that is providing IP addresses to the servers you wish to add to the domain. The
default attempts to obtain the DHCP information from a server named "DHCP1".
 
.PARAMETER DHCPScopeId
    The name of the DHCP Scope on the server specified via the DHCPServer parameter. The default attempts to obtain
DHCP information from a scope named "10.0.0.0".
 
.PARAMETER DomainName
    The name of the domain that you are attempting to add the new servers to. The default is to attempt to add the
new servers to a domain named "Company.local".
 
.PARAMETER LocalAdminCredential
    A local account on the servers that you're attempting to add to the domain that has local admin privileges. The
default obfuscates the password provided in the requirements for this scenario to prevent it from being displayed in
clear text, but this is not a secure method of storing a password. 
 
.PARAMETER DomainAdminCredential
    A domain account in the domain that you're attempting to add to the servers to that has domain admin privileges (As
specified in the scenario requirements). The default obfuscates the password provided in the requirements for this
scenario to prevent it from being displayed in clear text, but this is not a secure method of storing a password.
 
.EXAMPLE
    Add-DomainComputer -MACAddress '01-23-45-67-89-AB', '01-23-45-67-89-A1'
 
.EXAMPLE
    '01-23-45-67-89-AB', '01-23-45-67-89-A1' | Add-DomainComputer
 
.EXAMPLE
    Get-Content .\server-macs.txt | Add-DomainComputer
 
.EXAMPLE
    Get-Content .\server-macs.txt | Add-DomainComputer -BaseName 'SERVER'
 
.EXAMPLE
    Get-Content .\server-macs.txt | Add-DomainComputer -BaseName 'SERVER' -DHCPServer 'DHCP1'
 
.EXAMPLE
    Get-Content .\server-macs.txt | Add-DomainComputer -BaseName 'SERVER' -DHCPServer 'DHCP1' -DHCPScopeId '10.0.0.0'
 
.EXAMPLE
    Get-Content .\server-macs.txt | Add-DomainComputer -BaseName 'SERVER' -DHCPServer 'DHCP1' -DHCPScopeId '10.0.0.0' -DomainName 'Company.local'
 
.EXAMPLE
    Get-Content .\server-macs.txt | Add-DomainComputer -LocalAdminCredential (Get-Credential Administrator) -DomainAdminCredential (Get-Credential company\Admin)
 
.INPUTS
    String
 
.OUTPUTS
    None
#>
 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [ValidateScript({
            If ($_ -match '^([0-9a-fA-F]{2}[:-]{0,1}){5}[0-9a-fA-F]{2}$') {
                $True
            }
            else {
                Throw "$_ is either not a valid MAC Address or was not specified in the required format. Please specify one or more MAC addresses in the follwing format: '01-23-45-67-89-AB'"
            }
        })]
        [string[]]$MACAddress,
 
        [ValidateNotNullorEmpty()]
        [string]$NewNameBase = 'SERVER',
 
        [ValidateNotNullorEmpty()]
        [string]$DHCPServer = 'DHCP1',
 
        [ValidateNotNullorEmpty()]
        [string]$DHCPScopeId = '10.0.0.0',
 
        [ValidateNotNullorEmpty()]
        [string]$DomainName = 'Company.local',
 
        [pscredential]$LocalAdminCredential = (
            New-Object System.Management.Automation.PSCredential -ArgumentList administrator, (
            -join ("5040737377307264" -split "(?<=\G.{2})",19 |
            ForEach-Object {if ($_) {[char][int]"0x$_"}}) |
            ConvertTo-SecureString -AsPlainText -Force)
        ),
 
        [pscredential]$DomainAdminCredential = (
            New-Object System.Management.Automation.PSCredential -ArgumentList company\admin, (
            -join ("5040737377307264" -split "(?<=\G.{2})",19 |
            ForEach-Object {if ($_) {[char][int]"0x$_"}}) |
            ConvertTo-SecureString -AsPlainText -Force)
        )
    )
 
    BEGIN {
        Write-Verbose -Message "Determining if PowerShell is running as an Admin. Terminating the tool execution and returning a message to the user if not."
        if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
 
            $IPNameMatrix = @{}
 
            Write-Verbose -Message "Obtaining the list of currently trusted hosts, -Force will start the WinRM service if it in not already running without prompting."
            $TrustedHost = Get-Item -Path WSMan:\localhost\Client\TrustedHosts -Force | Select-Object -ExpandProperty Value
            Write-Verbose -Message "The Trusted Host list currently contains: $TrustedHost"
             
            Write-Verbose -Message "Creating CimSession to DHCP Server using Domain Admin credential. Current user may not have access to the DHCP Server."
            try {
                Write-Verbose -Message "Attempting to create CimSession to the DHCP Server: $DHCPServer using WSMAN."
                $CimSession = New-CimSession -ComputerName $DHCPServer -Credential $DomainAdminCredential -ErrorAction Stop
            }
            catch {
                try {
                    Write-Verbose -Message "WSMAN failed, attempting to create CimSession to the DHCP Server: $DHCPServer using DCOM."
                    $Opt = New-CimSessionOption -Protocol Dcom
                    $CimSession = New-CimSession -ComputerName $DHCPServer -SessionOption $Opt -Credential $DomainAdminCredential -ErrorAction Stop
                }
                catch {
                    $Problem = $true
                    Write-Warning -Message "Error creating CimSession to DHCP Server: $DHCPServer. Error Details: $_.Exception.Message"                   
                }
            }
 
            Workflow Join-Domain {
             #Comment based help and advanced parameter validation are not supported in workflows: http://blogs.technet.com/b/heyscriptingguy/archive/2013/01/02/powershell-workflows-restrictions.aspx
                param(
                    [hashtable]$IPNameMatrix,
                    [string]$DomainName,
                    [pscredential]$DomainAdminCredential
                )
                    foreach -parallel ($Computer in $PSComputerName) {
 
                        #This could be done in a single command with a single reboot, but if the machine has ever been in the domain, even if it has been reverted and the computer account was removed
                        #from AD, it will cause directory service busy errors on the rename so I chose to rename the computer in one command and add it to the domain in another which requires two
                        #reboots. Here's the single command to do this: Add-Computer -DomainName $DomainName -NewName $IPNameMatrix[$Computer] -Credential $DomainAdminCredential -PSActionRetryCount 3
 
                        Rename-Computer -NewName $IPNameMatrix[$Computer] -Force
                        Restart-Computer -Wait -For WinRM -Protocol WSMan -Force
 
                        Add-Computer -DomainName $DomainName -Credential $DomainAdminCredential -PSActionRetryCount 3
                        Restart-Computer -Wait -For WinRM -Protocol WSMan -Force -PSCredential $DomainAdminCredential
 
                        #Design Note: Unlike the parallel statement, the lines within the braces of the parallel -foreach statement are treated as a unit and are invoked sequentially
                    }
            }
 
        }
        else {
            $Problem = $true
            Write-Warning -Message "PowerShell must be run as an Administrator in order to use this tool. Right click PowerShell and select 'Run as Administrator' and then try again."
        }
    }
 
    PROCESS {
        if (-not($Problem)) {
                try {
                    Write-Verbose -Message "Attempting to translate the MAC addresses to IP addresses via the DHCP Server: $DHCPServer"               
                    [array]$IPAddress+= (Get-DhcpServerv4Lease -CimSession $CimSession -ScopeId $DHCPScopeId -ClientId $MACAddress -ErrorAction Stop |
                    Select-Object -ExpandProperty IPAddress).IPAddressToString
                }
                catch {
                    $Problem = $true
                    Write-Warning -Message "Error translating MAC Addresses to IP Addresses. Error Details: $_.Exception.Message"
                }
        }
    }
 
    END {
        if (-not($Problem)) {
            foreach ($IP in $IPAddress) {
                $i++
 
                Write-Verbose -Message "Adding IPAddress: $IP and ServerName: $NewNameBase$i to the IPNameMatrix HashTable."
                $IPNameMatrix.Add($IP, "$NewNameBase$i")
                Write-Verbose -Message "IPNameMatrix now contains: $($IPNameMatrix.Count) items"
 
                Write-Verbose -Message "Adding the IP Addresses to the local computers trusted hosts list."
                Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $IP.ToString() -Concatenate -Force
            }
 
            $Params = @{
                PSComputerName = $($IPNameMatrix.Keys)
                IPNameMatrix = $IPNameMatrix
                DomainName = $DomainName
                DomainAdminCredential = $DomainAdminCredential
                PSCredential = $LocalAdminCredential
            }
 
            try {
                Write-Verbose -Message "Calling the Join-Domain Workflow."
                Join-Domain -PSParameterCollection $Params
                 
                Write-Verbose -Message "Restoring the list of trusted hosts to the state that it was in prior to running this tool to prevent a reduction in system security."
                $TrustedHost | ForEach-Object {Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $_.ToString() -Force}
            }
            catch {
                Write-Warning -Message "Please contact your system administrator. Reference error: $_.Exception.Message"
            }
 
            Write-Verbose -Message "Cleanup: Removing the single CimSession that was created by this tool since it is no longer needed."
            Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
        }
    }
}