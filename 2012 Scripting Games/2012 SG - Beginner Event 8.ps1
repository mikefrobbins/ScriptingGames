function Get-HardwareType {

<#

.SYNOPSIS
Get-HardwareType is used to determine if a computer is a laptop of desktop.

.DESCRIPTION
Get-HardwareType is used to determine a computer's hardware type. It returns the computer
name and whether or not a computer is a laptop or a desktop.

#>

    $hardwaretype = Get-WmiObject -Class Win32_ComputerSystem -Property PCSystemType
        If ($hardwaretype -ne 2)
        {
        return $true
        }
        Else
        {
        return $false
        }}

If (Get-HardwareType)
{
"$Env:ComputerName is a Desktop"
}
Else
{
"$Env:ComputerName is a Laptop"
}
