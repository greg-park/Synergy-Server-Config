Param ( 
        [string]$appliances = "\appliances.csv",
        [string]$ilos       = "\ilos.csv",
        [string]$esxdata    = "\connection.csv",
        [string]$osdata     = "\storage.csv"
)

[string]$ScriptPath = ".\"
[string]$datadir     = ".\data"

# Keep a log of what we do 
$ScriptPath = Split-Path $MyInvocation.InvocationName
[string]$logFile = $datadir+"\ApplianceBuild_LOG.txt"
$Start = Get-Date
add-content -Path $logFile -Value "Building appliance: $Start" -Force

$OVInfo = $datadir+$appliances

if ( -not (Test-path $OVInfo ) ) {
    write-host $OVInfo, ": OneView information file not found.  Cannot create appliance"
    return
} else {
    $OVppliances = Import-CSV $OVInfo
}

foreach ( $Appliance in $OVppliances ) {

    if (-not($ConnectedSessions)) {
        $ApplianceConnection = Connect-OVMgmt -hostname $Hostname
    } else {
        Write-Host -ForegroundColor Magenta "Already connected to appliance"
    }

    # Step 1: add all servers to OneView using iLO IP address
    # Call external PS script ":"AddServers_OV.ps1"
    add-content -Path $logFile -Value "Connected to $item.IP" -Force

    $Program = $ScriptPath+"\BuildServerInfo.ps1"

    # Check for the network script file.  If this file does not exists then exit
    if ( -not (Test-path $Program ) ) {
        write-host $Program, ": Powershell Script not found.  Check execution directory"
        Disconnect-HPOVMgmt -Hostname $Appliance.IP
        return
    }
	$TStamp = Get-Date
	add-content -Path $logFile -Value "$TStamp $Program $Options" -Force
    write-host $Program
    Invoke-Expression "$Program"

# Now add the servers to OneView
#    $Program = $ScriptPath+"\AddServers_OV.ps1"
#
#    # Check for the network script file.  If this file does not exists then exit
#    if ( -not (Test-path $Program ) ) {
#        write-host $Program, ": Powershell Script not found.  Check execution directory"
#        Disconnect-HPOVMgmt -Hostname $Appliance.IP
#        return
#    }
#    $Options = $datadir+$ilos+" "+$Appliance.hostname
#	$TStamp = Get-Date
#	add-content -Path $logFile -Value "$TStamp $Program $Options" -Force
#    write-host $Program $Options
#    Invoke-Expression "$Program $Options"

    # TODO Step 2. Configure Profiles and any OneView settings
    # Call external PS Script: "ConfigProfile.ps1"

    # TODO Step 3. Configure operating system
    # Call external PS Script: "ConfigOS.ps1"

    # TODO Step 4. Check that all steps were successful
    # Call external PS Script: "CheckAll.ps1"
    
    # If Needed: Configure operating system options, settings, etc.
    # If Needed: Remove servers from OneView

}