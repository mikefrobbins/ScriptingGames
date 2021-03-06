$win32os = Get-WmiObject -Class Win32_OperatingSystem 
$now = ($win32os.ConvertToDateTime($win32os.LocalDateTime))
$lastboot = ($win32os.ConvertToDateTime($win32os.LastBootupTime))
$uptime = $now - $lastboot 
Write-Output "The computer $($win32os.csname) has been up for $($uptime.days) days $($uptime.hours) hours $($uptime.minutes) minutes, $($uptime.seconds) seconds as of $($now.tostring('G'))"