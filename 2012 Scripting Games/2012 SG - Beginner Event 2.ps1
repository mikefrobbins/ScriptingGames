Get-Service -ComputerName localhost | Where-Object -FilterScript {$_.Status -eq 'Running' -and $_.CanStop}
