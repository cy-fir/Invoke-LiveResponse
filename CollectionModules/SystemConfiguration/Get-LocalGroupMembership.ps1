 <#
.SYNOPSIS
	Queries for local groups, then returns membership for each group

.NOTES
    Author: David Howell
    Last Modified: 02/01/2016
    
OUTPUT csv
#>
$Groups = & net localgroup | Select-String -Pattern "^\*.+"
ForEach ($Group in $Groups) {
	if ($Group -match "\*(.+)") {
		& net localgroup $matches[1] | Select-Object -Skip 6 | Where-Object -FilterScript { $_ -and $_ -notmatch "The command completed successfully" } | ForEach-Object {
			[PSCustomObject]@{
				Username = $_
				Group = $matches[1]
			}
		}
	}
}