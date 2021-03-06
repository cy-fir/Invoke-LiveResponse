<#
.SYNOPSIS
    Gets the running processes and lists the modules being used by each process. 

.NOTES
    Modified: 02/01/2016
	
OUTPUT csv
#>

# Create an Array for our Process Modules
$ProcessModules=@()

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
	if (Test-Path $FilePath) {
		# Read the Content of the File in Bytes
		$FileinBytes=[System.IO.File]::ReadAllBytes($FilePath)
		# Use CalculateHash Method to determine hash
		$HashofBytes=$Hash.ComputeHash($FileinBytes)
		# Use BitConverter to Convert to String
		$FileHash=[System.BitConverter]::ToString($HashofBytes)
		# Remove the dashes from the hash
		$FileHash.Replace("-","")
	} else {
		Write-Host "Unable to locate File at $FilePath"
	}
}

# Use Get-Process command to list all running processes
$Processes = Get-Process -ErrorAction SilentlyContinue | Select-Object -Property Name, Path, Modules, Id
# Loop through each process and get the modules.
ForEach ($Process in $Processes) {
	$Modules=$Process.Modules | Select-Object -Property *
	# Loop through each module, compute their has, and add to the array
	ForEach ($Module in $Modules) {
		$SHA256Hash = ""
		if (Test-Path -Path $Module.FileName) {
			$SHA256Hash = Get-FileHash -FilePath $Module.FileName -HashType SHA256
		}
		[PSCustomObject]@{
			ProcessName = $Process.Name
			ProcessPath = $Process.Path
			ProcessID = $Process.Id
			ModuleName = $Module.ModuleName
			ModuleSHA256 = $SHA256Hash
			ModuleInternalName = $Module.FileVersionInfo.InternalName
			ModuleOriginalName = $Module.FileVersionInfo.OriginalFilename
			ModuleFilePath = $Module.FileName
			ModuleLanguage = $Module.FileVersionInfo.Language
			ModuleFileSize = $Module.Size
			ModuleFileDescription = $Module.Description
			ModuleFileCompany = $Module.Company
		}
	}
}