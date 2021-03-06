<#
.SYNOPSIS
	Uses Get-DNSClientCache or ipconfig /displaydns to return cached DNS resolutions
	
.NOTES
	Original From Dave Hull's Kansa repository on GitHub: 11/16/2014
	
OUTPUT csv
#>

if (Get-Command Get-DnsClientCache -ErrorAction SilentlyContinue) {
    Get-DnsClientCache | Select-Object TimeToLIve, Caption, Description, ElementName, InstanceId, Data, DataLength, Entry, Name, Section, Status, Type
} else {
	$o = "" | Select-Object TimeToLive, Data, DataLength, Entry, Name, Section, Type, RecordType
	
	# Run IPConfig.exe /DisplayDNS and set output to a variable for us to work with
	$DisplayDNS = & ipconfig.exe /displaydns | Select-Object -Skip 3 | ForEach-Object { $_.Trim() }
	
	# Parse the data from ipconfig and set to Object Properties
	$DisplayDNS | ForEach-Object {
	    switch -Regex ($_) {
	        "-----------" {
	        }
	        "Record Name[\s|\.]+:\s(?<RecordName>.*$)" {
	            $o.Name = ($matches['RecordName'])
	        } 
	        "Record Type[\s|\.]+:\s(?<RecordType>.*$)" {
	            $o.RecordType = ($matches['RecordType'])
	        }
	        "Time To Live[\s|\.]+:\s(?<TTL>.*$)" {
	            $o.TimeToLive = ($matches['TTL'])
	        }
	        "Data Length[\s|\.]+:\s(?<DataLength>.*$)" {
	            $o.DataLength = ($matches['DataLength'])
	        }
	        "Section[\s|\.]+:\s(?<Section>.*$)" {
	            $o.Section = ($matches['Section'])
	        }
	        "(?<Type>[A-Za-z()\s]+)\s.*Record[\s|\.]+:\s(?<Data>.*$)" {
	            $o.Data = ($matches['Data'])
				$o.Type = ($matches['Type'])
				$o
	        }
	        "^$" {
	            $o = "" | Select-Object TimeToLive, Data, DataLength, Entry, Name, Section, Type, RecordType
	        }
	        default {
				$o.Entry= $_
	        }
	    }
	}
}