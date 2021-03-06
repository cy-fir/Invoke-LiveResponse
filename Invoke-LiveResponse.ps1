<#
.SYNOPSIS
    PowerShell based live response via WinRM, PowerShell Sessions, and Invoke-Command.

.DESCRIPTION
    This project is an off-shoot of Dave Hull's Kansa project. https://github.com/davehull/Kansa/
	I had some ideas for expanding the project and adding a GUI, so decided to create my own project.

.PARAMETER ComputerName
    Name or IP Address of the target computer(s).
	Can accept a comma separated list for multiple.

.PARAMETER CollectionModule
	Collection modules are the scripts that collect data. This parameter specifies the collection module(s) to execute against the target system.
	Can accept a comma separated list for multiple modules.
	Modules requiring input parameters are handled by enclosing the name and arguments in quotes, and adding a space after the module name, and between each argument.
	Check the examples for more information.

.PARAMETER AnalysisModule
	Analysis modules are scripts that run against the results from collection modules. These can be used to automate various analysis tasks.
	This parameter specifies the analysis module(s) to execute against the data retrieved from the collection modules.

.PARAMETER ModuleGroup
	There are a large number of modules and it isn't easy to remember all of those that you would prefer to use in an investigation.
	Module Groups are configurable groups of modules that are saved in a configuration file, so you don't have to remember.
	This parameter designates to read the configuration file and execute the designated Collection Modules and Analysis Modules that have been assigned to the module group.
	Check ModuleGroups.conf or the GitHub Wiki for more information.

.PARAMETER JobType
	This parameter changes the method used for processing jobs. This only has an impact when executing against a large number of target systems.
	Possible Values: LiveResponse, Hunting
	Default Value: LiveResponse
		LiveResponse: All modules are executed on the target system before moving on to the next target.
		Hunting: The module is exected against all target systems before moving on to the next module.

.PARAMETER ShowCollectionModules
	Queries the Collection Modules folder and returns a list of available modules, along with the Synopsis, output type, dependencies, and input parameters.

.PARAMETER ShowAnalysisModules
	Queries the Analysis Modules folder and returns a list of available modules along with the Synopsis.
	
.PARAMETER ShowModuleGroups
	Queries ModuleGroups.conf and provides a list of all configured module groups, along with description and the list of Collection and Analysis modules selected in the group.

.PARAMETER Config
	There are various configuration settings that can be changed.
	This switch, when used alone, displays the current configuration settings.
	When used with configuration switches it changes the settings.
	Available Configuration settings - SavePath, ConcurrentJobs, FixWinRM, RevertFixWinRM

.PARAMETER SavePath
	This switch can be used during execution for a one-time save path, or can be used with the Config switch to remember a save path.
	Default Save Path is .\Results.	

.PARAMETER WinRMFix
	If WinRM isn't functioning on the target host, Invoke-LiveResponse will attempt to fix it.
	You can use this switch to disable this functionality.
	Default Value: True
	Possible Values: True, False, Clear

.PARAMETER RevertWinRMFix
	If WinRM wasn't functioning on the target and we fixed it, we revert any changes after processing is complete.
	You can use this switch to disable this functionality, meaning any changes will remain.
	Default Value: True
	Possible Values: True, False, Clear

.PARAMETER ConcurrentJobs
	Changes the number of runspaces to create for processing. 1 runspace is used per target system.
	You can use this switch to change the number of simultaneous jobs.
	Default is 2.
	This value is ignored when processing with the Hunting Job Type.

.PARAMETER Credential
	This parameter can be used to either designate to use the Credential.ps1 plugin, or to use Get-Credential to prompt for credentials.
	If left empty it will use Get-Credential to prompt.

.PARAMETER PSCredential
	This parameter can accept a PSCredential object to modify credentials used.
	This is mainly available for the GUI plugin to handle credential processing on its own and directly pass the values collected.

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
	Show the available module groups
	Invoke-LiveResponse -ShowModuleGroups

.EXAMPLE
	Run the MalwareTriage collection group on the target computer
	Invoke-LiveResponse -ComputerName COMPUTERNAME -ModuleGroup MalwareTriage

.EXAMPLE
	Run the MalwareTriage collection group on target computer, then run the Get-Timeline analysis module against the results.
	Invoke-LiveResponse -ComputerName COMPUTERNAME -ModuleGroup MalwareTriage -AnalysisModule Timeline

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
    Last Modified: 02/01/2016
    Version: 1.3
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
	[Parameter(Mandatory=$False,ParameterSetName="LRModuleGroup")]
	[Parameter(Mandatory=$True,ParameterSetName="AnalysisOnly")]
	[String[]]
	$AnalysisModule,
	
	[Parameter(Mandatory=$True,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$True,ParameterSetName="LRModuleGroup")]
	[String[]]
	$ComputerName,

	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRModuleGroup")]
	[ValidateSet("LiveResponse","Hunting")]
	[String]
	$JobType,

	[Parameter(Mandatory=$True,ParameterSetName="ShowCollectionModules")]
	[Switch]
	$ShowCollectionModules,
	
	[Parameter(Mandatory=$True,ParameterSetName="ShowAnalysisModules")]
	[Switch]
	$ShowAnalysisModules,
	
	[Parameter(Mandatory=$True,ParameterSetName="ShowModuleGroups")]
	[Switch]
	$ShowModuleGroups,

	[Parameter(Mandatory=$True,ParameterSetName="Config")]
	[Switch]
	$Config,

	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRModuleGroup")]
	[String]
	$SavePath,
	
	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[ValidateSet("True","False","Clear")]
	[String]
	$WinRMFix,
	
	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[ValidateSet("True","False","Clear")]
	[String]
	$RevertWinRMFix,
	
	[Parameter(Mandatory=$False,ParameterSetName="Config")]
	[ValidateRange(0,99)]
	[Int]
	$ConcurrentJobs,
	
	[Parameter(Mandatory=$True,ParameterSetName="AnalysisOnly")]
	[String]
	$ResultsPath,
	
	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRModuleGroup")]
	[ValidateSet("Prompt","Plugin")]
	[String]
	$Credential,

	[Parameter(Mandatory=$False,ParameterSetName="LRCollectionModule")]
	[Parameter(Mandatory=$False,ParameterSetName="LRModuleGroup")]
	[System.Management.Automation.PSCredential]
	$PSCredential
)

# Create Dynamic Parameter with Validate Set (tab completion) for ModuleGroup switch.
DynamicParam {
	# Determine executing directory
	Try {
		$ScriptDirectory = Split-Path ($MyInvocation.MyCommand.Path) -ErrorAction Stop
	} Catch {
		$ScriptDirectory = (Get-Location).Path
	}
	
	$RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	
	# Check for ModuleGroups.conf. If it exists, import the Module Sets as a possible value for the ModuleGroup parameter.
	if (Test-Path -Path "$ScriptDirectory\ModuleGroups.conf") {
		$ModuleGroupAttrColl = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
		$ModuleGroupParamAttr = New-Object System.Management.Automation.ParameterAttribute
		$ModuleGroupParamAttr.Mandatory = $True
		$ModuleGroupParamAttr.ParameterSetName = "LRModuleGroup"
		$ModuleGroupAttrColl.Add($ModuleGroupParamAttr)
		[XML]$ModuleGroupsXML = Get-Content -Path "$ScriptDirectory\ModuleGroups.conf" -ErrorAction Stop
		$ModuleGroupValidateSet = @()
		$ModuleGroupsXML.ModuleGroups | Get-Member -MemberType Property | Select-Object -ExpandProperty Name | Where-Object { $_ -ne "#comment" } | ForEach-Object {
			$ModuleGroupValidateSet += $_
		}
		$ModuleGroupValSetAttr = New-Object System.Management.Automation.ValidateSetAttribute($ModuleGroupValidateSet)
		$ModuleGroupAttrColl.Add($ModuleGroupValSetAttr)
		$ModuleGroupRuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter("ModuleGroup", [string], $ModuleGroupAttrColl)
		$RuntimeParameterDictionary.Add("ModuleGroup", $ModuleGroupRuntimeParam)
	}
	
	if ($RuntimeParameterDictionary) {
		return $RuntimeParameterDictionary
	}
}

Begin {
	# This makes it so the dynamic variables are set and we can tab complete with them.
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
	
	# Create arrays to store selected modules, arguments, output types, etc.
	$SelectedCollectionModules = New-Object System.Collections.ArrayList
	$SelectedAnalysisModules =  New-Object System.Collections.ArrayList
	
#region Parameter Set Name switch
	switch ($PSCmdlet.ParameterSetName) {
		"Config" {
			Write-Verbose "Entering Config switch processing"
			# We need to either import the current configuration if it exists, or create a new one
			if (Test-Path -Path "$Env:APPDATA\Invoke-LiveResponse.conf") {
				# Check if configuration file exists. Import if it does
				[XML]$ConfigObject = Get-Content -Path "$Env:APPDATA\Invoke-LiveResponse.conf"
				[System.Xml.XmlElement]$ConfigurationElement = $ConfigObject.Configuration
			} else {
				# If configuration file doesn't exist, create it
				$ConfigObject = New-Object System.Xml.XmlDocument
				$ConfigurationElement = $ConfigObject.CreateElement("Configuration")
				$ConfigObject.AppendChild($ConfigurationElement) | Out-Null
			}
			
			# SavePath Configuration handling
			if ($SavePath) {
				if ($SavePath -eq "delete" -or $SavePath -eq "clear" -or $SavePath -eq "remove") {
					Write-Verbose "Clearing current save path preference"
					$ConfigurationElement.RemoveAttribute("SavePath")
				} else {
					Write-Verbose "Saving new save path preference: $SavePath"
					if ($ConfigObject.Configuration.SavePath) {
						$ConfigObject.Configuration.SavePath = $SavePath
					} else {
						$ConfigurationElement.SetAttribute("SavePath",$SavePath)
					}
				}
			}
			
			# WinRMFix Configuration handling
			if ($WinRMFix) {
				if ($WinRMFix -eq "Clear") {
					Write-Verbose "Clearing current WinRMFix preference"
					$ConfigurationElement.RemoveAttribute("WinRMFix")
				} else {
					Write-Verbose "Saving new WinRMFix preference: $WinRMFix"
					if ($ConfigObject.Configuration.WinRMFix) {
						$ConfigObject.Configuration.WinRMFix = $WinRMFix
					} else {
						$ConfigurationElement.SetAttribute("WinRMFix",$WinRMFix)
					}
				}
			}
			
			# RevertWinRMFix Configuration handling
			if ($RevertWinRMFix) {
				if ($RevertWinRMFix -eq "Clear") {
					Write-Verbose "Clearing current RevertWinRMFix preference"
					$ConfigurationElement.RemoveAttribute("RevertWinRMFix")
				} else {
					Write-Verbose "Saving new RevertWinRMFix preference: $RevertWinRMFix"
					if ($ConfigObject.Configuration.RevertWinRMFix) {
						$ConfigObject.Configuration.RevertWinRMFix = $RevertWinRMFix
					} else {
						$ConfigurationElement.SetAttribute("RevertWinRMFix",$RevertWinRMFix)
					}
				}
			}
			
			# ConcurrentJobs Configuration handling
			if (($ConcurrentJobs) -or $ConcurrentJobs -eq 0) {
				if ($ConcurrentJobs -eq 0) {
					Write-Verbose "Clearing current ConcurrentJobs preference"
					$ConfigurationElement.RemoveAttribute("ConcurrentJobs")
				} else {
					Write-Verbose "Saving new ConcurrentJobs preference: $ConcurrentJobs"
					if ($ConfigObject.Configuration.ConcurrentJobs) {
						$ConfigObject.Configuration.ConcurrentJobs = $ConcurrentJobs.ToString()
					} else {
						$ConfigurationElement.SetAttribute("ConcurrentJobs",$ConcurrentJobs.ToString())
					}
				}
			}

			# Save any configuration changes
			$ConfigObject.Save("$Env:APPDATA\Invoke-LiveResponse.conf")
			
			# Show the current configuration settings after any updates
			[PSCustomObject]@{
				SavePath = if ($ConfigObject.Configuration.SavePath) { $ConfigObject.Configuration.SavePath } else { ".\Results (Default)" }
				ConcurrentJobs = if ($ConfigObject.Configuration.ConcurrentJobs) { $ConfigObject.Configuration.ConcurrentJobs } else { "2 (Default)" }
				WinRMFix = if ($ConfigObject.Configuration.WinRMFix) { $ConfigObject.Configuration.WinRMFix } else { "True (Default)" }
				RevertWinRMFix = if ($ConfigObject.Configuration.RevertWinRMFix) { $ConfigObject.Configuration.RevertWinRMFix } else { "True (Default)" }
			}
			exit
		}
		
		"ShowCollectionModules" {
			Write-Verbose "Entering ShowCollectionModules switch processing"
			$ConfirmPreference = "none"
			Get-ChildItem -Path "$ScriptDirectory\CollectionModules" -Filter *.ps1 -Recurse | Select-Object -Property Name, FullName | ForEach-Object {
				# Set some default values before parsing directives
				[String]$OutputType="txt"
				$BinaryDependency=$False
				[String]$BinaryName="N/A"
				[String]$InputParameters="N/A"
				
				# Parse the Directives from the Collection Module
				Get-Content -Path $_.FullName | Select-String -CaseSensitive -Pattern "^(OUTPUT|BINARY|INPUT)" | ForEach-Object {
					if ($_ -match "(^OUTPUT) (.*)") {
						[String]$OutputType=$matches[2]
					}
					if ($_ -match "(^BINARY) (.*)") {
						$BinaryDependency=$True
						[String]$BinaryName=$matches[2]
					}
					if ($_ -match "(^INPUT) (.*)") {
						[String]$InputParameters = $matches[2]
					}
				}
				
				[PSCustomObject]@{
					Name = $_.Name
					OutputType = $OutputType
					BinaryDependency = $BinaryDependency
					BinaryName = $BinaryName
					InputParameters = $InputParameters
					Description = (Get-Help $_.FullName | Select-Object -ExpandProperty Synopsis)
					FilePath = $_.FullName
				}
			}
		}
		
		"ShowModuleGroups" {
			Write-Verbose "Entering ShowModuleGroups switch processing"
			# Check for ModuleGroups.conf and read contents
			Write-Verbose -Message "Checking for ModuleGroups.conf file to import settings."
			if (Test-Path -Path "$ScriptDirectory\ModuleGroups.conf") {
				[XML]$ModuleGroupsXML = Get-Content -Path "$ScriptDirectory\ModuleGroups.conf"
				Write-Verbose -Message "ModuleGroups.conf found and imported."
				$ModuleGroupsXML.ModuleGroups | Get-Member -MemberType Property | Select-Object -ExpandProperty Name | Where-Object { $_ -ne "#comment" } | ForEach-Object {
					# Format the Collection/Analysis Module names and Input Values
					$CollectionModules = $ModuleGroupsXML.ModuleGroups.$_.CollectionModule | ForEach-Object { "$($_.Name) $($_.InputValues)" }
					$AnalysisModules = $ModuleGroupsXML.ModuleGroups.$_.AnalysisModule | ForEach-Object { "$($_.Name) $($_.InputValues)" }
					# For each collection group, create a custom object and populate metadata
					[PSCustomObject]@{
						Name = $_
						Description = $ModuleGroupsXML.ModuleGroups.$_.Description
						CollectionModules = $CollectionModules.Trim() -join ", "
						AnalysisModules = $AnalysisModules.Trim() -join ", "
					}
				}
			} else {
				Write-Verbose -Message "ModuleGroups.conf not found."
			}
		}
		
		"ShowAnalysisModules" {
			Write-Verbose "Entering ShowAnalysisModules switch processing"
			$ConfirmPreference = "none"
			Get-ChildItem -Path "$ScriptDirectory\AnalysisModules" -Filter *.ps1 -Recurse | Select-Object -Property Name, FullName | ForEach-Object {
				[PSCustomObject]@{
					Name = $_.Name
					Description = (Get-Help $_.FullName | Select-Object -ExpandProperty Synopsis)
					FilePath = $_.FullName
				}
			}
		}
		
		"LRCollectionModule" {
			Write-Verbose "Entering LRCollectionModule switch processing"
			# This section of code only sets the SelectedCollectionModules variable. Execution code is later
			
			# Process each supplied collection module
			$CollectionModule | ForEach-Object {
				$InputValues = "N/A"
				# Split module name from any input values
				if ($_ -match "([^\s]+)(\s([^s]+)?)?") {
					$Name = $matches[1]
					if ($Name -notmatch ".+\.ps1") {
						$Name = $Name + ".ps1"
					}
					[String[]]$InputValues = $matches[3] -split " "
				}
				
				# Get information about the module directly from the script
				if (Get-ChildItem -Path "$ScriptDirectory\CollectionModules\" -File $Name -Recurse) {
					# Set some default values before parsing directives
					[String]$OutputType="txt"
					$BinaryDependency=$False
					[String]$BinaryName="N/A"
					
					# Parse the Directives from the collection modules
					Get-Content -Path "$ScriptDirectory\CollectionModules\$Name" | Select-String -CaseSensitive -Pattern "^(OUTPUT|BINARY|INPUT)" | ForEach-Object {
						if ($_ -match "(^OUTPUT) (.*)") {
							[String]$OutputType=$matches[2]
						}
						if ($_ -match "(^BINARY) (.*)") {
							$BinaryDependency=$True
							[String]$BinaryName=$matches[2]
						}
						if ($_ -match "(^INPUT) (.*)") {
							[String[]]$InputParameters = $matches[2] -split "," | ForEach-Object { $_.Trim() }
						}
		            }
					
					# Gather information about the collection module that will be needed later during processing
					$SelectedCollectionModules.Add([PSCustomObject]@{
						Name = $Name
						FilePath = (Get-ChildItem -Path "$ScriptDirectory\CollectionModules\" -File $Name -Recurse).FullName
						InputValues = $InputValues
						InputParameters = $InputParameters
						OutputType = $OutputType
						BinaryDependency = $BinaryDependency
						BinaryName = $BinaryName
					}) | Out-Null
				} else {
					Write-Host "Collection Module `"$_`" does not exist"
				}
			}
		}
		
		"LRModuleGroup" {
			Write-Verbose "Entering LRModuleGroup switch processing"
			# This section of code only sets the SelectedCollectionModules variable. Execution code is later
			
			# Check for ModuleGroups.conf and read contents
			Write-Verbose -Message "Checking for ModuleGroups.conf file to import settings."
			if (Test-Path -Path "$ScriptDirectory\ModuleGroups.conf") {
				[XML]$ModuleGroupsXML = Get-Content -Path "$ScriptDirectory\ModuleGroups.conf" -ErrorAction Stop
				Write-Verbose -Message "ModuleGroups.conf found and imported."
			} else {
				Write-Verbose -Message "ModuleGroups.conf not found."
			}
			
			if ($ModuleGroupsXML.ModuleGroups.$ModuleGroup.CollectionModule) {
				$AvailableModules = Get-ChildItem -Path 'C:\Users\DHowell\Google Drive\Scripts\Invoke-LiveResponse\CollectionModules' -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
				$ModuleGroupsXML.ModuleGroups.$ModuleGroup.CollectionModule | ForEach-Object {
					# Verify the collection module exists before adding it to selected collection modules list
					$FullPath = $AvailableModules -like "*$($_.Name)"
					if ($FullPath) {
						# Set some default values before parsing directives
						[String]$OutputType="txt"
						$BinaryDependency=$False
						[String]$BinaryName="N/A"
						$InputParameters = "N/A"
						if ($_.InputValues -eq "") {
							[String]$InputValues = "N/A"
						} else {
							[String[]]$_.InputValues -split " "
						}
						
						# Parse the Directives from the collection modules
						Get-Content -Path $FullPath | Select-String -CaseSensitive -Pattern "^(OUTPUT|BINARY|INPUT)" | ForEach-Object {
							if ($_ -match "(^OUTPUT) (.*)") {
								[String]$OutputType=$matches[2]
							}
							if ($_ -match "(^BINARY) (.*)") {
								$BinaryDependency=$True
								[String]$BinaryName=$matches[2]
							}
							if ($_ -match "(^INPUT) (.*)") {
								[String[]]$InputParameters = $matches[2] -split "," | ForEach-Object { $_.Trim() }
							}
			            }
						
						# Gather information about the collection module that will be needed later during processing
						$SelectedCollectionModules.Add([PSCustomObject]@{
							Name = $_.Name
							FilePath = (Get-ChildItem -Path "$ScriptDirectory\CollectionModules\" -File $_.Name -Recurse).FullName
							InputValues = $InputValues
							InputParameters = $InputParameters
							OutputType = $OutputType
							BinaryDependency = $BinaryDependency
							BinaryName = $BinaryName
						}) | Out-Null
					}
				}
			}
			
			if ($ModuleGroupsXML.ModuleGroups.$ModuleGroup.AnalysisModule) {
				$ModuleGroupsXML.ModuleGroups.$ModuleGroup.AnalysisModule | ForEach-Object {
					# Verify the analysis module exists before adding it to selected analysis modules list
					$FullPath = Get-ChildItem -Path "$ScriptDirectory\AnalysisModules" -Filter $_.Name -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
					if ($FullPath) {
						$SelectedAnalysisModules.Add([PSCustomObject]@{
							Name = $_.Name
							FilePath = $FullPath
						}) | Out-Null
					}
				}
			}
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
				$SelectedAnalysisModules.Add([PSCustomObject]@{
					Name = $Name
					FilePath = "$ScriptDirectory\AnalysisModules\$Name"
				}) | Out-Null
			} else {
				Write-Host "Analysis Module `"$_`" does not exist"
			}
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
		
		#region Credential switch handling
		
		# If the Credential switch was specified, run the Credentials plugin or prompt for Credentials using Get-Credential
		if ($Credential -eq "Prompt") {
			Write-Verbose "Credential switch used to designate prompt for credentials."
			[System.Management.Automation.PSCredential]$Credentials = Get-Credential -Message "Enter credentials for Invoke-LiveResponse"
		} elseif ($Credential -eq "Plugin") {
			Write-Verbose "Credential switch used to desginate use credentials plugin."
			if (Test-Path -Path "$ScriptDirectory\Plugins\Credentials.ps1") {
				[System.Management.Automation.PSCredential]$Credentials = & "$ScriptDirectory\Plugins\Credentials.ps1"
			}
		}
		
		if ($PSCredential) {
			[System.Management.Automation.PSCredential]$Credentials = $PSCredential
		}
		
		#endregion Credential switch handling
		
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
		ForEach ($SelectedCollectionModule in $SelectedCollectionModules) {
			if ($SelectedCollectionModule.InputParameters -ne "N/A" -and $SelectedCollectionModule.InputValues -ne "N/A") {
				Add-Content -Path $LogPath -Value "Name: $($SelectedCollectionModule.Name) - Parameters: $($SelectedCollectionModule.InputParameters) - Values: $($SelectedCollectionModule.InputValues)"
			} else {
				Add-Content -Path $LogPath -Value "Name: $($SelectedCollectionModule.Name)"
			}
		}
		Add-Content -Path $LogPath -Value $SelectedCollectionModules.Name
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) Analysis Modules Selected:"
		Add-Content -Path $LogPath -Value $SelectedAnalysisModules.Name
		Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) ##############################"
#endregion Preparing for Live Response

		#region Test/Fix WinRM
		
		# If WinRMFix is enabled, test WinRM and attempt to fix if issues are found
		if ($WinRMFix -eq "True") {
			# Array to store changes for reverting the changes later
			$WinRMChanges = New-Object System.Collections.ArrayList
			
			ForEach ($Computer in $ComputerName) {
				Write-Verbose "Testing WinRM on $Computer"
				Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Testing WinRM."
				if (-not ($Computer -eq "localhost" -or $Computer -eq "127.0.0.1" -or $Computer -eq $Env:COMPUTERNAME)) {
					Try {
						# First, test PowerShell remoting. If it fails execution will cut to the Catch section to enable WinRM
						if ($Credentials) {
							Invoke-Command -ComputerName $Computer -ScriptBlock {1} -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credentials -ErrorAction Stop | Out-Null
						} else {
							Invoke-Command -ComputerName $Computer -ScriptBlock {1} -SessionOption (New-PSSessionOption -NoMachineProfile) -ErrorAction Stop | Out-Null
						}
						Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : WinRM seems to be functioning."
					} Catch {
						$TempObject = New-Object PSObject
						$TempObject | Add-Member -MemberType NoteProperty -Name "ComputerName" -Value $Computer
						
						Write-Verbose "WinRM doesn't appear to be functioning on $Computer. Attempting to fix it."
						Add-Content -Path $LogPath -Value "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : WinRM doesn't appear to be functioning. Attempting to fix/enable it."
						# Verify WinRM Service is running. If it isn't, note the state and start the service.
						if ($Credentials) {
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
						
						if ($Credentials) {
							# Create a Remote Registry handle on the remote machine
							$ConnectionOptions = New-Object System.Management.ConnectionOptions
							$ConnectionOptions.UserName = $Credentials.UserName
							$ConnectionOptions.SecurePassword = $Credentials.Password
							
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
						if ($Credentials) {
							(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Credential $Credentials -Filter "Name='WinRM'").StopService() | Out-Null
							(Get-WmiObject -ComputerName $Computer -Class Win32_Service -Credential $Credentials -Filter "Name='WinRM'").StartService() | Out-Null
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
							if ($CollectionModule.InputValues.Count -le $CollectionModule.InputParameters.Count) {
								$Inputs = @()
								for ($i=0; $i -lt $CollectionModule.InputValues.Count; $i++) {
									if ($CollectionModule.InputValues[$i] -eq "null") {
										$Inputs += "`$null"
									} elseif ($CollectionModule.InputParameters[$i] -match "^(\[(.+)\])?.+") {
										# Use Regex to parse the parameter name, and type (if present)
										if ($matches[1]) {
											New-Variable -Name TempVar -Value ($CollectionModule.InputValues[$i] -as ($matches[2] -as [type]))
											$Inputs += $TempVar
											Remove-Variable -Name TempVar
										} else {
											$Inputs += $CollectionModule.InputValues[$i]
										}
									}
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $Computer : Executing collection module $($CollectionModule.Name) with Input Values: $($Inputs -join `", `")"
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ErrorAction SilentlyContinue
							}
						}
					} else {
						if ($CollectionModule.InputValues -ne "N/A") {
							# If there is an input parameter for this module, we need to reformat it to be passed to Invoke-Command
							if ($CollectionModule.InputValues.Count -le $CollectionModule.InputParameters.Count) {
								$Inputs = @()
								for ($i=0; $i -lt $CollectionModule.InputValues.Count; $i++) {
									if ($CollectionModule.InputValues[$i] -eq "null") {
										$Inputs += "`$null"
									} elseif ($CollectionModule.InputParameters[$i] -match "^(\[(.+)\])?.+") {
										# Use Regex to parse the parameter name, and type (if present)
										if ($matches[1]) {
											New-Variable -Name TempVar -Value ($CollectionModule.InputValues[$i] -as ($matches[2] -as [type]))
											$Inputs += $TempVar
											Remove-Variable -Name TempVar
										} else {
											$Inputs += $CollectionModule.InputValues[$i]
										}
									}
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ErrorAction SilentlyContinue
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
						Invoke-Command -ComputerName "127.0.0.1" -FilePath $AnalysisModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ArgumentList "$OutputPath"
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
							if ($CollectionModule.InputValues.Count -le $CollectionModule.InputParameters.Count) {
								$Inputs = @()
								for ($i=0; $i -lt $CollectionModule.InputValues.Count; $i++) {
									if ($CollectionModule.InputValues[$i] -eq "null") {
										$Inputs += "`$null"
									} elseif ($CollectionModule.InputParameters[$i] -match "^(\[(.+)\])?.+") {
										# Use Regex to parse the parameter name, and type (if present)
										if ($matches[1]) {
											New-Variable -Name TempVar -Value ($CollectionModule.InputValues[$i] -as ($matches[2] -as [type]))
											$Inputs += $TempVar
											Remove-Variable -Name TempVar
										} else {
											$Inputs += $CollectionModule.InputValues[$i]
										}
									}
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName "127.0.0.1" -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ErrorAction SilentlyContinue
							}
						}
					} else {
						if ($CollectionModule.InputValues -ne "N/A") {
							# If there is an input parameter for this module, we need to reformat it to be passed to Invoke-Command
							if ($CollectionModule.InputValues.Count -le $CollectionModule.InputParameters.Count) {
								$Inputs = @()
								for ($i=0; $i -lt $CollectionModule.InputValues.Count; $i++) {
									if ($CollectionModule.InputValues[$i] -eq "null") {
										$Inputs += "`$null"
									} elseif ($CollectionModule.InputParameters[$i] -match "^(\[(.+)\])?.+") {
										# Use Regex to parse the parameter name, and type (if present)
										if ($matches[1]) {
											New-Variable -Name TempVar -Value ($CollectionModule.InputValues[$i] -as ($matches[2] -as [type]))
											$Inputs += $TempVar
											Remove-Variable -Name TempVar
										} else {
											$Inputs += $CollectionModule.InputValues[$i]
										}
									}
								}
							}
							# Execute the module
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ArgumentList $Inputs -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ArgumentList $Inputs -ErrorAction SilentlyContinue
							}
						} else {
							if ($Credential) {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential -ErrorAction SilentlyContinue
							} else {
								$JobResults = Invoke-Command -ComputerName $Computer -FilePath $CollectionModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ErrorAction SilentlyContinue
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
						
						Invoke-Command -ComputerName "127.0.0.1" -FilePath $AnalysisModule.FilePath -SessionOption (New-PSSessionOption -NoMachineProfile) -ArgumentList "$OutputPath\$Computer"
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
				if ($Credentials) {
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
				if ($Credentials) {
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
				if ($Credentials) {
					(Get-WmiObject -ComputerName $WinRMChange.ComputerName -Class Win32_Service -Credential $Credentials -Filter "Name='WinRM'").StopService() | Out-Null
				} else {
					(Get-WmiObject -ComputerName $WinRMChange.ComputerName -Class Win32_Service -Filter "Name='WinRM'").StopService() | Out-Null
				}
				$SynchronizedHashtable.ProgressLogMessage += "$(Get-Date -Format yyyyMMdd-H:mm:ss) $($WinRMComputerName) : Stopped WinRM service to revert changes."
			}
			if ($Credentials) {
				# Create a Remote Registry handle on the remote machine
				$ConnectionOptions = New-Object System.Management.ConnectionOptions
				$ConnectionOptions.UserName = $Credentials.UserName
				$ConnectionOptions.SecurePassword = $Credentials.Password
				
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