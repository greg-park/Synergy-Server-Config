# RefreshServers.ps1
# - Script use to force re-apply server profile
#   VERSION 0.1
#
##############################################################################
<#
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
#>
##############################################################################

[CmdletBinding()]
param
(
	[Parameter(Position = 0, Mandatory, HelpMessage = "Please provide the path and filename of the CSV file containing the server iLO's and crednetials.")]
	[ValidateNotNullorEmpty()]
	[string]$CSV = ".\data\iLOs.csv"
)

if (-not(Test-Path $CSV -PathType Leaf)) {
	Write-Error ("The CSV parameter value {0} does not resolve to a file. Please check the value and try again." -f $CSV) -ErrorAction Stop
}

if (-not (get-module HPEOneView.800)) {
	Import-Module HPEOneView.800
}

#if (-not (get-module HPEiLOCmdlets)) {
#	Import-Module HPEiLOCmdlets
#}

# First connect to the HP OneView appliance
if (-not($ConnectedSessions)) {
	Connect-OVMgmt
} else {
	write-host $ConnectedSessions
}

#Read CSV of server iLO Addresses, with account credentials
# CSV File should contain the following headers:
#
# hostname,account,password
[Array]$ServersList = Import-Csv $CSV
$counter = 1

#Used to store the async task object for varification later
$AsyncTaskCollection = New-Object System.Collections.ArrayList
# Write-Progress -ID 1 -Activity ("Re-apply Server profiles to {0}" -f $ApplianceConnection.Name) -Status "Starting" -PercentComplete 0
$i = 1
$OVServers = Get-OVServer
$svrs = @()

foreach ($svr in $OVServers) {
	if (![string]::IsNullOrEmpty($svr.serverName)) {
		$thissvr = Get-OVServer -Name $svr.Name
		if ($thissvr.serverProfileUri) {
#			write-host $thissvr.Name, $thissvr.serverName, $thissvr.mpHostInfo.mpIpAddresses[1].address
			foreach ($sList in $ServersList ) {
				if ( $sList.iloIP -eq $thissvr.mpHostInfo.mpIpAddresses[1].address ) {
#					Write-Host "Found", $thissvr.Name, $thissvr.serverName, $thissvr.mpHostInfo.mpIpAddresses[1].address
					if ($thissvr.powerState -eq "Off" ) {
#						Write-Host "... and server is off, update profile"
						$p = Send-OVRequest -uri $thissvr.serverProfileUri
						$prof = Get-OVServerProfile -name $p.Name
						$svrs += $prof.Name
					}
				}
			}
		}
	}
}

$AsyncTaskCollection = New-Object System.Collections.ArrayList
# Write-Progress -ID 1 -Activity ("Servers to {0}" -f $ConnectedSessions.Name) -Status ("Processing {0}" -f $_.ip) -PercentComplete ($i / $ServersList.Count * 100)
Write-Host "Reapply Server Profiles for:"
write-host $svrs
# add a "Confirm at this step"
$svrs | ForEach-Object {
	# Pauase the processing, as only 64 concurrent async tasks are supported by the appliance
	if ($counter -eq 64) {
		Write-Host 'Sleeping for 120 seconds.'
		1..120 | ForEach-Object {
			Write-Progress -id 2 -parentid 1 -Activity 'Sleeping for 2 minutes' -Status ("{0:mm\:ss}" -f (New-TimeSpan -Seconds $_ ))-PercentComplete (($_ / 120) * 100)
			Start-Sleep -Seconds 1
		}

		Write-Progress -Activity 'Sleeping for 2 minutes' -Completed
		#Reset counter here
		$counter = 1
	}
	$Profile = Get-OVServerProfile -Name $_
	$Resp = Update-OVServerProfile -InputObject $Profile -Reapply -Confirm:$false -Async
	[void]$AsyncTaskCollection.Add($Resp)
	$counter++
	# Write-Host $_.iloip
}

Write-Host 'Reapply Profiles in process.'
Write-Host ("{0} async tasks were created." -f $AsyncTaskCollection.Count)
Write-Host 'Displaying final status of tasks.'

$AsyncTaskCollection | ForEach-Object { Send-OVRequest $_.uri } | Sort-Object status -Descending | Format-Table
Start-Sleep -Seconds 30
Get-OVTask -State Running | Wait-OVTaskComplete
