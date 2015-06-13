Get-EventLog -ComputerName $Env:ComputerName -LogName Application -EntryType Error | Group-Object -Property Source -NoElement | Sort-Object -Property Count -Descending
