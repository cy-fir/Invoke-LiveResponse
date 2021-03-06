<#
.SYNOPSIS
	Reads AppCompatCache registry key and parses the data.

.NOTES
	Author:  David Howell
	Last Updated: 02/01/2016
	Thanks to Mandiant's WhitePaper: https://dl.mandiant.com/EE/library/Whitepaper_ShimCacheParser.pdf
	Thanks to Harlan Carvey's Perl AppCompatCache.pl script:  https://github.com/keydet89/RegRipper2.8/blob/master/plugins/appcompatcache.pl
OUTPUT csv
#>

# Initialize Array to store our data
$EntryArray=@()
$AppCompatCache=$Null

if (!(Get-PSDrive -Name HKLM -PSProvider Registry -ErrorAction SilentlyContinue)) {
	New-PSDrive -Name HKLM -PSProvider Registry -Root HKEY_LOCAL_MACHINE -ErrorAction SilentlyContinue | Out-Null
	Write-Verbose -Message "Creating a PSDrive to access HKLM"
}

# Retrieve data in the AppCompatCache
if (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\AppCompatCache\' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty AppCompatCache) {
	$AppCompatCache = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\AppCompatCache\' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty AppCompatCache
} else {
	$AppCompatCache = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\AppCompatibility\AppCompatCache' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty AppCompatCache
}

if ($AppCompatCache) {
	# Initialize a Memory Stream and Binary Reader to scan through the Byte Array
	$MemoryStream = New-Object System.IO.MemoryStream(,$AppCompatCache)
	$BinReader = New-Object System.IO.BinaryReader $MemoryStream
	$UnicodeEncoding = New-Object System.Text.UnicodeEncoding

	# First 4 bytes - Header
	$Header = ([System.BitConverter]::ToString($AppCompatCache[0..3])) -replace "-",""

	switch ($Header) {
		# 0x30 - Windows 10
		"30000000" {
			$MemoryStream.Position = 48
			
			# Complete loop to parse each entry
			while ($MemoryStream.Position -lt $MemoryStream.Length) {
				$Tag = [System.BitConverter]::ToString($BinReader.ReadBytes(4)) -replace "-",""

				$BinReader.ReadBytes(4) | Out-Null
				$SZ = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
				$NameLength = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
				$Name = $UnicodeEncoding.GetString($BinReader.ReadBytes($NameLength))
				$Time = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
				$DataLength = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
				$Data = $UnicodeEncoding.GetString($BinReader.ReadBytes($DataLength))
				[PSCustomObject]@{
					Name = $Name
					ModifiedTime = $Time
					Data = $Data
				}
			}
		}
	
		# 0x80 - Windows 8
		"80000000" {
			$Offset = [System.BitConverter]::ToUInt32($AppCompatCache[0..3],0)
			$AppCompatTag = [System.BitConverter]::ToString($AppCompatCache[$Offset..($Offset+3)],0) -replace "-",""
			
			if ($AppCompatTag -eq "30307473" -or $AppCompatTag -eq "31307473") {
				# 64-bit Tag
				$MemoryStream.Position = ($Offset)
				
				# Complete loop to parse each entry
				while ($MemoryStream.Position -lt $MemoryStream.Length) {
					# I've noticed some random gaps of space in Windows 8 AppCompatCache.
					# To remedy, I verify the tag for each entry and scan forward for the next tag if whitespace is found
					
					# First 4 Bytes is the Tag
					$EntryTag = [System.BitConverter]::ToString($BinReader.ReadBytes(4),0) -replace "-",""
					
					if ($EntryTag -eq "30307473" -or $EntryTag -eq "31307473") {
						$BinReader.ReadBytes(4) | Out-Null
						$JMP = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
						$SZ = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
						$Name = $UnicodeEncoding.GetString($BinReader.ReadBytes($SZ + 2))
						$BinReader.ReadBytes(8) | Out-Null
						$Time = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
						$BinReader.ReadBytes(4) | Out-Null
						
						[PSCustomObject]@{
							Name = $Name
							Time = $Time
						}
					} else {
						# We've found a gap of space that isn't an AppCompatCache Entry
						# Perform a loop to read 1 byte at a time until we find the tag 30307473 or 31307473 again
						$Exit = $False
						
						while ($Exit -ne $true) {
							$Byte1 = [System.BitConverter]::ToString($BinReader.ReadBytes(1),0) -replace "-",""
							if ($Byte1 -eq "30" -or $Byte1 -eq "31") {
								$Byte2 = [System.BitConverter]::ToString($BinReader.ReadBytes(1),0) -replace "-",""
								if ($Byte2 -eq "30") {
									$Byte3 = [System.BitConverter]::ToString($BinReader.ReadBytes(1),0) -replace "-",""
									if ($Byte3 -eq "74") {
										$Byte4 = [System.BitConverter]::ToString($BinReader.ReadBytes(1),0) -replace "-",""
										if ($Byte4 -eq "73") {
											# Verified a correct tag for a new entry
											# Scroll back 4 bytes and exit the scan loop
											$MemoryStream.Position = ($MemoryStream.Position - 4)
											$Exit = $True
										} else {
											$MemoryStream.Position = ($MemoryStream.Position - 3)
										}
									} else {
										$MemoryStream.Position = ($MemoryStream.Position - 2)
									}
								} else {
									$MemoryStream.Position = ($MemoryStream.Position - 1)
								}
							}
						}
					}
				}
				
			} elseif ($AppCompatTag -eq "726F7473") {
				# 32-bit
				
				$MemoryStream.Position = ($Offset + 8)
				
				# Complete loop to parse each entry
				while ($MemoryStream.Position -lt $MemoryStream.Length) {
					$JMP = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
					$Time = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
					$SZ = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
					$Name = $UnicodeEncoding.GetString($BinReader.ReadBytes($SZ))
					[PSCustomObject]@{
						Name = $Name
						Time = $Time
					}
				}
			}
		}

		# BADC0FEE in Little Endian Hex - Windows 7 / Windows 2008 R2
		"EE0FDCBA" {
			# Number of Entries at Offset 4, Length of 4 bytes
			$NumberOfEntries = [System.BitConverter]::ToUInt32($AppCompatCache[4..7],0)
			
			# Move BinReader to the Offset 128 where the Entries begin
			$MemoryStream.Position=128
			
			# Get some baseline info about the 1st entry to determine if we're on 32-bit or 64-bit OS
			$Length = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
			$MaxLength = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
			$Padding = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
			
			# Move Binary Reader back to the start of the entries
			$MemoryStream.Position=128
			
			if (($MaxLength - $Length) -eq 2) {
				if ($Padding -eq 0) {
					# 64-bit Operating System
					
					# Use the Number of Entries it says are available and iterate through this loop that many times
					for ($i=0; $i -lt $NumberOfEntries; $i++) {
						$StartOfEntry = $MemoryStream.Position
						$Length = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
						$BinReader.ReadBytes(2) | Out-Null # MaxLength
						$BinReader.ReadBytes(4) | Out-Null # Padding
						$Offset0 = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
						$BinReader.ReadBytes(4) | Out-Null # Offset 1
						$TimeModified = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
						$MemoryStream.Position = $StartOfEntry + $Offset0
						[PSCustomObject]@{
							Name = $UnicodeEncoding.GetString($BinReader.ReadBytes($Length)) -replace "\\\?\?\\",""
							ModifiedTime = $TimeModified
						}
						$MemoryStream.Position = $StartOfEntry + 48
					}
				} else {
					# 32-bit Operating System
					
					# Use the Number of Entries it says are available and iterate through this loop that many times
					for ($i=0; $i -lt $NumberOfEntries; $i++) {
						$StartOfEntry = $MemoryStream.Position
						$Length = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
						$BinReader.ReadBytes(2) | Out-Null # Max Length
						$Offset = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
						$TimeModified = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
						$MemoryStream.Position = $StartOfEntry + $Offset
						[PSCustomObject]@{
							Name = $UnicodeEncoding.GetString($BinReader.ReadBytes($Length)) -replace "\\\?\?\\",""
							ModifiedTime = $TimeModified
						}
						$MemoryStream.Position = $StartOfEntry + 32
					}
				}
			}
		}
		
		# BADC0FFE in Little Endian Hex - Windows Server 2003 through Windows Vista and Windows Server 2008
		"FE0FDCBA" {
			# Number of Entries at Offset 4, Length of 4 bytes
			$NumberOfEntries = [System.BitConverter]::ToUInt32($AppCompatCache[4..7],0)
			
			# Lets analyze the padding of the first entry to determine if we're on 32-bit or 64-bit OS
			$Padding = [System.BitConverter]::ToUInt32($AppCompatCache[12..15],0)
			
			# Move BinReader to the Offset 8 where the Entries begin
			$MemoryStream.Position=8
			
			if ($Padding -eq 0) {
				# 64-bit Operating System
				
				# Use the Number of Entries it says are available and iterate through this loop that many times
				for ($i=0; $i -lt $NumberOfEntries; $i++) {
					$StartOfEntry = $MemoryStream.Position
					$Length = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
					$BinReader.ReadBytes(2) | Out-Null # Max Length
					$BinReader.ReadBytes(4) | Out-Null # Padding
					$Offset0 = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
					$BinReader.ReadBytes(4) | Out-Null # Offset1
					$Time = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
					$MemoryStream.Position = $StartOfEntry + $Offset0
					[PSCustomObject]@{
						Name = $UnicodeEncoding.GetString($BinReader.ReadBytes($Length)) -replace "\\\?\?\\",""
						ModifiedTime = $TimeModified
					}
					$MemoryStream.Position = $StartOfEntry + 32
				}
			
			} else {
				# 32-bit Operating System
				
				# Use the Number of Entries it says are available and iterate through this loop that many times
				for ($i=0; $i -lt $NumberOfEntries; $i++) {
					$StartOfEntry = $MemoryStream.Position
					$Length = [System.BitConverter]::ToUInt16($BinReader.ReadBytes(2),0)
					$BinReader.ReadBytes(2) | Out-Null # Max Length
					$Offset = [System.BitConverter]::ToUInt32($BinReader.ReadBytes(4),0)
					$Time = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
					$MemoryStream.Position = $StartOfEntry + $Offset
					[PSCustomObject]@{
						Name = $UnicodeEncoding.GetString($BinReader.ReadBytes($Length)) -replace "\\\?\?\\",""
						ModifiedTime = $TimeModified
					}
					$MemoryStream.Position = $StartOfEntry + 24
				}
			}
			
			# Return a Table with the results.  I have to do this in the switch since not all OS versions will have the same interesting fields to return
			$EntryArray | Select-Object -Property Name, Time, Flag0, Flag1
		}
		
		# DEADBEEF in Little Endian Hex - Windows XP
		"EFBEADDE" {
			# Number of Entries at Offset 4, Length of 4 bytes
			$NumberOfEntries = [System.BitConverter]::ToUInt32($AppCompatCache[4..7],0)
			
			# Move to the Offset 400 where the Entries begin
			$MemoryStream.Position=400
			
			# Use the Number of Entries it says are available and iterate through this loop that many times
			for ($i=0; $i -lt $NumberOfEntries; $i++) {
				$Name = ($UnicodeEncoding.GetString($BinReader.ReadBytes(488))) -replace "\\\?\?\\",""
				$BinReader.ReadBytes(40) | Out-Null
				[PSCustomObject]@{
					Name = $Name
					ModifiedTime = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
					Size = [System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)
					UpdatedTime = [DateTime]::FromFileTime([System.BitConverter]::ToUInt64($BinReader.ReadBytes(8),0)).ToString("G")
				}
			}
		}
	}
}