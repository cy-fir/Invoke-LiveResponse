<#
.SYNOPSIS 
	Returns WMI Event Consumer information, which has been used for malware persistence.

.DESCRIPTION
	Looks for EventConsumer, EventFilter, and FilterToConsumerBinding.  Uses FilterToConsumerBinding to correlate the EventConsumer and EventFilter if possible.
	
.NOTES
	Author: David Howell
	Modified: 04/02/2015

OUTPUT csv
#>

$ResultArray=@()

$EventConsumers = Get-WMIObject -Namespace root\subscription -Class __EventConsumer -ErrorAction SilentlyContinue | Select-Object -Property *
$EventFilters = Get-WmiObject -Namespace root\subscription -Class __EventFilter -ErrorAction SilentlyContinue | Select-Object -Property *
$FilterConsumerBindings = Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue | Select-Object -Property Consumer, DeliverSynchronously, DeliveryQoS, Filter, MaintainSecurityContext, SlowDownProviders

# Start with FilterToConsumerBindings, correlate the Filter and Consumer, and add to our array
ForEach ($FilterConsumerBinding in $FilterConsumerBindings) {
	# Quick Easy way to create a Custom Object
	$CustomObject = [PSCustomObject]@{
		DeliveryQoS = $FilterConsumerBinding.DeliveryQoS
		DeliverSynchronously = $FilterConsumerBinding.DeliverSynchronously
		MaintainSecurityContext = $FilterConsumerBinding.MaintainSecurityContext
		SlowDownProviders = $FilterConsumerBinding.SlowDownProviders
		CreatorSID = $FilterConsumerBinding.CreatorSID -join ""
	}
	
	# Loop through EventFilters, find the related Filter, add the important values of the Filter to our custom object
	ForEach ($EventFilter in $EventFilters) {
		if ($EventFilter.__RELPATH -eq $FilterConsumerBinding.Filter) {
			$CustomObject | Add-Member -MemberType NoteProperty -Name FilterName -Value $EventFilter.Name
			$CustomObject | Add-Member -MemberType NoteProperty -Name EventAccess -Value $EventFilter.EventAccess
			$CustomObject | Add-Member -MemberType NoteProperty -Name EventNamespace -Value $EventFilter.EventNamespace
			$CustomObject | Add-Member -MemberType NoteProperty -Name Query -Value $EventFilter.Query
			$CustomObject | Add-Member -MemberType NoteProperty -Name QueryLanguage -Value $EventFilter.QueryLanguage
		}	
	}
	
	# Loop through EventConsumers, find the related Consumer, add the important values for that class to our custom object
	ForEach ($EventConsumer in $EventConsumers) {
		if ($EventConsumer.__RELPATH -eq $FilterConsumerBinding.Consumer) {
			$CustomObject | Add-Member -MemberType NoteProperty -Name ConsumerName -Value $EventConsumer.Name
			$CustomObject | Add-Member -MemberType NoteProperty -Name ConsumerType -Value $EventConsumer.__CLASS
			# Switch based on the Class of the EventConsumer, since it can be a few different options and each has different important fields
			switch ($EventConsumer.__CLASS) {
				"CommandLineEventConsumer" {
					$CustomObject | Add-Member -MemberType NoteProperty -Name MachineName -Value $EventConsumer.MachineName
					$CustomObject | Add-Member -MemberType NoteProperty -Name CommandLineTemplate -Value $EventConsumer.CommandLineTemplate
					$CustomObject | Add-Member -MemberType NoteProperty -Name WorkingDirectory -Value $EventConsumer.WorkingDirectory
					$CustomObject | Add-Member -MemberType NoteProperty -Name CreateNewConsole -Value $EventConsumer.CreateNewConsole
					$CustomObject | Add-Member -MemberType NoteProperty -Name CreateNewProcessGroup -Value $EventConsumer.CreateNewProcessGroup
					$CustomObject | Add-Member -MemberType NoteProperty -Name DesktopName -Value $EventConsumer.DesktopName
					$CustomObject | Add-Member -MemberType NoteProperty -Name ExecutablePath -Value $EventConsumer.ExecutablePath
					$CustomObject | Add-Member -MemberType NoteProperty -Name Priority -Value $EventConsumer.Priority
					$CustomObject | Add-Member -MemberType NoteProperty -Name RunInteractively -Value $EventConsumer.RunInteractively
					$CustomObject | Add-Member -MemberType NoteProperty -Name ShowWindowCommand -Value $EventConsumer.ShowWindowCommand
					$CustomObject | Add-Member -MemberType NoteProperty -Name WindowTitle -Value $EventConsumer.WindowTitle
				}
				
				"NTEventLogEventConsumer" {
					$CustomObject | Add-Member -MemberType NoteProperty -Name MachineName -Value $EventConsumer.MachineName
					$CustomObject | Add-Member -MemberType NoteProperty -Name Category -Value $EventConsumer.Category
					$CustomObject | Add-Member -MemberType NoteProperty -Name EventID -Value $EventConsumer.EventID
					$CustomObject | Add-Member -MemberType NoteProperty -Name EventType -Value $EventConsumer.EventType
					$CustomObject | Add-Member -MemberType NoteProperty -Name InsertionStringTemplates -Value $EventConsumer.InsertionStringTemplates
					$CustomObject | Add-Member -MemberType NoteProperty -Name MaximumQueueSize -Value $EventConsumer.MaximumQueueSize
					$CustomObject | Add-Member -MemberType NoteProperty -Name NameOfRawDataProperty -Value $EventConsumer.NameOfRawDataProperty
					$CustomObject | Add-Member -MemberType NoteProperty -Name NameOfUserSIDProperty -Value $EventConsumer.NameOfUserSIDProperty
					$CustomObject | Add-Member -MemberType NoteProperty -Name NumberOfInsertionStrings -Value $EventConsumer.NumberOfInsertionStrings
					$CustomObject | Add-Member -MemberType NoteProperty -Name SourceName -Value $EventConsumer.SourceName
					$CustomObject | Add-Member -MemberType NoteProperty -Name UNCServerName -Value $EventConsumer.UNCServerName
				}
				
				"LogFileEventConsumer" {
					$CustomObject | Add-Member -MemberType NoteProperty -Name Filename -Value $EventConsumer.Filename
					$CustomObject | Add-Member -MemberType NoteProperty -Name MaximumFileSize -Value $EventConsumer.MaximumFileSize
					$CustomObject | Add-Member -MemberType NoteProperty -Name Text -Value $EventConsumer.Text
				}
				
				"ActiveScriptEventConsumer" {
					$CustomObject | Add-Member -MemberType NoteProperty -Name KillTimeout  -Value $EventConsumer.KillTimeout 
					$CustomObject | Add-Member -MemberType NoteProperty -Name MachineName -Value $EventConsumer.MachineName
					$CustomObject | Add-Member -MemberType NoteProperty -Name MaximumQueueSize -Value $EventConsumer.MaximumQueueSize
					$CustomObject | Add-Member -MemberType NoteProperty -Name ScriptingEngine -Value $EventConsumer.ScriptingEngine
					$CustomObject | Add-Member -MemberType NoteProperty -Name ScriptFileName -Value $EventConsumer.ScriptFileName
					$CustomObject | Add-Member -MemberType NoteProperty -Name ScriptText -Value $EventConsumer.ScriptText
				}
				
				"SMTPEventConsumer" {
					$CustomObject | Add-Member -MemberType NoteProperty -Name BccLine -Value $EventConsumer.BccLine
					$CustomObject | Add-Member -MemberType NoteProperty -Name CcLine -Value $EventConsumer.CcLine
					$CustomObject | Add-Member -MemberType NoteProperty -Name FromLine -Value $EventConsumer.FromLine
					$CustomObject | Add-Member -MemberType NoteProperty -Name Message -Value $EventConsumer.Message
					$CustomObject | Add-Member -MemberType NoteProperty -Name ReplyToLine -Value $EventConsumer.ReplyToLine
					$CustomObject | Add-Member -MemberType NoteProperty -Name SMTPServer -Value $EventConsumer.SMTPServer
					$CustomObject | Add-Member -MemberType NoteProperty -Name Subject -Value $EventConsumer.Subject
					$CustomObject | Add-Member -MemberType NoteProperty -Name ToLine -Value $EventConsumer.ToLine
					$CustomObject | Add-Member -MemberType NoteProperty -Name HeaderFields -Value $EventConsumer.HeaderFields
				}
			}		
		}
	}
	$ResultArray += $CustomObject
}

# Loop through the Event Filters and make sure they are all accounted for.  Some may exist without a FilterToConsumerBinding
ForEach ($RemainingFilter in $EventFilters) {
	# Start with false value, and set it to true when we know it's already been added
	$AlreadyAdded=$False
	ForEach ($Result in $ResultArray) {
		if ($Result.FilterName -eq $RemainingFilter.Name) {
			$AlreadyAdded=$True
		}
	}
	
	# If it hasn't been added, lets create our object and add it
	if ($AlreadyAdded -eq $false) {
		$CustomObject = "" | Select-Object -Property FilterName, EventAccess, EventNamespace, Query, QueryLanguage
		$CustomObject.FilterName = $RemainingFilter.Name
		$CustomObject.EventAccess = $RemainingFilter.EventAccess
		$CustomObject.EventNamespace = $RemainingFilter.EventNamespace
		$CustomObject.Query = $RemainingFilter.Query
		$CustomObject.QueryLanguage = $RemainingFilter.QueryLanguage
		$ResultArray += $CustomObject
	
	}
}

# Loop through the Event Consumers and make sure they are all accounted for.  Some may exist without a FilterToConsumerBinding
ForEach ($RemainingConsumer in $EventConsumers) {
	# Start with false value, and set it to true when we know it's already been added
	$AlreadyAdded=$False
	ForEach ($Result in $ResultArray) {
		if ($Result.ConsumerName -eq $RemainingConsumer.Name) {
			$AlreadyAdded=$True
		}
	}
	
	# If it hasn't been added, lets create our object and add it
	if ($AlreadyAdded -eq $false) {
		# Switch based on the Class of the EventConsumer, since it can be a few different options and each has different important fields
		switch ($RemainingConsumer.__CLASS) {
			"CommandLineEventConsumer" {
				$CustomObject = "" | Select-Object -Property ConsumerName, ConsumerType, MachineName, CommandLineTemplate, WorkingDirectory, CreateNewConsole, CreateNewProcessGroup, DesktopName, ExecutablePath, Priority, RunInteractively, ShowWindowCommand, WindowTitle
				$CustomObject.ConsumerName = $RemainingConsumer.Name
				$CustomObject.ConsumerType = $RemainingConsumer.__CLASS
				$CustomObject.MachineName = $RemainingConsumer.MachineName
				$CustomObject.CommandLineTemplate = $RemainingConsumer.CommandLineTemplate
				$CustomObject.WorkingDirectory = $RemainingConsumer.WorkingDirectory
				$CustomObject.CreateNewConsole = $RemainingConsumer.CreateNewConsole
				$CustomObject.CreateNewProcessGroup = $RemainingConsumer.CreateNewProcessGroup
				$CustomObject.DesktopName = $RemainingConsumer.DesktopName
				$CustomObject.ExecutablePath = $RemainingConsumer.ExecutablePath
				$CustomObject.Priority = $RemainingConsumer.Priority
				$CustomObject.RunInteractively = $RemainingConsumer.RunInteractively
				$CustomObject.ShowWindowCommand = $RemainingConsumer.ShowWindowCommand
				$CustomObject.WindowTitle = $RemainingConsumer.WindowTitle
			}
			
			"NTEventLogEventConsumer" {
				$CustomObject = "" | Select-Object -Property ConsumerName, ConsumerType, MachineName, Category, EventID, EventType, InsertionStringTemplates, MaximumQueueSize, NameOfRawDataProperty, NameOfUserSIDProperty, NumberOfInsertionStrings, SourceName, UNCServerName
				$CustomObject.ConsumerName = $RemainingConsumer.Name
				$CustomObject.ConsumerType = $RemainingConsumer.__CLASS
				$CustomObject.MachineName = $RemainingConsumer.MachineName
				$CustomObject.Category = $RemainingConsumer.Category
				$CustomObject.EventID = $RemainingConsumer.EventID
				$CustomObject.EventType = $RemainingConsumer.EventType
				$CustomObject.InsertionStringTemplates = $RemainingConsumer.InsertionStringTemplates
				$CustomObject.MaximumQueueSize = $RemainingConsumer.MaximumQueueSize
				$CustomObject.NameOfRawDataProperty = $RemainingConsumer.NameOfRawDataProperty
				$CustomObject.NameOfUserSIDProperty = $RemainingConsumer.NameOfUserSIDProperty
				$CustomObject.NumberOfInsertionStrings = $RemainingConsumer.NumberOfInsertionStrings
				$CustomObject.SourceName = $RemainingConsumer.SourceName
				$CustomObject.UNCServerName = $RemainingConsumer.UNCServerName
			}
			
			"LogFileEventConsumer" {
				$CustomObject = "" | Select-Object -Property ConsumerName, ConsumerType, Filename, MaximumFileSize, Text
				$CustomObject.ConsumerName = $RemainingConsumer.Name
				$CustomObject.ConsumerType = $RemainingConsumer.__CLASS
				$CustomObject.Filename = $RemainingConsumer.Filename
				$CustomObject.MaximumFileSize = $RemainingConsumer.MaximumFileSize
				$CustomObject.Text = $RemainingConsumer.Text
			}
			
			"ActiveScriptEventConsumer" {
				$CustomObject = "" | Select-Object -Property ConsumerName, ConsumerType, KillTimeout, MachineName, MaximumQueueSize, ScriptingEngine, ScriptFileName, ScriptText
				$CustomObject.ConsumerName = $RemainingConsumer.Name
				$CustomObject.ConsumerType = $RemainingConsumer.__CLASS
				$CustomObject.KillTimeout  = $RemainingConsumer.KillTimeout 
				$CustomObject.MachineName = $RemainingConsumer.MachineName
				$CustomObject.MaximumQueueSize = $RemainingConsumer.MaximumQueueSize
				$CustomObject.ScriptingEngine = $RemainingConsumer.ScriptingEngine
				$CustomObject.ScriptFileName = $RemainingConsumer.ScriptFileName
				$CustomObject.ScriptText = $RemainingConsumer.ScriptText
			}
			
			"SMTPEventConsumer" {
				$CustomObject = "" | Select-Object -Property ConsumerName, ConsumerType, BccLine, CcLine, FromLine, Message, ReplyToLine, SMTPServer, Subject, ToLine, HeaderFields
				$CustomObject.ConsumerName = $RemainingConsumer.Name
				$CustomObject.ConsumerType = $RemainingConsumer.__CLASS
				$CustomObject.BccLine = $RemainingConsumer.BccLine
				$CustomObject.CcLine = $RemainingConsumer.CcLine
				$CustomObject.FromLine = $RemainingConsumer.FromLine
				$CustomObject.Message = $RemainingConsumer.Message
				$CustomObject.ReplyToLine = $RemainingConsumer.ReplyToLine
				$CustomObject.SMTPServer = $RemainingConsumer.SMTPServer
				$CustomObject.Subject = $RemainingConsumer.Subject
				$CustomObject.ToLine = $RemainingConsumer.ToLine
				$CustomObject.HeaderFields = $RemainingConsumer.HeaderFields
			}
		}
	
	$ResultArray += $CustomObject
	}
}

$ResultArray