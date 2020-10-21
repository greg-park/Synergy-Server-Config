# RemoveServers_OV.ps1
# - Example script for Removing multiple servers from an appliance.
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

if (-not (get-module HPEOneView.540)){
    Import-Module HPEOneView.540
}

if (-not (get-module HPEiLOCmdlets)){
    Import-Module HPEiLOCmdlets
}

# First connect to the HP OneView appliance
if (-not($ConnectedSessions)) {
	$ApplianceConnection = Connect-OVMgmt -hostname $Hostname
}
$OVServerList = Get-OVServer

#Read CSV of server iLO Addresses, with account credentials
# CSV File should contain the following headers:
#
# hostname,account,password
[Array]$ServersList = Import-Csv $CSV

foreach ( $OVserver in $ServersList ) {
	foreach ( $server in $OVServerList ) {
		if ( $OVServer.hostname -eq $server.mpHostInfo.mpIpAddresses[0].address ) {
			$Resp = Remove-OVServer -Name $server.Name -confirm:$false | Wait-OVTaskComplete
		}
	}
}

Write-Host 'all done.'