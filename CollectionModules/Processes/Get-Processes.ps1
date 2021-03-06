<#
.SYNOPSIS
	Uses Get-Process and WMI's Win32_Process class to enumerate processes, commandline arguments, and hashes.
	
.NOTES
	Author: David Howell
	Last Modified: 02/01/2016
	
OUTPUT csv
#>

if (-not(Get-Command Get-FileHash)) {
	function Get-FileHash {
		<#
		.SYNOPSIS 
			Get-FileHash calculates the hash value of the supplied file.

		.PARAMETER Path
			Path of the file to compute a hash.

		.PARAMETER Algorithm
			Type of hash to calculate (MD5, SHA1, SHA256)

		.NOTES
			Copied from Kansa module on 01/21/2015 and cleaned up by David Howell.
		#>
		[CmdletBinding()]Param(
			[Parameter(Mandatory=$True)]
			[String]$Path,
		
			[Parameter(Mandatory=$True)]
			[ValidateSet("MD5","SHA1","SHA256")]
			[String]$Algorithm
		)

		# Switch to set which Cryptography Class is needed for computation
		Switch ($HashType) {
			"MD5" { $Hash = [System.Security.Cryptography.MD5]::Create() }
			"SHA1" { $Hash = [System.Security.Cryptography.SHA1]::Create() }
			"SHA256" { $Hash = [System.Security.Cryptography.SHA256]::Create() }
		}

		# Test if the provided FilePath exists
		if (Test-Path $FilePath -ErrorAction SilentlyContinue) {
			[PSCustomObject]@{
				Algorithm = $HashType
				Hash = [System.BitConverter]::ToString($Hash.ComputeHash([System.IO.File]::ReadAllBytes($FilePath))) -replace "-",""
				Path = $Path
			}
		}
	}
}

Get-Process | ForEach-Object {
	$WMIData = Get-WmiObject -Class Win32_Process -Filter "ProcessID='$($_.ID)'" | Select-Object -Property ParentProcessID, CommandLine
	if ($_.Path) {
		$MD5 = Get-FileHash -Path $_.Path -Algorithm MD5 | Select-Object -ExpandProperty Hash
		$SHA1 = Get-FileHash -Path $_.Path -Algorithm SHA1 | Select-Object -ExpandProperty Hash
		$SHA256 = Get-FileHash -Path $_.Path -Algorithm SHA256 | Select-Object -ExpandProperty Hash
	} else { $MD5 = $null; $SHA1 = $null; $SHA256 = $null }
	[PSCustomObject]@{
		ProcessName = $_.Name
		ProcessStartTime = $_.StartTime
		ProcessExitTime = $_.ExitTime
		ProcessPath = $_.Path
		Commandline = $WMIData.CommandLine
		ProcessID = $_.ID
		ParentProcessID = $WMIData.ParentProcessID
		Handles = $_.Handles
		Company = $_.Company
		FileVersion = $_.FileVersion
		ProductVersion = $_.ProductVersion
		Description = $_.Description
		WorkingSet = $_.WorkingSet
		MachineName = $_.MachineName
		SessionID = $_.SessionID
		MD5 = $MD5
		SHA1 = $SHA1
		SHA256 = $SHA256
	}
	Remove-Variable WMIData -ErrorAction SilentlyContinue
}