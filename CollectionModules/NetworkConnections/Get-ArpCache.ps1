<#
.SYNOPSIS
	Uses arp.exe to get the arp cache from the computer and formats it for output.
	
.NOTES
	Author: David Howell
	Last Modified: 02/01/2016

OUTPUT csv
#>

# Get ARP Cache
$ARPEntries = & $env:windir\System32\arp.exe -a | Select-String -Pattern "(dynamic|static)" | ForEach-Object { $_ -replace "-" }
# For Each Entry in the ARP Cache, perform the following steps for formatting
ForEach ($ARPEntry in $ARPEntries) {
	# Split to different lines, only return lines with data in them (not blank lines)
	$ARPEntry = $ARPEntry -split " " | Where-Object { $_ }
	[PSCustomObject]@{
		IPAddress = $ARPEntry[0]
		MACAddress = $ARPEntry[1]
		Type = $ARPEntry[2]
	}
}