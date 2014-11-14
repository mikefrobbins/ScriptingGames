#Requires -Version 3.0
function New-UserAuditReport {
 
<#
.SYNOPSIS
Creates a report of specific properties for random Active Directory users in HTM or HTML format to be used for
auditing purposes. 
.DESCRIPTION
    New-UserAuditReport is a function that creates a htm or html report for a random number of active directory
user accounts. The specific information that is on the report is: user name, department, title, date
and time for the last interactive, network, or service logon, date and time of last password change, and
whether or not the account is disabled or locked out. The ActiveDirectory PowerShell module is not required,
but it is attempted first via an external reusable function and then ADSI is attempted via another reusable
external function if this function experiences an issue with the Active Directory PowerShell module.
    The LastLogonTimestamp property was chosen because the other possible attributes are bot replicated to all
the domain controllers in the domain and each one would need to be queried as discussed in this blog article:
http://blogs.technet.com/b/askds/archive/2009/04/15/the-lastlogontimestamp-attribute-what-it-was-designed-for-and-how-it-works.aspx
    The pwdLastSet property was chosen to provide consistency on what is returned by Get-ADUser and ADSI. 
.PARAMETER Records
The number of random Active Directory user records to retrieve.
.PARAMETER Path
The folder or directory to place the htm or html file in. The default is the current user's temporary directory.
.PARAMETER FileName
The file name that will be used to save the report as. Only valid file names with a .htm or .html file extension
are accepted.
.PARAMETER Force
Switch parameter that when specified overwrites the destination file if it already exists.
.EXAMPLE
New-UserAuditReport -FileName AuditReport.htm
.EXAMPLE
New-UserAuditReport -Records 10 -FileName AuditReport.html
.EXAMPLE
New-UserAuditReport -Records 15 -Path c:\tmp -FileName MyAuditReport.htm
.EXAMPLE
New-UserAuditReport -Records 25 -Path c:\tmp -FileName MyAuditReport.htm -Force
.INPUTS
None
.OUTPUTS
None
#>
 
    [CmdletBinding()]
    param(
        [ValidateNotNullorEmpty()]
        [int]$Records = 20,
 
        [ValidateNotNullorEmpty()]
        [ValidateScript({Test-Path $_ -PathType 'Container'})]
        [string]$Path = $Env:TEMP,
 
        [Parameter(Mandatory=$True)]
        [ValidatePattern("^(?!^(PRN|AUX|CLOCK\$|NUL|CON|COM\d|LPT\d|\..*)(\..+)?$)[^\x00-\x1f\\?*:\"";|/]+\.html?$")]
        [string]$FileName,
 
        [switch]$Force
    )
 
    $Params = @{
        Records = $Records
        ErrorAction = 'Stop'
        ErrorVariable = 'Issue'
    }
 
    $Problem = $false
 
    Try {
        Write-Verbose -Message "Attempting to use the Active Directory PowerShell Module"
        $Users = Get-ADRandomUser @Params
    }
    catch {
 
        try {
            Write-Verbose -Message "Failure when attempting to use the Active Directory PowerShell Module, now attempting to use ADSI"
            $Users = Get-ADSIRandomUser @Params
        }
        catch {
            $Problem = $True
            Write-Warning -Message "$Issue.Exception.Message"
        }
 
    }
     
    If (-not($Problem)) {
 
Write-Verbose -Message "Defining GreenBar CSS Style"
$GreenBarStyle = @"
    <style>
    body {
        color:#333333;
        font-family:"Lucida Grande", verdana, sans-serif;
        font-size: 10pt;
    }
    h1 {
        text-align:center;
    }
    h2 {
        border-top:2px solid #4e9a06;
    }
 
    th {
        font-weight:bold;
        color:#eeeeee;
        background-color:#4e9a06;
    }
    .odd  { background-color:#ffffff; }
    .even { background-color:#e4ffc7; }
    </style>
"@
         
        Write-Verbose -Message "Defining auditor friendly dates, property names, converting to HTMl fragment, and applying CSS."
        $UsersHTML = $Users | Select-Object -Property @{
                                 Label='UserName';Expression ={$_.samaccountname}},
                                 Department,
                                 Title,
                                 @{Label='LastLogin';Expression ={([datetime]::fromfiletime([int64]::Parse($_.lastlogontimestamp)))}},
                                 @{Label='PasswordLastChanged';Expression ={([datetime]::fromfiletime([int64]::Parse($_.pwdlastset)))}},
                                 @{Label='IsDisabled';Expression ={(-not($_.enabled))}},
                                 @{Label='IsLockedOut';Expression ={$_.lockedout}} |
                              ConvertTo-Html -Fragment |
                              Out-String |
                              Set-AlternatingCSS -CSSEvenClass 'even' -CssOddClass 'odd'
 
        $HTMLParams = @{
            'Head'="<title>Random User Audit Report</title>$GreenBarStyle"
            'PreContent'="<H2>Random User Audit Report for $Records Users</H2>"
            'PostContent'= "$UsersHTML <HR> $(Get-Date)"
        }
 
        $Params.Remove("Records")
 
        Try {
            Write-Verbose -Message "Attempting to build filepath. The regular expression in the params block validated that the file name is valid on a windows system."
            $FilePath = Join-Path -Path $Path -ChildPath "$($FileName.ToLower())" @Params
             
            Write-Verbose -Message "Converting to HTML and creating the file."
            ConvertTo-Html @HTMLParams @Params |
            Out-File -FilePath $FilePath -NoClobber:(-not($Force)) @Params
        }
        catch {
            Write-Warning -Message "Use the -Force parameter to overwrite the existing file. Error details: $Issue.Message.Exception"      
        }
    }
 
 
}
 
function Get-ADRandomUser {
#Requires -Modules ActiveDirectory
 
<#
.SYNOPSIS
Returns a list of specific properties for random Active Directory users using the Active Directory PowerShell Module. 
.DESCRIPTION
Get-ADRandomUser is a function that retrieves a list of random active directory users using the Active Directory
PowerShell module. The results are returned as objects for reusability.
.PARAMETER Records
The number of random Active Directory user records to retrieve.
.EXAMPLE
Get-ADRandomUser -Records 20
.INPUTS
None
.OUTPUTS
Selected.Microsoft.ActiveDirectory.Management.ADUser
#>
 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [int]$Records
    )
 
    $Params = @{
        Filter = '*'
        Properties = 'SamAccountName',
                     'Department',
                     'Title',
                     'LastLogonTimestamp',
                     'pwdLastSet',
                     'Enabled',
                     'LockedOut'
        ErrorAction = 'Stop'
        ErrorVariable = 'Issue'
    }
 
    try {
        Write-Verbose -Message "Attempting to import the Active Directory Get-ADUser cmdlet."
        Import-Module -Name ActiveDirectory -Cmdlet Get-ADUser -ErrorAction Stop -ErrorVariable Issue
     
        Write-Verbose -Message "Attempting to query Active Directory using the Get-ADUser cmdlet"
        $RandomUsers = Get-ADUser @Params |
                       Get-Random -Count $Records
 
        $Params.Property = $Params.Properties
        $Params.Remove("Properties")
        $Params.Remove("Filter")
         
        $RandomUsers | Select-Object @Params
                        
    }
    catch {
        Write-Warning -Message "$Issue.Message.Exception"
    }
 
}
 
function Get-ADSIRandomUser {
#Requires -Version 3.0
 
<#
.SYNOPSIS
Returns a list of specific properties for random Active Directory users using ADSI. 
.DESCRIPTION
Get-ADSIRandomUser is a function that retrieves a list of random active directory users using ADSI (Active Directory
Service Inferfaces). The results are returned as objects for reusability. This function does not depend on the
Active Directory PowerShell module.
.PARAMETER Records
The number of random Active Directory user records to retrieve.
.EXAMPLE
Get-ADSIRandomUser -Records 20
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
#>
 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [int]$Records
    )
 
    try {
        $searcher=[adsisearcher]'(&(objectCategory=user)(objectClass=user))'
     
        $props=@(
            'samaccountname',
            'department',
            'title',
            'lastlogontimestamp',
            'pwdlastset',
            'useraccountcontrol',
            'islockedout'
        )
 
        $searcher.PropertiesToLoad.AddRange($props)
        $RandomUsers = $searcher.FindAll() |
                       Get-Random -Count $Records
    }
    catch {
        Write-Warning -Message "Error retrieving active directory user information using ADSI"
    }
 
    foreach ($user in $RandomUsers) {
 
        [pscustomobject][ordered]@{
            SamAccountName = $($user.Properties.samaccountname)
            Department = $($user.Properties.department)
            Title=$($user.Properties.title)
            LastLogonTimestamp=$($user.Properties.lastlogontimestamp)
            pwdLastSet=$($user.Properties.pwdlastset)
            Enabled = (-not($($user.GetDirectoryEntry().InvokeGet('AccountDisabled'))))
            LockedOut = $($user.GetDirectoryEntry().InvokeGet('IsAccountLocked'))
        }
 
    }
 
}
 
function Set-AlternatingCSS {
 
<#
.SYNOPSIS
Setup an alternating cascading style sheet. 
.DESCRIPTION
The Set-AlternatingCSS function is a modified version of a function from Don Jones's "Creating HTML Reports in PowerShell"
book. Visit http://powershellbooks.com for details about this free ebook (Thank You Don!).
.PARAMETER HTMLFragment
The HTML fragment created with the ConvertTo-Html cmdlet that you wish to apply the alternating CSS to.
.PARAMETER CSSEvenClass
The CSS to apply to the even rows within the table.
.PARAMETER CssOddClass
The CSS to apply to the odd rows within the table.
.EXAMPLE
Set-AlternatingCSS -HTMLFragment ('My HTML' | ConvertTo-Html -Fragment | Out-String) -CSSEvenClass 'even' -CssOddClass 'odd'
.EXAMPLE
'My HTML' | ConvertTo-Html -Fragment | Out-String |Set-AlternatingCSS -CSSEvenClass 'even' -CssOddClass 'odd'
.INPUTS
String
.OUTPUTS
String
#>
 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True,
                   ValueFromPipeline=$True)]
        [string]$HTMLFragment,
         
        [Parameter(Mandatory=$True)]
        [string]$CSSEvenClass,
         
        [Parameter(Mandatory=$True)]
        [string]$CssOddClass
    )
 
    [xml]$xml = $HTMLFragment
    $Table = $xml.SelectSingleNode('table')
    $Classname = $CSSOddClass
 
    foreach ($tr in $Table.tr) {
        if ($Classname -eq $CSSEvenClass) {
            $Classname = $CssOddClass
        } else {
            $Classname = $CSSEvenClass
        }
        $Class = $xml.CreateAttribute('class')
        $Class.value = $Classname
        $tr.attributes.append($Class) | Out-Null
    }
 
    $xml.innerxml | Out-String
}