<#
.SYNOPSIS
	Looks for PowerShell profiles (PowerShell Persistence Mechanism), adds to ZIP file to be pulled back for analysis.

.DESCRIPTION
    PowerShell profiles are one mechanism used for persistence of PowerShell scripts.
    A PowerShell profile contains a list of commands that run each time PowerShell is executed on the system, either for all users or for the specific user account to which the profile pertains.
    PowerShell profile persistence is typically used in conjuction with a Scheduled Task, Run Key, or WMI Event subscription that silently runs PowerShell in the background after the computer has been rebooted.
    The profile itself contains the malicious code, and the Persistence mechanism only executes PowerShell.exe
    For more information on PowerShell persistence, see Mattifestation's PowerSploit repository on GitHub @ https://github.com/mattifestation/PowerSploit

.NOTES
    Original From Dave Hull's Kansa repository on GitHub: 11/16/2014
    Modified by David Howell to add comments, remove aliases, clean up code, and convert duplicate code into functions: 04/02/2015

OUTPUT zip
#>

# Set the ZipFile name to be used in the Temp Directory. This equates to the following save path: %Temp%\ComputerName-PSProfiles.zip
$ZipFile = $env:Temp + "\" + $env:COMPUTERNAME + "-PSProfiles.zip"

function Add-Zip {
    <#
    .SYNOPSIS
        This function creates and/or adds files to a .ZIP archive

    .NOTES
        This function taken from Dave Hull's Kansa project and commented by David Howell
    #>
    [CmdletBinding()]Param(
        [Parameter(Mandatory=$True)][String]$ZipFilePath=$null,
        [Parameter(Mandatory=$True)][String]$FilePath=$null
    )
    # Test if the Zip File exists, and if it doesn't create the file
    if (-not (Test-Path -Path $ZipFilePath)) {
        # Create the file with appropriate Zip file header information
        Set-Content -Path $ZipFilePath ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18)) -Force

        # Set the Read Only option to False so we can add to the zip file
        (Get-ChildItem -Path $ZipFilePath).IsReadOnly=$false
    }

    # Initialize a Shell.Application ComObject to use for adding to the zip file
    $Shell = New-Object -ComObject Shell.Application

    # Set the Namespace of the ComObject to our Zip File
    $ZipPackage = $Shell.NameSpace($ZipFilePath)

    # Use the CopyHere method to add the file
    $ZipPackage.CopyHere($FilePath)

    # Pause while the file is added
    Start-Sleep -Milliseconds 100
}

function VerifyandZip  {
    <#
    .SYNOPSIS
        Function created to remove duplicate code. Verifies the PowerShell Profile exists, then adds to the Zip File.

    .NOTES
        File Paths require full path in a string
    #>
    [CmdletBinding()]Param(
        [Parameter(Mandatory=$True)][String]$FilePath,
        [Parameter(Mandatory=$True)][String]$ProfileName,
        [Parameter(Mandatory=$True)][String]$ZipFilePath
    )

    # Test if the Profile Exists
    if (Test-Path -Path $FilePath -ErrorAction SilentlyContinue) {
        # Copy Item to Temp Directory just in case of errors if profile is in use
        Copy-Item -Path $FilePath -Destination $env:Temp\$ProfileName -ErrorAction SilentlyContinue

        # Add the Item to the Zip File
        Get-ChildItem -Path $env:Temp\$ProfileName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        Add-Zip -ZipFilePath $ZipFilePath -FilePath $env:Temp\$ProfileName
		
        # Delete the Profile from Temp Directory
        Remove-Item -Path $env:Temp\$ProfileName -Force -ErrorAction SilentlyContinue
    }
}

# Check if this file already exists and delete it if it does
if (Test-Path -Path $ZipFile -ErrorAction SilentlyContinue) {
    # Force deletion of the item
    Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
}

# Loop structure to repeat for each User Profile on the computer
Get-WmiObject -Namespace root\cimv2 -Class Win32_UserProfile -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPath | ForEach-Object {
    # Set File Path Variable for this User Profile
    $ProfilePath = $_ + "\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"

    # Set Profile Name Variable for this user Profile
    $ProfileName = Split-Path -Path $_ -Leaf

    # Call the VerifyandZip function
    VerifyandZip -FilePath $ProfilePath -ProfileName $ProfileName -ZipFilePath $ZipFile
}

# Create an array to store Default Paths to PowerShell Profiles
$DefaultPaths=@(
    [PSCustomObject]@{Path=$env:windir + "\System32\WindowsPowerShell\v1.0\Microsoft.Powershell_profile.ps1"; Name="System32_Microsoft.Powershell_profile.ps1"},
    [PSCustomObject]@{Path=$env:windir + "\System32\WindowsPowershell\v1.0\profile.ps1"; Name="System32_profile.ps1"},
    [PSCustomObject]@{Path=$env:windir + "\SysWOW64\WindowsPowershell\v1.0\Microsoft.Powershell_profile.ps1"; Name="SysWOW64_Microsoft.Powershell_profile.ps1"},
    [PSCustomObject]@{Path=$env:windir + "\SysWOW64\WindowsPowershell\v1.0\profile.ps1"; Name="SysWOW64_profile.ps1"}
)

# Add the Default Paths to our Zip if they exist
$DefaultPaths | ForEach-Object {
    VerifyandZip -FilePath $_.Path -ProfileName $_.Name -ZipFilePath $ZipFile
}

# If the Zip File was created, return the Value to NOVIRA.  Note, no zip file is created if no profiles exist
if (Test-Path -Path $ZipFile -ErrorAction SilentlyContinue) {
    # Relay the Zip File contents
    Get-Content -Encoding Byte -Raw $ZipFile -ErrorAction SilentlyContinue

    # Delete the Zip File
    Remove-Item -Path $Zipfile -Force -ErrorAction SilentlyContinue | Out-Null
}