Get-WinEvent -ListLog * -Force -ErrorAction SilentlyContinue | Where-Object {$_.RecordCount -and $_.IsEnabled} | Sort-Object RecordCount -Descending | Format-Table -Property LogName, RecordCount -Wrap


