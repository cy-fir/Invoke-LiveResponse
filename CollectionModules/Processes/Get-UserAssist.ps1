<#
.SYNOPSIS
	Gets User Assist data out of each user's registry hive and parses the data.
	
.NOTES
	Author: David Howell
	Last Modified: 01/04/2016
	Thanks to Harlan Carvey: https://github.com/appliedsec/forensicscanner/blob/master/plugins/userassist.pl
	https://www.aldeid.com/wiki/Windows-userassist-keys
OUTPUT csv
#>

# Intialize empty array for results
$ResultArray=@()

function ConvertFrom-Rot13 {
	# Code pulled from http://learningpcs.blogspot.com/2012/06/powershell-v2-function-convertfrom.html
	[CmdletBinding()]Param(
	   [Parameter(Mandatory=$True,ValueFromPipeline=$True)][String]$rot13string
	)
	[String]$String=$null
	$rot13string.ToCharArray() | ForEach-Object {
		if((([int] $_ -ge 97) -and ([int] $_ -le 109)) -or (([int] $_ -ge 65) -and ([int] $_ -le 77))) {
			$String += [char] ([int] $_ + 13)
		} elseif((([int] $_ -ge 110) -and ([int] $_ -le 122)) -or (([int] $_ -ge 78) -and ([int] $_ -le 90))) {
			$String += [char] ([int] $_ - 13)
	   } else {
	      $String += $_
	  }
	}
	$String
}

# Setup HKU:\ PSDrive for us to work with
if (!(Get-PSDrive -PSProvider Registry -Name HKU -ErrorAction SilentlyContinue)) {
	New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -ErrorAction Stop | Out-Null
}

#region Parse FolderDescriptions Key
$FolderDescriptions = @()
	# Parse the FolderDescriptions registry key.
	Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions | ForEach-Object {
		$ItemInfo = Get-ItemProperty -Path ($_.Name -replace "HKEY_LOCAL_MACHINE", "HKLM:")
		$TempObject = New-Object PSObject
		$TempObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $ItemInfo.Name
		$TempObject | Add-Member -MemberType NoteProperty -Name "PSChildName" -Value $ItemInfo.PSChildName
		if ($ItemInfo.ParentFolder) {
			$TempObject | Add-Member -MemberType NoteProperty -Name "ParentFolder" -Value $ItemInfo.ParentFolder
		}
		if ($ItemInfo.RelativePath) {
			$TempObject | Add-Member -MemberType NoteProperty -Name "RelativePath" -Value $ItemInfo.RelativePath
		}
		if ($ItemInfo.Category) {
			$TempObject | Add-Member -MemberType NoteProperty -Name "Category" -Value $ItemInfo.Category
		}
		if ($ItemInfo.Roamable) {
			$TempObject | Add-Member -MemberType NoteProperty -Name "Roamable" -Value $ItemInfo.Roamable
		}
		if ($ItemInfo.PreCreate) {
			$TempObject | Add-Member -MemberType NoteProperty -Name "PreCreate" -Value $ItemInfo.PreCreate
		}
		$FolderDescriptions += $TempObject
	}
	
	# Loop through Folder Descriptions and Change the ParentFolder GUID values to the relative path
	for ($i=0; $i -lt $FolderDescriptions.Count; $i++) {
		if ($FolderDescriptions[$i].ParentFolder) {
			for ($j=0; $j -lt $FolderDescriptions.Count; $j++) {
				if ($FolderDescriptions[$i].ParentFolder -eq $FolderDescriptions[$j].PSChildName) {
					$FolderDescriptions[$i].ParentFolder = $FolderDescriptions[$j].RelativePath
				}
			}
		}
	}
	
	# Loop back through Folder Descriptions and prepend the ParentFolder paths to the relative paths
	for ($i=0; $i -lt $FolderDescriptions.Count; $i++) {
		if ($FolderDescriptions[$i].ParentFolder) {
			for ($j=0; $j -lt $FolderDescriptions.Count; $j++) {
				if ($FolderDescriptions[$i].ParentFolder -eq $FolderDescriptions[$j].Name) {
					$FolderDescriptions[$i].ParentFolder = $FolderDescriptions[$j].ParentFolder
				}
			}
			$FolderDescriptions[$i].RelativePath = $FolderDescriptions[$i].ParentFolder + "\" + $FolderDescriptions[$i].RelativePath
		}
	}

	$FolderDescriptions = $FolderDescriptions | Where-Object { $_.RelativePath }
#endregion Parse FolderDescriptions Key

# Get a listing of users in HKEY_USERS
$Users = Get-ChildItem -Path HKU:\ -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name

ForEach ($User in $Users) {
	# Rename the root of the path so we can query with it
	$UserRoot = $User -replace "HKEY_USERS","HKU:"
	# Get some User Information to determine Username
	$UserInfo = Get-ItemProperty -Path "$($UserRoot)\Volatile Environment" -ErrorAction SilentlyContinue
	$UserName = "$($UserInfo.USERDOMAIN)\$($UserInfo.USERNAME)"
	
	# Query the User Assist key for this user
	$UserAssistEntries = Get-ItemProperty -Path "$($UserRoot)\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\*\Count" -ErrorAction SilentlyContinue | ForEach-Object { $_.PSObject.Properties }
	
	# Filter out the uneeded values, then process the entries
	# Entry names are ROT13 encoded, and the values are binary and need to be parsed.
	$UserAssistEntries | Where-Object -FilterScript { $_.Name -notlike "PS*" } | ForEach-Object {
		# Quick and Easy way to create a custom object
		$CustomObject = "" | Select-Object -Property Username, File_Name, File_Path, Execution_Count, Time_Executed
		
		$CustomObject.Username = $UserName
		# Convert the Rot13 Encoded Name
		$Name = ConvertFrom-Rot13 -rot13string $_.Name
		switch -regex ($Name) {
			# Regexs created based on information found here: http://sploited.blogspot.ch/2012/12/sans-forensic-artifact-6-userassist.html
			"({1AC14E77\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = "C:\Windows\system32\" + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			
			"({6D809377\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = "C:\Program Files\" + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			
			"({7C5A40EF\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = "C:\Program Files (x86)\" + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			"({D65231B0\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = "C:\Windows\System32\" + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			
			"({B4BFCC3A\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = $UserInfo.USERPROFILE + "\Desktop\" + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			
			"({FDD39AD0\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = $UserInfo.USERPROFILE + "\Documents\" + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			
			"({374DE290\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = $UserInfo.USERPROFILE + "\Downloads\" + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			
			"({0762D272\-[A-Za-z0-9\-]+})\\(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = $UserInfo.USERPROFILE + $matches[2]
				$CustomObject.file_name = $matches[4]
			}
			
			"(([A-Za-z]:|\\\\[^\\]+)\\)(([^\\]+\\)*)(.+)" {
				$CustomObject.file_path = $matches[1] + $matches[3]
				$CustomObject.file_name = $matches[5]
			}
			
			Default {
				# Try to match the GUID against an entry in the FolderDescriptions registry key
				for ($i=0; $i -lt $FolderDescriptions.Count; $i++) {
					if ($Name -like "$($FolderDescriptions[$i].PSChildName)*") {
						if ($Name -match "$($FolderDescriptions[$i].PSChildName)\\(([^\\]+\\)*)(.+)") {
							if ($FolderDescriptions[$i].RelativePath -like "Microsoft\*") {
								$CustomObject.file_path = $UserInfo.USERPROFILE + "\AppData\Roaming\" + $FolderDescriptions[$i].RelativePath + "\" + $matches[1]
							} elseif ($FolderDescriptions[$i].RelativePath -like "\AppData\*") {
								$CustomObject.file_path = $UserInfo.USERPROFILE + "\" + $FolderDescriptions[$i].RelativePath + "\" + $matches[1]
							} else {
								$CustomObject.file_path = $FolderDescriptions[$i].RelativePath + "\" + $matches[1]
							}
							$CustomObject.file_name = $matches[3]
						}
					}
				}
				
				# If no name has been filled, just bind the name directly
				if (-not($CustomObject.file_name)) {
					$CustomObject.file_name = $Name
				}
			}
		}
		
		if ($_.Value.Length -eq 16) {
			# Entries with a length of 16 are typically from Windows XP, Vista, 2003
			$CustomObject | Add-Member -Name SessionID -MemberType NoteProperty -Value [System.BitConverter]::ToUInt32($_.Value[0..3],0)
			$CustomObject.Execution_Count = [System.BitConverter]::ToUInt32($_.Value[4..7],0)
			if ([System.BitConverter]::ToUInt64($_.Value[8..15],0) -ne 0) {
				$CustomObject.Time_Executed = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($_.Value[8..15],0).ToString("G"))
			}
		} elseif ($_.Value.Length -eq 72) {
			# Etnries with a length of 72 are typically Windows 7/Windows 2008 and above
			$CustomObject.Execution_Count = [System.BitConverter]::ToUInt32($_.Value[4..7],0)
			if ([System.BitConverter]::ToUInt64($_.Value[60..67],0) -ne 0) {
				$CustomObject.Time_Executed = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($_.Value[60..67],0).ToString("G"))
			}
		} else {
			# Ignore other values for now.
		}
		$ResultArray += $CustomObject
	}
}

$ResultArray