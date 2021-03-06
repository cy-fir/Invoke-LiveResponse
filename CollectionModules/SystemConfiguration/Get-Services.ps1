<#
.SYNOPSIS
	Returns a list of services on the computer.

.NOTES
    Author: David Howell
    Last Modified: 04/02/2015
    
OUTPUT csv
#>
Get-WMIObject -Class Win32_Service -ErrorAction SilentlyContinue | Select-Object -Property Name, DisplayName, PathName, StartName, StartMode, State, ProcessID, Description