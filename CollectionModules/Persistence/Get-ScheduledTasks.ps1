<#
.SYNOPSIS
	Uses schtasks.exe to get the Scheduled Tasks from the computer and formats it for output.
.NOTES
	Author: David Howell
	Last Modified: 04/02/2015

OUTPUT csv
#>
& schtasks.exe /query /v /fo csv | ConvertFrom-Csv | Where-Object -FilterScript { $_.HostName -eq $Env:COMPUTERNAME }