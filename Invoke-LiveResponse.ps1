<#
.SYNOPSIS
    PowerShell based live response via WinRM, and Invoke-Command.

.DESCRIPTION
    This project is an off-shoot of Dave Hull's Kansa project. https://github.com/davehull/Kansa/
	I had some ideas for expanding the project and adding a GUI, so decided to create my own project.

.PARAMETER ComputerName
    Name or IP Address of the target computer(s). Can accept a comma separated list, or a variable containing a string array.

.PARAMETER CollectionModule
	Execute the specified collection module or modules against the target system. Accepts a comma separated list for multiple modules.
	Modules requiring parameters to be passed are handled by adding a space after the module name, then the value of the parameter.

.PARAMETER CollectionGroup
	Execute the specified group of collection modules. Collection groups are groups of modules that you can configure for different configurations (i.e. MalwareTriage, IISServer, etc.)

.PARAMETER AnalysisModule
	Execute the specified analysis modules against the data retrieved from the collection modules.

.PARAMETER JobType
	This parameter changes the method used for processing jobs. This only has an impact when executing against a large number of target systems.
	Possible Values: LiveResponse, Hunting
	Default Value: LiveResponse
		LiveResponse: All modules are executed on the target system before moving on to the next target.
		Hunting: The module is exected against all target systems before moving on to the next module.

.PARAMETER ShowCollectionModules
	Provides a list of all available collection modules, their descriptions, output format, and binary dependencies, and input parameters.

.PARAMETER ShowCollectionGroups
	Provides a list of all configured collection groups.

.PARAMETER ShowAnalysisModules
	Provide a list of all available analysis modules and their descriptions.

.PARAMETER Config
	Used with other switches to save settings in a conf file, such as save directory and number of concurrent jobs.
	When used alone, displays currently saved settings from the conf file.

.PARAMETER SavePath
	If you need to specify a different Save Path other than the default (.\Results).
	Can be used with the -Config switch to save a different save path in a config file.

.PARAMETER WinRMFix
	If WinRM isn't functioning on the target host, Invoke-LiveResponse will attempt to fix it.
	You can use this switch to disable this functionality.
	Default Value: $True

.PARAMETER RevertWinRMFix
	If WinRM wasn't functioning on the target and we fixed it, we revert any changes after processing is complete.
	You can use this switch to disable this functionality, meaning any changes will remain.
	Default Value: $True

.PARAMETER ConcurrentJobs
	Changes the number of runspaces to create for processing. 1 runspace is used per target system.
	Use ConcurrentJobs switch along with Config switch to change the number of simultaneous jobs.
	Default is 2.
	This value is ignored when processing with the Hunting Job Type.

.PARAMETER Credential
	This parameter checks for Credentials plugin first, and executes it if it exists. Otherwise it just performs Get-Credential to prompt user for credentials to use in the Live Response process.

.PARAMETER GUI
	This parameter calls the GUI.ps1 in the .\Plugins directory so the user can utilize a GUI rather than running at the command line.

.EXAMPLE
	Change the default save path and number of concurrent jobs.
	Invoke-LiveResponse -Config -SavePath \\servername\smbshare\LRResults -ConcurrentJobs 4

.EXAMPLE
	Show available collection modules
	Invoke-LiveResponse -ShowCollectionModules

.EXAMPLE
	Show available analysis modules
	Invoke-LiveResponse -ShowAnalysisModules

.EXAMPLE
	Show the available collection groups
	Invoke-LiveResponse -ShowCollectionGroups

.EXAMPLE
	Run the MalwareTriage collection group on the target computer
	Invoke-LiveResponse -ComputerName COMPUTERNAME -CollectionGroup MalwareTriage

.EXAMPLE
	Run the MalwareTriage collection group on target computer, then run the Get-Timeline analysis module against the results.
	Invoke-LiveResponse -ComputerName COMPUTERNAME -CollectionGroup MalwareTriage -AnalysisModule Timeline

.EXAMPLE
	Run the Get-Processes and Get-Netstat collection modules on the target computer
	Invoke-LiveResponse -ComputerName COMPUTERNAME -CollectionModule Get-Processes, Get-Netstat

.EXAMPLE
	Run the Get-ProcessMemory collection module and pass an executable name as a parameter.
	Invoke-LiveResponse -ComputerName COMPUTERNAME -CollectionModule "Get-ProcessMemory conhost.exe"

.EXAMPLE
	Run the Get-Processes collection module on target computer, then run the VirusTotalCheck analysis script against any file hashes returned.
	Invoke-LiveResponse -ComputerName COMPUTERNAME -CollectionModule Get-Processes -AnalysisModule VirusTotalCheck

.NOTES
    Author: David Howell
    Last Modified: 12/27/2015
    Version: 1.2
#>
[CmdletBinding(DefaultParameterSetName="LRCollectionModule")]
Param(
	[Parameter(Mandatory=$True,ParameterSetName="GUI")]
	[Switch]
	$GUI,
	
	[Parameter(Mandatory=$True,ParameterSetName="LRCollectionModule")]
	[String[]]
	$CollectionModule,
	
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionGroup")]
	[Parameter(Mandatory=$True,ParameterSetName="AnalysisOnly")]
	[String[]]
	$AnalysisModule,
	
	[Parameter(Mandatory=$True,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$True,ParameterSetName="LRCollectionGroup")]
	[String[]]
	$ComputerName,

	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionGroup")]
	[ValidateSet("LiveResponse","Hunting")]
	[String]
	$JobType,

	[Parameter(Mandatory=$True,ParameterSetName="ShowCollectionModules")]
	[Switch]
	$ShowCollectionModules,

	[Parameter(Mandatory=$True,ParameterSetName="ShowCollectionGroups")]
	[Switch]
	$ShowCollectionGroups,
	
	[Parameter(Mandatory=$True,ParameterSetName="ShowAnalysisModules")]
	[Switch]
	$ShowAnalysisModules,

	[Parameter(Mandatory=$True,ParameterSetName="Config")]
	[Switch]
	$Config,

	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionGroup")]
	[String]
	$SavePath,
	
	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[ValidateSet("True","False")]
	[String]
	$WinRMFix,
	
	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[ValidateSet("True","False")]
	[String]
	$RevertWinRMFix,
	
	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[Int]
	$ConcurrentJobs,
	
	[Parameter(Mandatory=$True,ParameterSetName="AnalysisOnly")]
	[String]
	$ResultsPath,
	
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionGroup")]
	[Switch]
	$Credential
)

# Using Dynamic Parameters for CollectionGroup and AnalysisModule switches
DynamicParam {
	# Determine executing directory
	Try {
		$ScriptDirectory = Split-Path ($MyInvocation.MyCommand.Path) -ErrorAction Stop
	} Catch {
		$ScriptDirectory = (Get-Location).Path
	}
	
	$RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	
#region Add CollectionGroup Dynamic Parameter
	# Check for CollectionGroups.conf. If it exists, import the Module Sets as a possible value for the CollectionGroup parameter.
	if (Test-Path -Path "$ScriptDirectory\CollectionModules\CollectionGroups.conf") {
		$CollectionGroupAttrColl = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
		$CollectionGroupParamAttr = New-Object System.Management.Automation.ParameterAttribute
		$CollectionGroupParamAttr.Mandatory = $True
		$CollectionGroupParamAttr.ParameterSetName = "LRCollectionGroup"
		$CollectionGroupAttrColl.Add($CollectionGroupParamAttr)
		[XML]$CollectionGroupsXML = Get-Content -Path "$ScriptDirectory\CollectionModules\CollectionGroups.conf" -ErrorAction Stop
		$CollectionGroupValidateSet = @()
		$CollectionGroupsXML.CollectionGroups | Get-Member -MemberType Property | Select-Object -ExpandProperty Name | Where-Object { $_ -ne "#comment" } | ForEach-Object {
			$CollectionGroupValidateSet += $_
		}
		$CollectionGroupValSetAttr = New-Object System.Management.Automation.ValidateSetAttribute($CollectionGroupValidateSet)
		$CollectionGroupAttrColl.Add($CollectionGroupValSetAttr)
		$CollectionGroupRuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter("CollectionGroup", [string], $CollectionGroupAttrColl)
		$RuntimeParameterDictionary.Add("CollectionGroup", $CollectionGroupRuntimeParam)
	}
#endregion Add CollectionGroup Dynamic Parameter
	
	if ($RuntimeParameterDictionary) {
		return $RuntimeParameterDictionary
	}
}

Begin {
	# Loop through the PSBoundParameters hashtable and add all variables. This makes it so the dynamic variables are set and we can tab complete with them.
	$PSBoundParameters.GetEnumerator() | ForEach-Object { New-Variable -Name $_.Key -Value $_.Value -ErrorAction SilentlyContinue }
} Process {

#region Check PowerShell Version
	# Verify we are running on PowerShell version 3 or higher
	Write-Verbose -Message "Checking PowerShell Version.  Version 3 or higher is required."
	if ($PSVersionTable.PSVersion.Major -lt 3) {
		Write-Error -Message "PowerShell version needs to be 3 or higher.  You are using version $($PSVersionTable.PSVersion.ToString()). Exiting script."
		exit
	} else {
		Write-Verbose -Message "PowerShell version $($PSVersionTable.PSVersion.Major) is sufficient, continuing."
	}
#endregion Check PowerShell Version

#region Get Executing Directory
	# Determine executing directory
	Write-Verbose -Message "Determining script's executing directory."
	Try {
		$ScriptDirectory = Split-Path ($MyInvocation.MyCommand.Path) -ErrorAction Stop
	} Catch {
		$ScriptDirectory = (Get-Location).Path
	}
	Write-Verbose -Message "Script's executing directory is $ScriptDirectory."
	$BinaryDirectory = $ScriptDirectory + "\CollectionModules\Binaries\"
	Write-Verbose -Message "Script's binary dependency directory is $BinaryDirectory."
#endregion Get Executing Directory

	# Array to contain list of "selected collection modules", which is added based on the values provided for -CollectionModule or -CollectionGroup
	$SelectedCollectionModules = New-Object System.Collections.ArrayList
	
	# Array to contain a list of "selected analysis modules", which is added based on the values provided with -AnalysisModule switch
	$SelectedAnalysisModules =  New-Object System.Collections.ArrayList
	
#region Parameter Set Name switch
	switch ($PSCmdlet.ParameterSetName) {
		# Config Parameter Set
		"Config" {
			# We need to either import the current configuration if it exists, or create a new one
			if (Test-Path -Path "$Env:APPDATA\Invoke-LiveResponse.conf") {
				# Check if configuration file exists. Import if it does
				[XML]$ConfigObject = Get-Content -Path "$Env:APPDATA\Invoke-LiveResponse.conf"
			} else {
				# If configuration file doesn't exist, create it
				$ConfigObject = New-Object System.Xml.XmlDocument
				$ConfigurationElement = $ConfigObject.CreateElement("Configuration")
				$ConfigObject.AppendChild($ConfigurationElement) | Out-Null
			}
			
			# If user provided a save path, either add it to the configuration or update the configuration's previous entry
			if ($SavePath) {
				if ($SavePath -eq "delete" -or $SavePath -eq "clear" -or $SavePath -eq "remove") {
					if (-not ($ConfigurationElement)) {
						[System.Xml.XmlElement]$ConfigurationElement = $ConfigObject.Configuration
					}
					$ConfigurationElement.RemoveAttribute("SavePath")
				} else {
					if ($ConfigObject.Configuration.SavePath) {
						$ConfigObject.Configuration.SavePath = $SavePath
					} else {
						if (-not ($ConfigurationElement)) {
							[System.Xml.XmlElement]$ConfigurationElement = $ConfigObject.Configuration
						}
						$ConfigurationElement.SetAttribute("SavePath",$SavePath)
					}
					$ConfigObject.Save("$Env:APPDATA\Invoke-LiveResponse.conf")
				}
			}
			
			# If user provided a WinRMFix value, either add it to the configuration or update the configuration's previous entry
			if ($WinRMFix) {
				if ($ConfigObject.Configuration.WinRMFix) {
					$ConfigObject.Configuration.WinRMFix = $WinRMFix
				} else {
					if (-not ($ConfigurationElement)) {
						[System.Xml.XmlElement]$ConfigurationElement = $ConfigObject.Configuration
					}
					$ConfigurationElement.SetAttribute("WinRMFix",$WinRMFix)
				}
				$ConfigObject.Save("$Env:APPDATA\Invoke-LiveResponse.conf")
			}
			
			# If user provided a RevertWinRMFix value, either add it to the configuration or update the configuration's previous entry
			if ($RevertWinRMFix) {
				if ($ConfigObject.Configuration.RevertWinRMFix) {
					$ConfigObject.Configuration.RevertWinRMFix = $RevertWinRMFix
				} else {
					if (-not ($ConfigurationElement)) {
						[System.Xml.XmlElement]$ConfigurationElement = $ConfigObject.Configuration
					}
					$ConfigurationElement.SetAttribute("RevertWinRMFix",$RevertWinRMFix)
				}
				$ConfigObject.Save("$Env:APPDATA\Invoke-LiveResponse.conf")
			}
			
			# If user provided a concurrent jobs amount, either add it ot the configuration or update the configuration's previous entry
			if ($ConcurrentJobs) {
				if ($ConcurrentJobs -lt 1) {
					if (-not ($ConfigurationElement)) {
						[System.Xml.XmlElement]$ConfigurationElement = $ConfigObject.Configuration
					}
					$ConfigurationElement.RemoveAttribute("ConcurrentJobs")
				} else {
					if ($ConfigObject.Configuration.ConcurrentJobs) {
						$ConfigObject.Configuration.ConcurrentJobs = $ConcurrentJobs.ToString()
					} else {
						if (-not ($ConfigurationElement)) {
							[System.Xml.XmlElement]$ConfigurationElement = $ConfigObject.Configuration
						}
						$ConfigurationElement.SetAttribute("ConcurrentJobs",$ConcurrentJobs.ToString())
					}
					$ConfigObject.Save("$Env:APPDATA\Invoke-LiveResponse.conf")
				}
			}
			
			# Show the current configuration settings after any updates
			$TempObject = New-Object PSObject
			$TempObject | Add-Member -MemberType NoteProperty -Name "SavePath" -Value ($ConfigObject.Configuration.SavePath)
			$TempObject | Add-Member -MemberType NoteProperty -Name "ConcurrentJobs" -Value ($ConfigObject.Configuration.ConcurrentJobs)
			$TempObject | Add-Member -MemberType NoteProperty -Name "WinRMFix" -Value ($ConfigObject.Configuration.WinRMFix)
			$TempObject | Add-Member -MemberType NoteProperty -Name "RevertWinRMFix" -Value ($ConfigObject.Configuration.RevertWinRMFix)
			return $TempObject
		}
		
		# ShowCollectionModules Parameter Set, used to display a list of available collection modules
		"ShowCollectionModules" {
			$CollectionModules = Get-ChildItem -Path "$ScriptDirectory\CollectionModules" -Filter *.ps1 -Recurse | Select-Object -Property Name, FullName
			$CollectionModuleArray=@()
			$ConfirmPreference = "none"
			$CollectionModules | ForEach-Object {
				$TempObject = New-Object PSObject
				$TempObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $_.Name
				$TempObject | Add-Member -MemberType NoteProperty -Name "FilePath" -Value $_.FullName
				# Parse the Directives from the Collection Module
				$Directives = Get-Content -Path $_.FullName | Select-String -CaseSensitive -Pattern "^(OUTPUT|BINARY|INPUT)"
				[String]$OutputType="txt"
	            $BinaryDependency=$False
	            [String]$BinaryName="N/A"
				[String]$InputParameters="N/A"
	            ForEach ($Directive in $Directives) {
	                if ($Directive -match "(^OUTPUT) (.*)") {
	                    [String]$OutputType=$matches[2]
	                }
	                if ($Directive -match "(^BINARY) (.*)") {
	                    $BinaryDependency=$True
	                    [String]$BinaryName=$matches[2]
	                }
					if ($Directive -match "(^INPUT) (.*)") {
						[String]$InputParameters = $matches[2]
					}
	            }
	            $TempObject | Add-Member -MemberType NoteProperty -Name "OutputType" -Value $OutputType
	            $TempObject | Add-Member -MemberType NoteProperty -Name "BinaryDependency" -Value $BinaryDependency
	            $TempObject | Add-Member -MemberType NoteProperty -Name "BinaryName" -Value $BinaryName
				$TempObject | Add-Member -MemberType NoteProperty -Name "InputParameters" -Value $InputParameters
				$TempObject | Add-Member -MemberType NoteProperty -Name "Description" -Value (Get-Help $_.FullName | Select-Object -ExpandProperty Synopsis)
				$CollectionModuleArray += $TempObject
			}
			
			$CollectionModuleArray | Select-Object -Property Name, Description, OutputType, BinaryDependency, BinaryName, InputParameters
		}
		
		# ShowCollectionGroups Parameter Set, used to display a list of available collection groups and the list of collection modules in each set.
		"ShowCollectionGroups" {
			$CollectionGroupArray = @()
			
			# Check for CollectionGroups.conf and read contents
			Write-Verbose -Message "Checking for CollectionGroups.conf file to import settings."
			if (Test-Path -Path "$ScriptDirectory\CollectionModules\CollectionGroups.conf") {
				[XML]$CollectionGroupsXML = Get-Content -Path "$ScriptDirectory\CollectionModules\CollectionGroups.conf" -ErrorAction Stop
				Write-Verbose -Message "CollectionGroups.conf found and imported."
				$CollectionGroupsXML.CollectionGroups | Get-Member -MemberType Property | Select-Object -ExpandProperty Name | Where-Object { $_ -ne "#comment" } | ForEach-Object {
					# For each collection group, create a custom object and populate metadata
					$TempObject = New-Object PSObject
					$TempObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $_
					$TempObject | Add-Member -MemberType NoteProperty -Name "Description" -Value $CollectionGroupsXML.CollectionGroups.$_.Description
					$TempObject | Add-Member -MemberType NoteProperty -Name "CollectionModules" -Value ([String]::Join(', ', $CollectionGroupsXML.CollectionGroups.$_.CollectionModule.Name))
					
					# Add custom object to our array
					$CollectionGroupArray += $TempObject
				}
				
				# Show the contents of our array
				$CollectionGroupArray | Select-Object -Property Name, Description, CollectionModules
			} else {
				Write-Verbose -Message "CollectionGroups.conf not found."
			}
		}
		
		# ShowAnalysisModules Parameter Set, used to display a list of available analysis modules and their description.
		"ShowAnalysisModules" {
			$AnalysisModules = Get-ChildItem -Path "$ScriptDirectory\AnalysisModules" -Filter *.ps1 -Recurse | Select-Object -Property Name, FullName
			$AnalysisModuleArray=@()
			$ConfirmPreference = "none"
			$AnalysisModules | ForEach-Object {
				$TempObject = New-Object PSObject
				$TempObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $_.Name
				$TempObject | Add-Member -MemberType NoteProperty -Name "FilePath" -Value $_.FullName
				$TempObject | Add-Member -MemberType NoteProperty -Name "Description" -Value (Get-Help $_.FullName | Select-Object -ExpandProperty Synopsis)
				$AnalysisModuleArray += $TempObject
			}
			
			$AnalysisModuleArray | Select-Object -Property Name, Description
		}
		
		# LRCollectionModule Parameter Set, used to perform live response with a specific collection module or modules
		"LRCollectionModule" {
			# This section of code only sets the SelectedCollectionModules variable. Execution code is later
			
			# Verify the collection module exists before adding it to selected collection modules list
			$CollectionModule | ForEach-Object {
				if ($_ -match "([^\s]+)(\s([^s]+)?)?") {
					$Name = $matches[1]
					
					if ($Name -notmatch ".+\.ps1") {
						$Name = $Name + ".ps1"
					}
					
					[String[]]$InputValues = $matches[3] -split " "
				}
				
				if (Get-ChildItem -Path "$ScriptDirectory\CollectionModules\" -File $Name -Recurse) {
					# Gather information about the collection module that will be needed later during processing
					$TempObject = New-Object PSObject
					$TempObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $Name
					$TempObject | Add-Member -MemberType NoteProperty -Name "FilePath" -Value (Get-ChildItem -Path "$ScriptDirectory\CollectionModules\" -File $Name -Recurse).FullName
					$TempObject | Add-Member -MemberType NoteProperty -Name "InputValues" -Value $InputValues
					# Parse the Directives from the collection modules
					$Directives = Get-Content -Path $TempObject.FilePath | Select-String -CaseSensitive -Pattern "^(OUTPUT|BINARY|INPUT)"
					[String]$OutputType="txt"
					$BinaryDependency=$False
					[String]$BinaryName="N/A"
		            ForEach ($Directive in $Directives) {
						if ($Directive -match "(^OUTPUT) (.*)") {
							[String]$OutputType=$matches[2]
						}
						if ($Directive -match "(^BINARY) (.*)") {
							$BinaryDependency=$True
							[String]$BinaryName=$matches[2]
						}
						if ($Directive -match "(^INPUT) (.*)") {
							[String]$InputParameters=$matches[2]
						}
		            }
					$TempObject | Add-Member -MemberType NoteProperty -Name "InputParameters" -Value $InputParameters
					$TempObject | Add-Member -MemberType NoteProperty -Name "OutputType" -Value $OutputType
					$TempObject | Add-Member -MemberType NoteProperty -Name "BinaryDependency" -Value $BinaryDependency
					$TempObject | Add-Member -MemberType NoteProperty -Name "BinaryName" -Value $BinaryName
					$SelectedCollectionModules.Add($TempObject) | Out-Null
				} else {
					Write-Host "Collection Module `"$_`" does not exist"
				}
				
				# Clean up variables we no longer need
				Remove-Variable -Name TempObject -ErrorAction SilentlyContinue
				Remove-Variable -Name Directives -ErrorAction SilentlyContinue
				Remove-Variable -Name BinaryDependency -ErrorAction SilentlyContinue
				Remove-Variable -Name BinaryName -ErrorAction SilentlyContinue
				Remove-Variable -Name OutputType -ErrorAction SilentlyContinue
				Remove-Variable -Name InputParameters -ErrorAction SilentlyContinue
				Remove-Variable -Name InputValues -ErrorAction SilentlyContinue
				Remove-Variable -Name Name -ErrorAction SilentlyContinue
			}
		}
		
		# LRCollectionGroup Parameter Set, used to perform live response with a group of collection modules defined in CollectionGroups.conf
		"LRCollectionGroup" {
			# This section of code only sets the SelectedCollectionModules variable. Execution code is later
			
			# Check for CollectionGroups.conf and read contents
			Write-Verbose -Message "Checking for CollectionGroups.conf file to import settings."
			if (Test-Path -Path "$ScriptDirectory\CollectionModules\CollectionGroups.conf") {
				[XML]$CollectionGroupsXML = Get-Content -Path "$ScriptDirectory\CollectionModules\CollectionGroups.conf" -ErrorAction Stop
				Write-Verbose -Message "CollectionGroups.conf found and imported."
			} else {
				Write-Verbose -Message "CollectionGroups.conf not found."
			}
			
			$CollectionGroupsXML.CollectionGroups.$CollectionGroup.CollectionModule | ForEach-Object {
				# Verify the collection module exists before adding it to selected collection modules list
				if (Get-ChildItem -Path "$ScriptDirectory\CollectionModules" -Filter $_.Name -Recurse) {
					# Gather information about the collection module that will be needed later during processing
					$TempObject = New-Object PSObject
					$TempObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $_.Name
					$TempObject | Add-Member -MemberType NoteProperty -Name "FilePath" -Value (Get-ChildItem -Path "$ScriptDirectory\CollectionModules" -Filter $_.Name -Recurse).FullName
					# Parse the Directives from the collection modules
					$Directives = Get-Content -Path $TempObject.FilePath | Select-String -CaseSensitive -Pattern "^(OUTPUT|BINARY)"
					[String]$OutputType="txt"
					$BinaryDependency=$False
					[String]$BinaryName="N/A"
					[String]$InputParameters="N/A"
		            ForEach ($Directive in $Directives) {
						if ($Directive -match "(^OUTPUT) (.*)") {
							[String]$OutputType=$matches[2]
						}
						if ($Directive -match "(^BINARY) (.*)") {
							$BinaryDependency=$True
							[String]$BinaryName=$matches[2]
						}
						if ($Directive -match "(^INPUT) (.*)") {
							[String]$InputParameters=$matches[2]
						}
		            }
					$TempObject | Add-Member -MemberType NoteProperty -Name "OutputType" -Value $OutputType
					$TempObject | Add-Member -MemberType NoteProperty -Name "BinaryDependency" -Value $BinaryDependency
					$TempObject | Add-Member -MemberType NoteProperty -Name "BinaryName" -Value $BinaryName
					$TempObject | Add-Member -MemberType NoteProperty -Name "InputParameters" -Value $InputParameters
					if ($_.InputValues -eq "") {
						$TempObject | Add-Member -MemberType NoteProperty -Name "InputValues" -Value "N/A"
					} else {
						$TempObject | Add-Member -MemberType NoteProperty -Name "InputValues" -Value $_.InputValues
					}
					$SelectedCollectionModules.Add($TempObject) | Out-Null
					
					# Clean up variables we no longer need
					Remove-Variable -Name TempObject -ErrorAction SilentlyContinue
					Remove-Variable -Name Directives -ErrorAction SilentlyContinue
					Remove-Variable -Name Directive -ErrorAction SilentlyContinue
					Remove-Variable -Name BinaryDependency -ErrorAction SilentlyContinue
					Remove-Variable -Name BinaryName -ErrorAction SilentlyContinue
					Remove-Variable -Name OutputType -ErrorAction SilentlyContinue
					Remove-Variable -Name InputParameters -ErrorAction SilentlyContinue
				}
			}
			Remove-Variable -Name CollectionGroupsXML -ErrorAction SilentlyContinue
		}
		
		# GUI Parameter Set, used to launch the GUI.ps1 script
		"GUI" {
			& "$ScriptDirectory\Plugins\GUI.ps1" -ScriptDirectory $ScriptDirectory
		}
	}
#endregion Parameter Set Name switch

#region Import Configuration Information
	# Check for configuration file. Read contents, if it exists.
	Write-Verbose -Message "Checking for configuration file to import settings."
	if (Test-Path -Path "$Env:APPDATA\Invoke-LiveResponse.conf") {
		[XML]$Config = Get-Content -Path "$Env:APPDATA\Invoke-LiveResponse.conf" -ErrorAction Stop
		Write-Verbose -Message "Configuration file found and imported."
	}
	# If a save path is listed in the configuration file, use it. Otherwise, set to the default.
	if ($Config.Configuration.SavePath) {
		$SaveLocation = $Config.Configuration.SavePath
		Write-Verbose -Message "Save path imported:  $($Config.Configuration.SavePath)"
	} else {
		$SaveLocation = $ScriptDirectory + "\Results\"
	}
	# If a concurrent jobs count is listed in the configuration file, use it. Otherwise use the default of 2.
	if ($Config.Configuration.ConcurrentJobs) {
		$RunspaceCount = $Config.Configuration.ConcurrentJobs
	} else {
		$RunspaceCount = 2
	}
	
	# If WinRMFix is listed in the configuration file, use it. Otherwise use the default of $True
	if ($Config.Configuration.WinRMFix) {
		if ($Config.Configuration.WinRMFix -eq "True") {
			$WinRMFix = $True
		} else {
			$WinRMFix = $False
		}
	} else {
		$WinRMFix = $True
	}
	# If RevertWinRMFix is listed in the configuration file, use it. Otherwise use the default of $True
	if ($Config.Configuration.RevertWinRMFix) {
		if ($Config.Configuration.RevertWinRMFix -eq "True") {
			$RevertWinRMFix = $True
		} else {
			$RevertWinRMFix = $False
		}
	} else {
		$RevertWinRMFix = $True
	}
	
	# Clean up variables we don't need after configuration import
	Remove-Variable -Name Config
#endregion Import Configuration Information

#region Retrieve Information regarding Analysis Modules
	# Add analysis modules to the SelectedAnalysisModules array for processing
	if ($AnalysisModule) {
		$AnalysisModule | ForEach-Object {
			if ($_ -notmatch ".+\.ps1") {
				$Name = $_ + ".ps1"
			}
			# Verify the analysis module exists
			if (Test-Path -Path "$ScriptDirectory\AnalysisModules\$Name") {
				# Gather information about the analysis module that will be needed later during processing
				$TempObject = New-Object PSObject
				$TempObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $Name
				$TempObject | Add-Member -MemberType NoteProperty -Name "FilePath" -Value "$ScriptDirectory\AnalysisModules\$Name"
				$SelectedAnalysisModules.Add($TempObject) | Out-Null
			} else {
				Write-Host "Analysis Module `"$_`" does not exist"
			}
			# Clean up variables we no longer need
			Remove-Variable -Name TempObject -ErrorAction SilentlyContinue
			Remove-Variable -Name Name -ErrorAction SilentlyContinue
		}
	}
#endregion Retrieve Information regarding Analysis Modules

#region Execute Analysis Only Parameter Set
	if ($PSCmdlet.ParameterSetName -eq "AnalysisOnly") {
		ForEach ($SelectedAnalysisModule in $SelectedAnalysisModules) {
			& "$($SelectedAnalysisModule.FilePath)" -ResultsPath $ResultsPath
		}
	}
#endregion Execute Analysis Only Parameter Set
	
	# Continue to perform live response actions, if we are using a parameter set for live response.
	if ($SelectedCollectionModules) {
	
#region Preparing for Live Response
		Write-Verbose "Continuing to Live Response"
		# If a Save Path was provided, override the path from the Configuration file
		if ($SavePath) {
			$SaveLocation = $SavePath
		}
		
		# If the Credential switch was specified, run the Credentials plugin or prompt for Credentials using Get-Credential
		if ($Credential) {
			Write-Verbose "Credential switch specified"
			if (Test-Path -Path "$ScriptDirectory\Plugins\Credentials.ps1") {
				[System.Management.Automation.PSCredential]$Credentials = & "$ScriptDirectory\Plugins\Credentials.ps1"
			} else {
				[System.Management.Automation.PSCredential]$Credentials = Get-Credential -Message "Enter credentials for Invoke-LiveResponse"
			}
		}
		
		if (-not($JobType)) {
			$JobType = "LiveResponse"	
		}
		
		# Create a Synchroznied hashtable to share progress with other runspaces/scripts
		$SynchronizedHashtable = [System.Collections.HashTable]::Synchronized(@{})
		
		# Create a ProgressLogMessage array to store log entries to send to log file
		$SynchronizedHashtable.ProgressLogMessage = New-Object System.Collections.ArrayList
		
		# Create a Progress Bar Message array to store messages for the progress bar
		$SynchronizedHashtable.ProgressBarMessage = New-Object System.Collections.ArrayList
		
		# Create a total count of collection module jobs to run for a progress bar
		$SynchronizedHashtable.ProgressBarTotal = $ComputerName.Count * ($SelectedCollectionModules.Count + $SelectedAnalysisModules.Count)
		$SynchronizedHashtable.ProgressBarCurrent = 0
		
		# Get the execution time and add that to the save path
		$StartTime=Get-Date -Format yyyyMMdd-HHmmss
		$SaveLocation = $SaveLocation + "\$StartTime"
		
		# Create the results directory
		New-Item -Path $SaveLocation -ItemType Directory -Force | Out-Null

		# Set a log path and create a log file
		$LogPath = "$SaveLocation\Logfile.Log"
		New-Item -Path $LogPath -ItemType File -Force | Out-Null
		
		# Initialize log file with some information about the current run execution
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Initiating Invoke-LiveResponse"
		Add-Content -Path $LogPath -Value (Get-Date -Format "MMMM dd, yyyy H:mm:ss")
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) ##############################"
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Curent User: $Env:Username"
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Current Computer: $env:Computername"
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) ##############################"
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Job Type: $JobType"
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Concurrent Job Count: $RunspaceCount"
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Target List: $ComputerName"
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Collection Modules Selected:"
		Add-Content -Path $LogPath -Value $SelectedCollectionModules.Name
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Analysis Modules Selected:"
		Add-Content -Path $LogPath -Value $SelectedAnalysisModules.Name
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) ##############################"
#endregion Preparing for Live Response

#region Test/Fix WinRM
		if ($WinRMFix -eq "True") {
		# Test PowerShell Remoting on the target hosts, and if it isn't working try to enable it
			# Create an array to store a list of changes we've made, so we can change them back when we are done.
			$WinRMChanges = New-Object System.Collections.ArrayList
			ForEach ($Computer in $ComputerName) {
				if (-not ($Computer -eq "localhost" -or $Computer -eq "127.0.0.1" -or $Computer -eq $Env:COMPUTERNAME)) {
					Try {
						# First, test PowerShell remoting. If it fails execution will cut to the Catch section to enable WinRM
						if ($Credential) {
							Invoke-Command -ComputerName $Computer -ScriptBlock {1} -Credential $Credentials -ErrorAction Stop | Out-Null
						} else {
							Invoke-Command -ComputerName $Computer -ScriptBlock {1} -ErrorAction Stop | Out-Null
						}
						Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : WinRM seems to be functioning."
					} Catch {
						$TempObject = New-Object PSObject
						$TempObject | Add-Member -MemberType NoteProperty -Name "ComputerName" -Value $Computer
						Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : WinRM doesn't appear to be functioning. Attempting to fix/enable it."
						# Verify WinRM Service is running. If it isn't, note the state and start the service.
						if ($Credential) {
							if ((Get-WmiObject -ComputerName $Computer -Class Win32_Service -Credential $Credentials -Filter "Name='WinRM'").State -ne "Running") {
								(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Credential $Credentials -Filter "Name='WinRM'").StartService() | Out-Null
								$TempObject | Add-Member -MemberType NoteProperty -Name "ChangedWinRM" -Value $True
							}
						} else {
							if ((Get-WmiObject -ComputerName $Computer -Class Win32_Service -Filter "Name='WinRM'").State -ne "Running") {
								(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Filter "Name='WinRM'").StartService() | Out-Null
								$TempObject | Add-Member -MemberType NoteProperty -Name "ChangedWinRM" -Value $True
							}
						}
						if ($ChangedWinRM -eq $True) {
							Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : WinRM service started."
						}
						
						if ($Credential) {
							# Create a Remote Registry handle on the remote machine
							$ConnectionOptions = New-Object System.Management.ConnectionOptions
							$ConnectionOptions.UserName = $Credential.UserName
							$ConnectionOptions.SecurePassword = $Credential.Password
							
							$ManagementScope = New-Object System.Management.ManagementScope -ArgumentList \\$Computer\Root\default, $ConnectionOptions -ErrorAction Stop
							$ManagementPath = New-Object System.Management.ManagementPath -ArgumentList "StdRegProv"
							
							$Reg = New-Object System.Management.ManagementClass -ArgumentList $ManagementScope, $ManagementPath, $null
						} else {
							$Reg = New-Object -TypeName System.Management.ManagementClass -ArgumentList \\$Computer\Root\default:StdRegProv -ErrorAction Stop
						}
						
						# Value used to connect to remote HKLM registry hive
						$HKLM = 2147483650
						
						# Verify the Registry Directory Structure exists, and if not try to create it
						if ($Reg.EnumValues($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM").ReturnValue -ne 0) {
							$Reg.CreateKey($HKLM, "SOFTWARE\Policies\Microsoft\Windows\WinRM") | Out-Null
						}
						if ($Reg.EnumValues($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service").ReturnValue -ne 0) {
							$Reg.CreateKey($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service") | Out-Null
						}
						# Verify the AllowAutoConfig registry value is 1, or set it to 1
						$AutoConfigValue=$Reg.GetDWORDValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","AllowAutoConfig")
						if ($AutoConfigValue.ReturnValue -ne 0 -and $AutoConfigValue.uValue -ne 1) {
							$Reg.SetDWORDValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","AllowAutoConfig","0x1") | Out-Null
							$TempObject | Add-Member -MemberType NoteProperty -Name "ChangedAutoConfigValue" -Value $AutoConfigValue
							Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Changed AllowAutoConfig registry key to 1."
						}
						# Verify the IPv4Filter registry value is *, or set it to *
						$IPV4Value=$Reg.GetStringValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv4Filter")
						if ($IPV4Value.ReturnValue -ne 0 -and $IPV4Value.sValue -ne "*") {
							$Reg.SetStringValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv4Filter","*") | Out-Null
							$TempObject | Add-Member -MemberType NoteProperty -Name "ChangedIPV4Value" -Value $IPV4Value
							Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Changed IPV4Filter registry key to *"
						}
						# Verify the IPv6Filter registry value is *, or set it to *
						$IPV6Value=$Reg.GetStringValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv6Filter")
						if ($IPV6Value.ReturnValue -ne 0 -and $IPV6Value.sValue -ne "*") {
							$Reg.SetStringValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv6Filter","*") | Out-Null
							$TempObject | Add-Member -MemberType NoteProperty -Name "ChangedIPV6Value" -Value $IPV6Value
							Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Changed IPV6Filter registry key to *"
						}
						
						# Now restart the WinRM service
						if ($Credential) {
							(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Credential $Credential -Filter "Name='WinRM'").StopService() | Out-Null
							(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Credential $Credential -Filter "Name='WinRM'").StartService() | Out-Null
						} else {
							(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Filter "Name='WinRM'").StopService() | Out-Null
							(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Filter "Name='WinRM'").StartService() | Out-Null
						}
						$WinRMChanges.Add($TempObject) | Out-Null
						$Reg.Dispose() | Out-Null
					}
				}
			}
		}
#endregion Test/Fix WinRM

#region Live Response Scriptblock
		# Define a ScriptBlock with Parameters for our Live Response process
		$LiveResponseProcess = {
			[CmdletBinding()]Param(
				[Parameter(Mandatory=$True)]
				[String]
				$Computer,
				
				[Parameter(Mandatory=$True)]
				[String]
				$OutputPath,
				
				[Parameter(Mandatory=$True)]
				[PSObject[]]
				$CollectionModules,
				
				[Parameter(Mandatory=$True)]
				[String]
				$BinaryDirectory,
				
				[Parameter(Mandatory=$True)]
				[System.Collections.HashTable]
				$SynchronizedHashtable,
				
				[Parameter(Mandatory=$False)]
				[PSObject[]]
				$AnalysisModules,
				
				[Parameter(Mandatory=$False)]
				[System.Management.Automation.PSCredential]
				$Credential
			)
			$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Job Processing beginning."
			
			if (Test-Connection -ComputerName $Computer -Count 1 -Quiet) {
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Target system is online."	
				#region Copy Binary Dependencies
				# First, copy any binary dependencies to the target
				if ($CollectionModules.BinaryDependency -contains "True") {
					$CollectionModules.BinaryName | Where-Object { $_ -ne "N/A" } | Select-Object -Unique | ForEach-Object {
						$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Binary Dependency found: $_. Copying to the target system."
						if (Test-Path -Path "$BinaryDirectory\$_") {
							if ($Computer -eq $Env:COMPUTERNAME -or $Computer -eq "127.0.0.1" -or $Computer -eq "localhost") {
								if ($Credential) {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows -Credential $Credential | Out-Null
								} else {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows | Out-Null
								}
							} else {
								if ($Credential) {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$ -Credential $Credential | Out-Null
								} else {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$ | Out-Null
								}
							}
							Copy-Item -Path "$BinaryDirectory\$_" -Destination Temp:\ -Recurse -ErrorAction SilentlyContinue
							Get-PSDrive -Name "Temp" | Remove-PSDrive
						}
					}
				}
				#endregion Copy Binary Dependencies
				
				#region Execute Modules
				ForEach($CollectionModule in $CollectionModules) {
					$SynchronizedHashtable.ProgressBarMessage += "Executing $($CollectionModule.Name) on $Computer"
					$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Executing collection module $($CollectionModule.Name)"

					# If we are running against the local host we need to process these tasks differently
					if ($Computer -eq $Env:COMPUTERNAME -or $Computer -eq "127.0.0.1" -or $Computer -eq "localhost") {
						# Execute the collection module on the local computer
						if ($CollectionModule.InputValues -ne "N/A") {
							# If there is an input parameter for this module, we need to reformat it to be passed to Invoke-Command
							[String[]]$Inputs = $CollectionModule.InputValues -split " "
							for ($i=0; $i -lt $Inputs.Count; $i++) {
								if ($Inputs[$i] -eq "null") {
									$Inputs[$i] = "`$null"
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -ErrorAction SilentlyContinue
							}
						}
					} else {
						if ($CollectionModule.InputValues -ne "N/A") {
							# If there is an input parameter for this module, we need to reformat it to be passed to Invoke-Command
							[String[]]$Inputs = $CollectionModule.InputValues -split " "
							for ($i=0; $i -lt $Inputs.Count; $i++) {
								if ($Inputs[$i] -eq "null") {
									$Inputs[$i] = "`$null"
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -ErrorAction SilentlyContinue
							}
						}
					}
					$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Job $($CollectionModule.Name) completed."
					if ($JobResults) {
						if (-not (Test-Path -Path "$OutputPath\$Computer")) {
							# Create a directory for the computer in the results folder
							New-Item -Path "$OutputPath\$Computer" -ItemType Directory -Force | Out-Null
						}
						switch ($CollectionModule.OutputType) {
							"txt" {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
							"csv" {
								$JobResults | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId | Export-Csv -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -NoTypeInformation -Force | Out-Null
							}
							"tsv" { Out-File -FilePath
								$JobResults | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Content -Path "$OutputPath\$Computer\$($CollectionModule.Name).$($CollectionModule.OutputType)" -Force | Out-Null
							}
							"xml" {
								[System.Xml.XmlDocument]$Temp = $JobResults
								$Temp.Save("$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)")
								Remove-Variable -Name "Temp" -ErrorAction SilentlyContinue
							}
							"bin" {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
							"zip" {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
							default {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
						}
					} else {
						$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : No results were returned from $($CollectionModule.Name)."
					}
					# Clean Up the Job Results variable
					Remove-Variable -Name JobResults -ErrorAction SilentlyContinue
					
					$SynchronizedHashtable.ProgressBarCurrent++
				}
				$SynchronizedHashtable.ProgressBarMessage += "Collection Module Processing complete for $Computer"
				#endregion Execute Modules
				
				#region Remove Binary Dependencies
				# Remove any binary dependencies that we copied to the target
				if ($CollectionModules.BinaryDependency -contains "True") {
					$CollectionModules.BinaryName | Where-Object { $_ -ne "N/A" } | Select-Object -Unique | ForEach-Object {
						$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Removing binary dependency $_ from the target."
						if (Test-Path -Path "$BinaryDirectory\$_") {
							if ($Computer -eq $Env:COMPUTERNAME -or $Computer -eq "127.0.0.1" -or $Computer -eq "localhost") {
								if ($Credential) {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows -Credential $Credential
								} else {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows
								}
							} else {
								if ($Credential) {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$ -Credential $Credential
								} else {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$
								}
							}
							Remove-Item -Path "Temp:\$BinaryDirectory\$_" -Force -ErrorAction SilentlyContinue
							Get-PSDrive -Name "Temp" | Remove-PSDrive
						}
					}
				}
				#endregion Remove Binary Dependencies
				
				#region Process Analysis Modules
					if ($AnalysisModules) {
					# Process each Analysis Module
					ForEach ($AnalysisModule in $AnalysisModules) {
						$SynchronizedHashtable.ProgressBarMessage += "Executing $($CollectionModule.Name) on $Computer"
						$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Starting Analysis module $($AnalysisModule.Name)"
						Invoke-Command -ComputerName "127.0.0.1" -FilePath $AnalysisModule.FilePath -ArgumentList "$OutputPath"
						$SynchronizedHashtable.ProgressBarCurrent++
					}
					$SynchronizedHashtable.ProgressBarMessage += "Analysis Module Processing complete for $Computer"
				}
				#endregion Process Analysis Modules
			} else {
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Target is offline. Cannot proceed with live response."
			}
			
			# Set Job Status to Complete
			$SynchronizedHashtable."JobStatus-$($Computer)" = "Complete"
		}
#endregion Live Response Scriptblock
		
#region Hunting Scriptblock
		# Define a ScriptBlock with Parameters for our Hunting process
		$HuntingProcess = {
			[CmdletBinding()]Param(
				[Parameter(Mandatory=$True)]
				[String[]]
				$Computers,
				
				[Parameter(Mandatory=$True)]
				[String]
				$OutputPath,
				
				[Parameter(Mandatory=$True)]
				[PSObject]
				$CollectionModule,
				
				[Parameter(Mandatory=$True)]
				[String]
				$BinaryDirectory,
				
				[Parameter(Mandatory=$True)]
				[System.Collections.HashTable]
				$SynchronizedHashtable,
				
				[Parameter(Mandatory=$False)]
				[PSObject[]]
				$AnalysisModules,
				
				[Parameter(Mandatory=$False)]
				[System.Management.Automation.PSCredential]
				$Credential
			)
			$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $($CollectionModule.Name) : Job Processing beginning."
			
			ForEach ($Computer in $Computers) {
				if (Test-Connection -ComputerName $Computer -Count 1 -Quiet) {
					$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Target system is online."
					
					#region Copy Binary Dependencies
					# Copy any binary dependcies to the targets
					if ($CollectionModule.BinaryDependency -eq "True" -and $CollectionModule.BinaryName -ne "N/A") {
						$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : $($CollectionModule.Name) has a binary dependency: $($CollectionModule.BinaryName). Copying to the target system."
						if (Test-Path -Path "$BinaryDirectory\$($CollectionModule.BinaryName)") {
							if ($Computer -eq $Env:COMPUTERNAME -or $Computer -eq "127.0.0.1" -or $Computer -eq "localhost") {
								if ($Credential) {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows -Credential $Credential
								} else {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows
								}
							} else {
								if ($Credential) {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$ -Credential $Credential
								} else {
									New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$
								}
							}
							Copy-Item -Path "$BinaryDirectory\$($CollectionModule.BinaryName)" -Destination Temp:\ -Recurse -ErrorAction SilentlyContinue
							Get-PSDrive -Name "Temp" | Remove-PSDrive
						}
					}
					#endregion Copy Binary Dependencies
					
					$SynchronizedHashtable.ProgressBarMessage += "Executing $($CollectionModule.Name) on $Computer"
					$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Executing collection module $($CollectionModule.Name)"

					# If we are running against the local host we need to process these tasks differently
					if ($Computer -eq $Env:COMPUTERNAME -or $Computer -eq "127.0.0.1" -or $Computer -eq "localhost") {
						# Execute the collection module on the local computer
						if ($CollectionModule.InputValues -ne "N/A") {
							# If there is an input parameter for this module, we need to reformat it to be passed to Invoke-Command
							[String[]]$Inputs = $CollectionModule.InputValues -split " "
							for ($i=0; $i -lt $Inputs.Count; $i++) {
								if ($Inputs[$i] -eq "null") {
									$Inputs[$i] = "`$null"
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -ErrorAction SilentlyContinue
							}
						}
					} else {
						if ($CollectionModule.InputValues -ne "N/A") {
							# If there is an input parameter for this module, we need to reformat it to be passed to Invoke-Command
							[String[]]$Inputs = $CollectionModule.InputValues -split " "
							for ($i=0; $i -lt $Inputs.Count; $i++) {
								if ($Inputs[$i] -eq "null") {
									$Inputs[$i] = "`$null"
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -ErrorAction SilentlyContinue
							}
						}
					}
					$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Job $($CollectionModule.Name) completed."
					if ($JobResults) {
						if (-not (Test-Path -Path "$OutputPath\$Computer")) {
							# Create a directory for the computer in the results folder
							New-Item -Path "$OutputPath\$Computer" -ItemType Directory -Force | Out-Null
						}
						switch ($CollectionModule.OutputType) {
							"txt" {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
							"csv" {
								$JobResults | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId | Export-Csv -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -NoTypeInformation -Force | Out-Null
							}
							"tsv" { Out-File -FilePath
								$JobResults | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Force | Out-Null
							}
							"xml" {
								[System.Xml.XmlDocument]$Temp = $JobResults
								$Temp.Save("$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)")
								Remove-Variable -Name "Temp" -ErrorAction SilentlyContinue
							}
							"bin" {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
							"zip" {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
							default {
								Set-Content -Path "$OutputPath\$Computer\$Computer-$($CollectionModule.Name).$($CollectionModule.OutputType)" -Value $JobResults -Force | Out-Null
							}
						}
					} else {
						$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : No results were returned from $($CollectionModule.Name)."
					}
					# Clean Up the Job Results variable
					Remove-Variable -Name JobResults -ErrorAction SilentlyContinue
					
					$SynchronizedHashtable.ProgressBarCurrent++
				}
				$SynchronizedHashtable.ProgressBarMessage += "Collection Module Processing complete for $Computer"
				
				#region Remove Binary Dependencies
				# Remove any binary dependencies that we copied to the target
				if ($CollectionModule.BinaryDependency -contains "True" -and $CollectionModule.BinaryName -ne "N/A") {
					$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Removing binary dependency $_ from the target."
					if (Test-Path -Path "$BinaryDirectory\$($CollectionModule.BinaryName)") {
						if ($Computer -eq $Env:COMPUTERNAME -or $Computer -eq "127.0.0.1" -or $Computer -eq "localhost") {
							if ($Credential) {
								New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows -Credential $Credential
							} else {
								New-PSDrive -Name "Temp" -PSProvider FileSystem -Root C:\Windows
							}
						} else {
							if ($Credential) {
								New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$ -Credential $Credential
							} else {
								New-PSDrive -Name "Temp" -PSProvider FileSystem -Root \\$Computer\Admin`$
							}
						}
						Remove-Item -Path "Temp:\$BinaryDirectory\$($CollectionModule.BinaryName)" -Force -ErrorAction SilentlyContinue
						Get-PSDrive -Name "Temp" | Remove-PSDrive
					}
				}
				#endregion Remove Binary Dependencies
				
				#region Process Analysis Modules
				if ($AnalysisModules) {
					# Process each Analysis Module
					ForEach ($AnalysisModule in $AnalysisModules) {
						$SynchronizedHashtable.ProgressBarMessage += "Executing $($CollectionModule.Name) on $Computer"
						$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Starting Analysis module $($AnalysisModule.Name)"
						
						Invoke-Command -ComputerName "127.0.0.1" -FilePath $AnalysisModule.FilePath -ArgumentList "$OutputPath\$Computer"
						$SynchronizedHashtable.ProgressBarCurrent++
					}
					$SynchronizedHashtable.ProgressBarMessage += "Analysis Module Processing complete for $Computer"
				}
				#endregion Process Analysis Modules
			} else {
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Target is offline. Cannot proceed with live response."
			}
			
			# Set Job Status to Complete
			$SynchronizedHashtable."JobStatus-$($Computer)" = "Complete"
		}
#endregion Hunting Scriptblock
		
		if ($JobType -eq "LiveResponse") {
#region Create Runspace Pool and Runspaces for Live Response
			# Create a Runspace pool with Single-Threaded apartments
			$RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1,$RunspaceCount)
			$RunspacePool.ApartmentState = "STA"
			$RunspacePool.Open()
			$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) Runspace Pool created with a max of $RunspaceCount runspaces."
		
			# Create an Array to store our Runspace Jobs
			$RunspaceJobArray = @()
		
			# Create PowerShell processes for each computer and add to our runspace pool
			ForEach ($Computer in $ComputerName) {
				$SynchronizedHashtable."JobStatus-$($Computer)" = "InProgress"
				$SynchronizedHashtable.ProgressBarMessage += "Creating a job in queue for $Computer"
				Write-Verbose "Creating a job in queue for $Computer"
				$RunspaceJob = [System.Management.Automation.PowerShell]::Create()
				$RunspaceJob.AddScript($LiveResponseProcess) | Out-Null
				$RunspaceJob.AddParameter("Computer", $Computer) | Out-Null
				$RunspaceJob.AddParameter("OutputPath", $SaveLocation) | Out-Null
				$RunspaceJob.AddParameter("CollectionModules", $SelectedCollectionModules) | Out-Null
				$RunspaceJob.AddParameter("BinaryDirectory", $BinaryDirectory) | Out-Null
				$RunspaceJob.AddParameter("SynchronizedHashtable",$SynchronizedHashtable) | Out-Null
				if ($SelectedAnalysisModules.Count -gt 0) {
					$RunspaceJob.AddParameter("AnalysisModules", $SelectedAnalysisModules) | Out-Null
				}
				if ($Credential) {
					$RunspaceJob.AddParameter("Credential", $Credentials) | Out-Null
				}
				$RunspaceJob.RunspacePool = $RunspacePool
				
				# Add the job to our Job Array
				$RunspaceJobArray += New-Object PSObject -Property @{ Pipe = $RunspaceJob; Result = $RunspaceJob.BeginInvoke() }
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) PowerShell process created for $Computer in Runspace pool."
			}
#endregion Create Runspace Pool and Runspaces for Live Response
		} elseif ($JobType -eq "Hunting") {
#region Create Runspace Pool and Runspaces For Hunting
			# Create a Runspace pool with Single-Threaded apartments
			$RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1,1)
			$RunspacePool.ApartmentState = "STA"
			$RunspacePool.Open()
			$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) Runspace Pool created with a max of 1 runspaces."
			# Create an Array to store our Runspace Jobs
			$RunspaceJobArray = @()
			
			# Create PowerShell processes for each collection module and add to our runspace pool
			ForEach ($SelectedCollectionModule in $SelectedCollectionModules) {
				$SynchronizedHashtable."JobStatus-$($SelectedCollectionModule).Name" = "InProgress"
				$SynchronizedHashtable.ProgressBarMessage += "Creating a job in queue for $($SelectedCollectionModule.Name)"
				Write-Verbose "Creating a job in queue for $($SelectedCollectionModule.Name)"
				$RunspaceJob = [System.Management.Automation.PowerShell]::Create()
				$RunspaceJob.AddScript($HuntingProcess) | Out-Null
				$RunspaceJob.AddParameter("Computers", $ComputerName) | Out-Null
				$RunspaceJob.AddParameter("OutputPath", $SaveLocation) | Out-Null
				$RunspaceJob.AddParameter("CollectionModule", $SelectedCollectionModule) | Out-Null
				$RunspaceJob.AddParameter("BinaryDirectory", $BinaryDirectory) | Out-Null
				$RunspaceJob.AddParameter("SynchronizedHashtable",$SynchronizedHashtable) | Out-Null
				if ($SelectedAnalysisModules.Count -gt 0) {
					$RunspaceJob.AddParameter("AnalysisModules", $SelectedAnalysisModules) | Out-Null
				}
				if ($Credential) {
					$RunspaceJob.AddParameter("Credential", $Credentials) | Out-Null
				}
				$RunspaceJob.RunspacePool = $RunspacePool

				# Add the job to our Job Array
				$RunspaceJobArray += New-Object PSObject -Property @{ Pipe = $RunspaceJob; Result = $RunspaceJob.BeginInvoke() }
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) PowerShell process created for $($SelectedCollectionModule.Name) in Runspace pool."
			}
#endregion Create Runspace Pool and Runspaces For Hunting
		}

#region Job Monitoring and Log Writing
		# Use LoggingCounter to maintain location in the progress messages to write entries to the log file
		[int]$LoggingCounter = 0
		
		# While loop to continue checking job status and write log entries to the log file
		while ($RunspaceJobArray.Result.IsCompleted -contains $False -and ($SynchronizedHashtable.Keys -like "JobStatus*" | ForEach-Object { $SynchronizedHashtable.$_ }) -Contains "InProgress") {
			# Create Progress Bar if not in GUI mode
			if (-not($GUI)) {
				Write-Progress -Activity "Performing Live Response" -Status $SynchronizedHashtable.ProgressBarMessage[$SynchronizedHashtable.ProgressBarMessage.Count - 1] -PercentComplete ($SynchronizedHashtable.ProgressBarCurrent / $SynchronizedHashtable.ProgressBarTotal * 100)
			}
			Start-Sleep -Seconds 1
		}
		
		# Write progress log messages to our log file
		while ($LoggingCounter -lt $SynchronizedHashtable.ProgressLogMessage.Count) {
			Add-Content -Path $LogPath -Value $SynchronizedHashtable.ProgressLogMessage[$LoggingCounter]
			$LoggingCounter++
			# Create Progress Bar if not in GUI mode
			if (-not($GUI)) {
				Write-Progress -Activity "Performing Live Response" -Status $SynchronizedHashtable.ProgressBarMessage[$SynchronizedHashtable.ProgressBarMessage.Count - 1] -PercentComplete ($SynchronizedHashtable.ProgressBarCurrent / $SynchronizedHashtable.ProgressBarTotal * 100)
			}
		}
#endregion Job Monitoring and Log Writing
		
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) ##############################"
		$RunspacePool.Dispose()
		$RunspacePool.Close()
		
		Invoke-Item -Path $SaveLocation
	}
} End {
#region Revert WinRM Fixes
	if ($RevertWinRMFix -eq "True") {
		ForEach ($WinRMChange in $WinRMChanges) {
			# If WinRM  wasn't running before, lets stop it
			if ($WinRMChange.ChangedWinRM) {
				if ($Credential) {
					(Get-WmiObject -ComputerName $WinRMChange.ComputerName -Class Win32_Service -Credential $Credentials -Filter "Name='WinRM'").StopService() | Out-Null
				} else {
					(Get-WmiObject -ComputerName $WinRMChange.ComputerName -Class Win32_Service -Filter "Name='WinRM'").StopService() | Out-Null
				}
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $($WinRMComputerName) : Stopped WinRM service to revert changes."
			}
			if ($Credential) {
				# Create a Remote Registry handle on the remote machine
				$ConnectionOptions = New-Object System.Management.ConnectionOptions
				$ConnectionOptions.UserName = $Credential.UserName
				$ConnectionOptions.SecurePassword = $Credential.Password
				
				$ManagementScope = New-Object System.Management.ManagementScope -ArgumentList \\$($WinRMChange.ComputerName)\Root\default, $ConnectionOptions -ErrorAction Stop
				$ManagementPath = New-Object System.Management.ManagementPath -ArgumentList "StdRegProv"
				
				$Reg = New-Object System.Management.ManagementClass -ArgumentList $ManagementScope, $ManagementPath, $null
			} else {
				$Reg = New-Object -TypeName System.Management.ManagementClass -ArgumentList \\$($WinRMChange.ComputerName)\Root\default:StdRegProv -ErrorAction Stop
			}
		
			# Set registry settings back to their original state
			if ($WinRMChange.ChangedAutoConfig) {
				if ($WinRMChange.ChangedAutoConfig.uValue -eq $null) {
					$Reg.DeleteValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","AllowAutoConfig")
				} else {
					$Reg.SetDWORDValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","AllowAutoConfig",$WinRMChange.ChangedAutoConfig)
				}
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $($WinRMChange.ComputerName) : AllowAutoConfig registry key changed back to original setting."
			}
		
			if ($WinRMChange.ChangedIPV4Value) {
				if ($WinRMChange.ChangedIPV4Value.uValue -eq $null) {
					$Reg.DeleteValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv4Filter")
				} else {
					$Reg.SetStringValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv4Filter",$WinRMChange.ChangedIPV4Value)
				}
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $($WinRMChange.ComputerName) : IPV4Filter registry key changed back to original setting."
			}
		
			if ($WinRMChange.ChangedIPV6Value -ne $null) {
				if ($WinRMChange.ChangedIPV6Value.uValue -eq $null) {
					$Reg.DeleteValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv6Filter")
				} else {
					$Reg.SetStringValue($HKLM,"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service","IPv6Filter",$WinRMChange.ChangedIPV6Value)
				}
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $($WinRMChange.ComputerName) : IPV6Filter registry key changed back to original setting."
			}
			$Reg.Dispose()
		}
	}
#endregion Revert WinRM Fixes
}