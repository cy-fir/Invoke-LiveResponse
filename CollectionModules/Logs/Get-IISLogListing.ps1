<#
.SYNOPSIS
	Looks for IIS registry key noting log path (if it exists), then returns a list of logs from the path.

.NOTES
	Author: David Howell
	Last Modified: 04/02/2015
	I was going to have it return all of the logs in a zip file, but there could be complications when trying to create a .ZIP of a large amount of logs (gigabytes) and could cause a server to crash.

OUTPUT csv
#>

# Look for the W3 Service registry entry to determine if IIS is installed
if ((Get-ItemProperty HKLM:\Software\Microsoft\Inetstp\Components -ErrorAction SilentlyContinue).W3SVC) {
	# Initialize array to store Log File Info
	$IISLogs=@()
	Try {
	# Try to Import the WebAdministration Module and use it to find the IIS Log Paths
		Import-Module WebAdministration -ErrorAction Stop
		
		# List the Sites in IIS, and get the log path for each
		Get-ChildItem -Path IIS:\\Sites -ErrorAction Stop | ForEach-Object {
			# If the Log Path has %SystemDrive% in it, rename it to $Env:SystemDrive to work with PowerShell
			if ($_.logFile.Directory -like "%SystemDrive%*") {
				$TempLocation = $_.logFile.Directory -replace "%SystemDrive%", "$Env:SystemDrive"
				$IISLogs+=Get-ChildItem -Path $TempLocation -Recurse -Filter *.log -Force | Select-Object -Property FullName, Length, CreationTimeUtc, LastAccessTimeUtc, LastWriteTimeUtc
			} else {
				$IISLogs+=Get-ChildItem -Path $_.logFile.Directory -Recurse -Filter *.log -Force | Select-Object -Property FullName, Length, CreationTimeUtc, LastAccessTimeUtc, LastWriteTimeUtc
			}
		}
	} Catch {
	# WebAdministration Module didn't work, try to get the logs manually
		# Use WMI to list the local disks, then check each one to see if wwwroot exists and look for the log files in those directories
		Get-WmiObject -Class Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq "Local Fixed Disk" } | ForEach-Object {
			if (Test-Path -Path "$($_.DeviceID)\inetpub\logs\LogFiles" -ErrorAction SilentlyContinue) {
				$IISLogs+=Get-ChildItem -Path "$($_.DeviceID)\inetpub\logs\LogFiles" -Recurse -Filter *.log -Force -ErrorAction SilentlyContinue | Select-Object -Property FullName, Length, CreationTimeUtc, LastAccessTimeUtc, LastWriteTimeUtc
			}
		}
	}
	$IISLogs | Select-Object -Property FullName, Length, CreationTimeUtc, LastAccessTimeUtc, LastWriteTimeUtc
} else {
	# IIS doesn't appear to be installed on $Env:COMPUTERNAME.
}