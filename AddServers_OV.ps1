# AddServers_OV.ps1
# - Example script for importing multiple servers to be managed.
# - Adapted from example scrits
#   VERSION 01
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
	[string]$CSV = ".\data\iLOs.csv",

	[Parameter(Position = 1, Mandatory, HelpMessage = "Provide the appliance FQDN or Hostname to connect to.")]
	[String]$Hostname = "hpov.domain.local"

)

if (-not(Test-Path $CSV -PathType Leaf)) {
	Write-Error ("The CSV parameter value {0} does not resolve to a file. Please check the value and try again." -f $CSV) -ErrorAction Stop
}

if (-not (get-module HPEOneView.540)) {
	Import-Module HPEOneView.540
}

if (-not (get-module HPEiLOCmdlets)) {
	Import-Module HPEiLOCmdlets
}

# First connect to the HP OneView appliance
if (-not($ConnectedSessions)) {
	$ApplianceConnection = Connect-OVMgmt -hostname $Hostname
}

#Read CSV of server iLO Addresses, with account credentials
# CSV File should contain the following headers:
#
# hostname,account,password
[Array]$ServersList = Import-Csv $CSV
$counter = 1

#Used to store the async task object for varification later
$AsyncTaskCollection = New-Object System.Collections.ArrayList
Write-Progress -ID 1 -Activity ("Adding Servers to {0}" -f $ApplianceConnection.Name) -Status "Starting" -PercentComplete 0
$i = 1

$ServersList | ForEach-Object {
	#Pauase the processing, as only 64 concurrent async tasks are supported by the appliance
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

	Write-Progress -ID 1 -Activity ("Adding Servers to {0}" -f $ApplianceConnection.Name) -Status ("Processing {0}" -f $_.ip) -PercentComplete ($i / $ServersList.Count * 100)
	$secpasswd = ConvertTo-SecureString $_.password -AsPlainText -Force
	$iLOCreds = New-Object System.Management.Automation.PSCredential($_.account, $secpasswd)
	$iloconnection = connect-hpeilo -Address $_.iloip -Credential $iLOCreds -DisableCertificateAuthentication -ErrorAction SilentlyContinue

	# TODO: Add test setting for DCS.  There is no iLO to check so need a way to
	# TODO: work with the DCS and add these servers
	# TODO: Create a $DCS variable.  If $DCS then check iLO but ignore results
	if ($iloconnection) {
		$ilolicense = Get-HPEiLOLicense -Connection $iloconnection
		if ($ilolicense.LicenseTier -eq 'ADV') {
			$LicenseType = "OneViewNoiLO"
		}
		else {
			$LicenseType = "OneView"
		}
		# ToDO 
		# Before adding we might want to double check server is not already in OneView
		# $NetSet = Get-HPEiLOIPv4NetworkSetting -Connection $ilo
		# $Server = Get-OVServer -Name $netsetting.DNSName
		# if (!$Server) {
		$Resp = Add-OVServer -hostname $_.iloip -Credential $iLOCreds -LicensingIntent $LicenseType -Async
		[void]$AsyncTaskCollection.Add($Resp)
		$counter++
		# } 
	}
 else {
		Write-Host $_.ip, "Failed ilo connection ... skipping"
	}
}

Write-Host 'We are all done.'
Write-Host ("{0} async tasks were created." -f $AsyncTaskCollection.Count)
Write-Host 'Displaying final status of tasks.'

$AsyncTaskCollection | ForEach-Object { Send-OVRequest $_.uri } | Sort-Object status -Descending | Format-Table