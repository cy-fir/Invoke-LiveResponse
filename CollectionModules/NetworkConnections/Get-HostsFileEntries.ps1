<#
.SYNOPSIS
	Checks for entries in the hosts file, parses them and returns a custom object.

.NOTES
    Author: David Howell
    Last Modified: 02/01/2016
    
OUTPUT csv
#>

if (Test-Path -Path $Env:windir\System32\drivers\etc\hosts) {
	# Get the Content of the Hosts file, but ignore all the Comment lines and Blank lines
	Get-Content -Path $Env:windir\System32\drivers\etc\hosts | Select-String -Pattern "^(?!(#)).+" | ForEach-Object {
		# Use regex to parse the 2, or possibly 3 groups of information in a line:
		#  IP Address - Host Name - Comments
		if ($_ -match "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\s+([^\s]+)\s+(#.+)?") {
			[PSCustomObject]@{
				IPAddress = $Matches[1]
				Hostname = $Matches[2]
				Comments = $Matches[3]
			}
		}
	}
}