Get-EventLog -LogName Application -Source Microsoft-Windows-Winsrv -InstanceId 10001 |
Format-Table TimeGenerated, ReplacementStrings