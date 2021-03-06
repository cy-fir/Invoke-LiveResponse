<#
.SYNOPSIS
	Looks for JavaCache files on the system and parses important data from those files.

.NOTES
    Author: David Howell
    Last Modified: 02/01/2016
	Thanks to: http://www.forensicswiki.org/wiki/Java
    
OUTPUT csv
#>

#Get User Profiles on the System
$UserProfiles = Get-WMIObject -Class Win32_UserProfile -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPath | Where-Object { $_ -like "C:\Users\*" -or $_ -like "C:\Windows\system32\config\systemprofile"}

# Initialize ASCII Encoding to convert Byte Array data to ASCII
$ASCIIEncoding = New-Object System.Text.ASCIIEncoding

# Check the Java Cache for Each Profile
ForEach ($UserProfile in $UserProfiles) {
	# Look for .idx files, and process each one
	$IDXFiles = Get-ChildItem -Path "$UserProfile\AppData\LocalLow\Sun\Java\Deployment\cache\" -Filter *.idx -ErrorAction SilentlyContinue | Select-Object -Property FullName, Length, CreationTimeUtc, LastAccessTimeUtc, LastWriteTimeUtc
	ForEach ($IDXFile in $IDXFiles) {
		# Read the IDX file into a Byte Array
		[Byte[]]$ByteArray = [System.IO.File]::ReadAllBytes($IDXFile.FullName)
		$MemoryStream = New-Object System.IO.MemoryStream (,$ByteArray)
		$BinReader = New-Object System.IO.BinaryReader $MemoryStream
		
		$BinReader.ReadBytes(2) | Out-Null
		$JavaCacheVersion = [Convert]::ToUInt32(([BitConverter]::ToString($BinReader.ReadBytes(4)) -replace "-",""),16)
		
		# 605 and 603/604 Have the same structure other than a few bytes at the beginning
		switch ($JavaCacheVersion) {
			"605" {
				$BinReader.ReadByte() | Out-Null # IsShortcutImage Flag
			}
			
			"(602|603|604)" {
				$BinReader.ReadBytes(2) | Out-Null # Not Used
				$BinReader.ReadByte() | Out-Null # IsShortcutImage Flag
			}
		}
		
		$ContentLength = [Convert]::ToUInt32(([BitConverter]::ToString($BinReader.ReadBytes(4)) -replace "-",""),16)
		$ModifiedTime = ([DateTime]"1/1/1970").AddMilliseconds([Convert]::ToUInt64(([BitConverter]::ToString($BinReader.ReadBytes(8)) -replace "-",""),16))
		$ExpiredTime = ([DateTime]"1/1/1970").AddMilliseconds([Convert]::ToUInt64(([BitConverter]::ToString($BinReader.ReadBytes(8)) -replace "-",""),16))
		$ValidationTime = ([DateTime]"1/1/1970").AddMilliseconds([Convert]::ToUInt64(([BitConverter]::ToString($BinReader.ReadBytes(8)) -replace "-",""),16))
		
		switch ($JavaCacheVersion) {
			"602" {
				$VersionStringLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
				$VersionString = $ASCIIEncoding.GetString($BinReader.ReadBytes($VersionStringLength))
				$URLStringLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
				$URLString = $ASCIIEncoding.GetString($BinReader.ReadBytes($URLStringLength))
				$NamespaceIDStringLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
				$NamespaceIDString = $ASCIIEncoding.GetString($BinReader.ReadBytes($NamespaceIDStringLength))
				
				$HTTPHeadercount = [Convert]::ToUInt32(([BitConverter]::ToString($BinReader.ReadBytes(4)) -replace "-",""),16)
				$HTTPHeaderArray = @()
				for ($i=0; $i -lt $HTTPHeadercount; $i++) {
					$HeaderNameLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
					$HeaderName = $ASCIIEncoding.GetString($BinReader.ReadBytes($HeaderNameLength))
					$HeaderValueLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
					$HeaderValue = $ASCIIEncoding.GetString($BinReader.ReadBytes($HeaderValueLength))
				}
				
			}
			
			"(603|604|605)" {
				$BinReader.ReadByte() | Out-Null # Flag - Known to be signed
				$Section2Length = [Convert]::ToUInt32(([BitConverter]::ToString($BinReader.ReadBytes(4)) -replace "-",""),16)
				$BinReader.ReadBytes(4) | Out-Null # Section 3 Length
				$BinReader.ReadBytes(4) | Out-Null # Section 4 Length
				$BinReader.ReadBytes(4) | Out-Null # Section 5 Length
				$BlacklistValidationTime = ([DateTime]"1/1/1970").AddMilliseconds([Convert]::ToUInt64(([BitConverter]::ToString($BinReader.ReadBytes(8)) -replace "-",""),16))
				$CertExpirationTime = ([DateTime]"1/1/1970").AddMilliseconds([Convert]::ToUInt64(([BitConverter]::ToString($BinReader.ReadBytes(8)) -replace "-",""),16))
				$BinReader.ReadByte() | Out-Null # Class Verification Status
				$BinReader.ReadBytes(4) | Out-Null # Reduced Manifest Length
				$BinReader.ReadBytes(4) | Out-Null # Section 4 pre15 Length
				$BinReader.ReadByte() | Out-Null # Flag - Has only signed entries
				$BinReader.ReadByte() | Out-Null # Flag - Has single code source
				$BinReader.ReadBytes(4) | Out-Null # Section 4 Certs Length
				$BinReader.ReadBytes(4) | Out-Null # Section 4 Signers Length
				$BinReader.ReadByte() | Out-Null # Flag - Has missing signed entries
				$BinReader.ReadBytes(8) | Out-Null # Trusted Libraries Validation Time
				$BinReader.ReadBytes(4) | Out-Null # Reduced Manifest2 Length
				$BinReader.ReadByte() | Out-Null # Flag - Is proxied
				
				#region Section 2
				$MemoryStream.Position = 128
				$VersionStringLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
				$VersionString = $ASCIIEncoding.GetString($BinReader.ReadBytes($VersionStringLength))
				$URLStringLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
				$URLString = $ASCIIEncoding.GetString($BinReader.ReadBytes($URLStringLength))
				$NamespaceIDStringLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
				$NamespaceIDString = $ASCIIEncoding.GetString($BinReader.ReadBytes($NamespaceIDStringLength))
				$CodebaseIPStringLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
				$CodebaseIPString = $ASCIIEncoding.GetString($BinReader.ReadBytes($CodebaseIPStringLength))
				$HTTPHeadercount = [Convert]::ToUInt32(([BitConverter]::ToString($BinReader.ReadBytes(4)) -replace "-",""),16)
				$HTTPHeaderArray = @()
				for ($i=0; $i -lt $HTTPHeadercount; $i++) {
					$HeaderNameLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
					$HeaderName = $ASCIIEncoding.GetString($BinReader.ReadBytes($HeaderNameLength))
					$HeaderValueLength = [Convert]::ToUInt16(([BitConverter]::ToString($BinReader.ReadBytes(2)) -replace "-",""),16)
					$HeaderValue = $ASCIIEncoding.GetString($BinReader.ReadBytes($HeaderValueLength))
					$HTTPHeaderArray += $HeaderName + ": " + $HeaderValue
				}
				#endregion Section 2
			}
		}
		
		[PSCustomObject]@{
			AppVersion = $VersionString
			AppURL = $URLString
			AppNamespaceID = $NamespaceIDString
			AppCodebase = $CodebaseIPString
			AppHTTPHeaders = $HTTPHeaderArray -join ", "
			JavaCacheVersion = $JavaCacheVersion
			AppContentLength = $ContentLength
			AppModifiedTime = $ModifiedTime
			IDXFilePath = $IDXFile.FullName
			IDXCreatedTime = $IDXFile.CreationTime
			IDXAccessedTime = $IDXFile.LastAccessTime
			IDXModifiedTime = $IDXFile.LastWriteTime
			AppExpiredTime = $ExpiredTime
			AppValidationTime = $ValidationTime
			AppBlacklistValidationTime = $BlacklistValidationTime
			AppCertExpirationTime = $CertExpirationTime
		}
	}
}