<#
.SYNOPSIS
	Uses Get-Process and WMI's Win32_Process class to enumerate processes, commandline arguments, and hashes.
	
.NOTES
	Author: David Howell
	Last Modified: 01/04/2016
	
OUTPUT csv
#>

function Get-FileHash {
    <#
    .SYNOPSIS 
        Get-FileHash calculates the hash value of the supplied file.

    .PARAMETER FilePath
        Path of the file to compute a hash.

    .PARAMETER HashType
        Type of hash to calculate (MD5, SHA1, SHA256)

    .NOTES
        Copied from Kansa module on 01/21/2015 and cleaned up by David Howell.
    #>

    [CmdletBinding()]Param(
        [Parameter(Mandatory=$True)][String]$FilePath,
        [ValidateSet("MD5","SHA1","SHA256")][String]$HashType
    )

    # Switch to set which Cryptography Class is needed for computation
    Switch ($HashType.ToUpper()) {
        "MD5" { $Hash=[System.Security.Cryptography.MD5]::Create() }
        "SHA1" { $Hash=[System.Security.Cryptography.SHA1]::Create() }
        "SHA256" { $Hash=[System.Security.Cryptography.SHA256]::Create() }
    }

    # Test if the provided FilePath exists
    if (Test-Path $FilePath -ErrorAction SilentlyContinue) {
        # Read the Content of the File in Bytes
        $FileinBytes=[System.IO.File]::ReadAllBytes($FilePath)
        # Use CalculateHash Method to determine hash
        $HashofBytes=$Hash.ComputeHash($FileinBytes)
        # Use BitConverter to Convert to String
        $FileHash=[System.BitConverter]::ToString($HashofBytes)
        # Remove the dashes from the hash
        $FileHash.Replace("-","")
    } else {
    	# Unable to locate File at $FilePath
    }
}

$Processes = @()
Get-Process | ForEach-Object {
	$WMIData = Get-WmiObject -Class Win32_Process -Filter "ProcessID='$($_.ID)'" | Select-Object -Property ParentProcessID, CommandLine
	$TempObject = New-Object PSObject
	$TempObject | Add-Member -MemberType NoteProperty -Name "Process_Name" -Value $_.Name
	$TempObject | Add-Member -MemberType NoteProperty -Name "Process_Start_Time" -Value $_.StartTime
	$TempObject | Add-Member -MemberType NoteProperty -Name "Process_Exit_Time" -Value $_.ExitTime
	$TempObject | Add-Member -MemberType NoteProperty -Name "Process_Path" -Value $_.Path
	$TempObject | Add-Member -MemberType NoteProperty -Name "CommandLine" -Value $WMIData.CommandLine
	$TempObject | Add-Member -MemberType NoteProperty -Name "Process_ID" -Value $_.ID
	$TempObject | Add-Member -MemberType NoteProperty -Name "Parent_Process_ID" -Value $WMIData.ParentProcessID
	$TempObject | Add-Member -MemberType NoteProperty -Name "Handles" -Value $_.Handles
	$TempObject | Add-Member -MemberType NoteProperty -Name "Company" -Value $_.Company
	$TempObject | Add-Member -MemberType NoteProperty -Name "File_Version" -Value $_.FileVersion
	$TempObject | Add-Member -MemberType NoteProperty -Name "Product_Version" -Value $_.ProductVersion
	$TempObject | Add-Member -MemberType NoteProperty -Name "Description" -Value $_.Description
	$TempObject | Add-Member -MemberType NoteProperty -Name "WorkingSet" -Value $_.WorkingSet
	$TempObject | Add-Member -MemberType NoteProperty -Name "MachineName" -Value $_.MachineName
	$TempObject | Add-Member -MemberType NoteProperty -Name "SessionID" -Value $_.SessionID
	if ($_.Path -ne $null -and $_.Path -ne "") {
        $TempObject | Add-Member -MemberType NoteProperty -Name "MD5" -Value (Get-FileHash -FilePath $_.Path -HashType MD5)
		$TempObject | Add-Member -MemberType NoteProperty -Name "SHA1" -Value (Get-FileHash -FilePath $_.Path -HashType SHA1)
		$TempObject | Add-Member -MemberType NoteProperty -Name "SHA256" -Value (Get-FileHash -FilePath $_.Path -HashType SHA256)
    }
	$Processes += $TempObject
	Remove-Variable TempObject
	Remove-Variable WMIData -ErrorAction SilentlyContinue
}

$Processes | Select-Object -Property Process_Name, Process_Start_Time, Process_Exit_Time, Process_Path, CommandLIne, Process_ID, Parent_Process_ID, MD5, SHA1, SHA256, Handles, Company, File_Version, Product_Version, Description, WorkingSet, MachineName, SessionID