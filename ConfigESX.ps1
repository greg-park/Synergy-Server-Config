##############################################################################
# ConfigESX.ps1
# Version 0.1
# Example script to demonstrate deploying esx nodes in a Synergy frame 
#
# The script uses iLO PowerShell and VMware PowerCLI
# 
# Variable Discussion (need to go through this list, not all variables are used in this program)
#    [string]$blade     = Name as it appears in OneView Server Hardware
#    [string]$profname  = Name for the profile once created
#    [string]$OVName    = OneView IP address or FQDN
#    [string]$OVUser    = Clear text of OneView admin username
#    [string]$OVPass    = Clear text of OneView password ... in production this is a BAD practice
#    [string]$OVDomain  = Logon domain
#    [string]$TemplateName = Name of the server profile template used when creating server profile
#    [string]$Isopath   = HTTP string to web server with ISO for iLO remote media
#    [string]$ksTemplate = Name of KickStart config file, i.e. '\\10.10.197.71\media\media\esxautotpw\test\109\ksBase.cfg'
#    [string]$NewCfg    = Name of KickStart addition changes, i.e. '\\10.10.197.71\media\media\esxautotpw\test\109\ks.cfg'
#    [string]$DiskPath  = Define the target disk path.  Could just use firstdisk paramater but this allows flexibility.  Ex. 'vmhba0:C1:T0:L0'
# NOTE: for the above you might be able to determine this.  Need to do some research.
#    [string]$NewIP     = IP address to use once esxi is installed, ex: 10.10.100.1
#    [string]$NewHostName = Host name to use once esxi is installed, ex: 'TestHost'
#    [string]$MoreStuff  = Command list to add to ks files, example
#           " vim-cmd hostsvc/enable_ssh `n vim-cmd hostsvc/start_ssh `n vim-cmd hostsvc/enable_esx_shell `n vim-cmd hostsvc/start_esx_shell `n esxcli software vib install -d http://10.10.197.71/media/esxautotpw/vib/nimble-ncm `n esxcli software vib install -d http://10.10.197.71/media/esxautotpw/vib/sutesx67/ `n esxcli software vib install -d http://10.10.197.71/media/esxautotpw/vib/nimble-ncm `n sleep 60 `n reboot"
# NOTE: It might be easier to crete a temp text file with all the post esxi install commands to add to the kickstart file.  Need to do some testing.
#    [string]$CenterName = Vcenter IP address to use for adding newly created esxi host, ex: '10.10.105.250'
#    [string]$CenterUser = Another bad practice, vCenter administrator.  'administrator@vsphere.local'
#    [string]$Centerpass = Continueing the bad practices, admin password 'HP1nvent!'
#    [string]$ESXUser    = esxi user name, ex:'root'
#    [string]$ESXPWD     = Again, don't do this in production, password is: 'HP1nvent!'
#    [string]$Datacenter = The name of the DataCenter to create within vCenter, ex: "TestDC"
#    [string]$Cluster    = Just to be complete lets add a Cluster, ex: "TestCl"
#
#
# (C) Copyright 2013-2018 Hewlett Packard Enterprise Development LP 
##############################################################################

##############################################################################
#
# define a few parmeters to point to the csv files
# 
# ApplianceData.csv is the OneView appliance IP, username, password
# InstallDAta.csv is information about the actual install
# vCenterDAta.csv is the ip, username and password for vcenter
# 
# Use of CSV files allow this to be done for more than one appliance and/or vCenter

param (
    [int]$ErrorProfile = 0,
    [string]$ApplianceData =".\ApplianceData.csv",
    [string]$InstallData =".\InstallData.csv",
    [string]$vCenterData =".\vCenterData.csv"
 )

##############################################################################
#
# Function DoOperatingSystem
#
# This routine is used to install esxi
# The process is similar to the other loops.  Use the InstallData.csv file for informmation about the servers.
# Run through that list of servers 
#   Look up the Servername in OneView, grap the IP address for iLO
#   Add the extra kickstart commands specific to this server to the ks.cfg
#   Use the iLO powershell cmdlets to mount the remote media (remember this requires HTTP)
#   let the installation go

function DoOperatingSystem {
    #Identify iLO IP by string match so we can use it to mount the ISO to the iLO virtual Media
    if ( -not (Test-path -Path $InstallData)) {
        write-host "No file specified or file $vCenterData does not exist.  Unable to install system"
        exit
    }
    # Read the CSV Users file
    $tempFile = [IO.Path]::GetTempFileName()
    Get-Content $InstallData | Where-Object { ($_ -notlike ",,,,,,,,*") -and  ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempFile   # Skip blank line
    # Get-Content $InstallData > $tempFile   # Skip blank line ($_ -notlike '"*') -and
    
    $Servers = import-csv $tempFile

    # ToDo:
# Seperate out the iLO IPs to a seperate file
# Generate that file from a short OneView script "GetiLOIPs.ps1"
#   GetiLOIPs.ps1 will look like
#   $server = Get-HPOVServer -Name $svr.blade
#   $Index = $server.mpHostinfo.mpIpAddresses.Count-1
#   $iloIP = $server.mpHostInfo.mpIpAddresses[$Index].address
#   write $iloIP to File

    foreach ( $svr in $Servers ) {
        $server = Get-HPOVServer -Name $svr.blade
        $Index = $server.mpHostinfo.mpIpAddresses.Count-1
        $iloIP = $server.mpHostInfo.mpIpAddresses[$Index].address

        # Generate Kickstart
        $tmpcfg = ".\tmpks.txt"
        (Get-Content $svr.ksTemplate) | Foreach-Object {
             $_.replace('$DskPath', $svr.DiskPath).replace('$HOSTIP', $svr.NewIP).replace('$HOSTNM', $svr.NewHostName).replace('$More', $svr.MoreStuff)
        } | Set-Content $svr.NewCfg
        Get-Content $svr.NewCfg, "esxcfg.txt" | Set-Content $tmpcfg
        Copy-Item $tmpcfg -Destination $svr.NewCfg
        #Remove-Item $tmpcfg
 
        write-host -ForegroundColor Magenta "Mounting $($svr.Isopath) to $iloIP"
        $iLoconn = Connect-HPEiLO $iloIP -Username hpadmin -Password atlpresales -DisableCertificateAuthentication
        if ( $null -eq $iLoconn ) {
            Write-Host -ForeGroundColor Magenta $iloIP," connection could not be established ... exiting"
            exit
        }
        Mount-HPEiLOVirtualMedia  -connection $iLoconn -Device CD -ImageURL $svr.Isopath
        set-hpeiloonetimebootoption -connection $iLoconn -BootSourceOverrideEnable Once -BootSourceOverrideTarget CD
        write-host -ForegroundColor Magenta "Booting server to install OS"
        Get-HPOVserver -Name $svr.blade | Start-HPOVServer | Get-HPOVTask -State Running | Wait-HPOVTaskComplete
 
        For ($i=360; $i -gt 1; $i--) {  
            Write-Progress -Activity "sleeping 5 minutes while OS image is installed" -Status "$i"
            Start-Sleep -Seconds 1
        }

        write-host -ForegroundColor Magenta "Waiting for $($svr.profname) at $($svr.NewIP) to come online"
        while ( (Test-NetConnection -Computername $svr.NewIP -InformationLevel Quiet -WarningAction SilentlyContinue ) -ne "True" ) {
            Write-Host -foreground Green "Waiting for Server ",$svr.NewIP,"to boot ..."
            Start-Sleep -Seconds 20
        }
        Write-Host -ForegroundColor Magenta "$($svr.NewIP) is installed!"  
    }
}

##############################################################################
#
# Function CheckESX
#
# This routine is used to verify esxi installation

function Checkesx {

    if ( -not (Test-path -Path $vCenterData)) {
        write-host "No file specified or file $vCenterData does not exist.  Unable to install system"
        exit
    }
    # Read the CSV Users file
    $tempFile = [IO.Path]::GetTempFileName()
    Get-Content $vCenterData | Where-Object { ($_ -notlike ",,,,,,,,*") -and  ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempFile   # Skip blank line
    # Get-Content $InstallData > $tempFile   # Skip blank line ($_ -notlike '"*') -and
    
    $esxHosts = import-csv $tempFile
    
    foreach ($esxHost in $esxHosts) {
        [string]$CenterName     = $esxHost.vCenterName
        [string]$CenterUser     = $esxHost.vCenterUser
        [string]$Centerpass     = $esxHost.vCenterPWD
        [string]$ESXUser        = $esxHost.ESXUser
        [string]$ESXPWD         = $esxHost.ESXpwd
        [string]$Datacenter     = $esxHost.DataCenter
        [string]$Cluster        = $esxHost.Cluster
        [string]$NewIP          = $esxHost.NewIP
        [string]$esxcli

        # import-module VMware.VimAutomation.Core
        # import-module VMware.VimAutomation.Storage
        write-Host -ForegroundColor Green "connecting $NewIP to check sut status"
        $tmpHost = Connect-VIServer $NewIP -User $ESXUser -Password $ESXpwd
        $esxcli = get-esxcli
        $sutins = $esxcli.software.vib.list() | Select-Object AcceptanceLevel,ID,InstallDate,Name,ReleaseDate,Status,Vendor,Version | Where-Object {$_.name -match "sut"}

        if ($sutins -eq $null) {
            Write-Host -Foregroundcolor Red "For esxi host $NewIP it does not look like isut installed"
        } else {
            Write-Host -Foregroundcolor Green "SUT installed on $NewIP is: "$sutins.ID
        }

        if ( $global:DefaultVIServers.Count -gt 0 -and $global:DefaultVIServers[0].Name -eq $CenterName ) {
            write-Host -ForegroundColor Green "Already connected to $CenterName"
            Write-Host -ForegroundColor Green "Server: ", $global:DefaultVIServers[0].Name
        } else {
            write-Host -ForegroundColor Green "connecting $CenterName as $CenterUser and $Centerpass"
            $tmpHost = Connect-VIServer $CenterName -User $CenterUser -Password $Centerpass
        }

        # Create DC & Cluster if they dont exist
        If (-Not ($NewDatacenter = Get-Datacenter $DataCenter -ErrorAction SilentlyContinue)){ 
            Write-Host -ForegroundColor Green "Adding $DataCenter"
            $NewDatacenter = New-Datacenter -Name $DataCenter -Location (Get-Folder -NoRecursion) 
        } else {
            Write-Host -foreground Green "$DataCenter already exists"
        }

        if (-Not ($NewCluster = Get-Cluster $Cluster -ErrorAction SilentlyContinue)) { 
           Write-Host -foreground Green "Adding $Cluster Cluster"
           $NewCluster = New-Cluster -Name $Cluster -Location $NewDatacenter -DrsEnabled:$true
        } else {
            Write-Host -foreground Green "$Cluster already exists"
        }

        # Add host to Cluster
        if ( -Not ( $NewHost = Get-VMHost $NewIP )) {
            write-host -foreground Green "Adding $NewIP to $Cluster"
            $NewHost = Add-VMHost -Name $NewIP -Location $NewCluster -User $ESXUser -Password $ESXPWD -Force
        } else {
            Write-Host -foreground Green "$NewIP already in $Cluster"
        }
        Disconnect-VIServer * -Confirm:$false | Out-Null
    }
} #End of AutoAddServer

##############################################################################
## Main Program
#
# Note: this program could be called from an external script

if ( -not (Test-path -Path $ApplianceData)) {
    write-host "No file specified or file $ApplianceData does not exist.  Unable to install system"
    exit
}

# 
# Read the CSV file to get info for multiple appliances.
# This particular program only uses 1 instance of the Appliance 

$tempFile = [IO.Path]::GetTempFileName()
Get-Content $ApplianceData | Where-Object { ($_ -notlike ",,,,,,,,*") -and  ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempFile   # Skip blank line
# Get-Content $InstallData > $tempFile   # Skip blank line ($_ -notlike '"*') -and

$Appliances = import-csv $tempFile
[string]$OVName       = $Appliances.OVName
[string]$OVUser       = $Appliances.OVUser
[string]$OVPass       = $Appliances.OVPass
[string]$OVDomain     = $Appliances.OVDomain

write-host -ForegroundColor Magenta "Connect to OneView appliance:$OVName"
if ( !$ConnectedSessions ) {
    $secpasswd = ConvertTo-SecureString $OVPass -AsPlainText -Force
    $OVCreds = New-Object System.Management.Automation.PSCredential ("$OVUser", $secpasswd)
    $MyConnection = Connect-HPOVMgmt -hostname $OVName -Credential $OVCreds -AuthLoginDomain $OVDomain
} else {
    Write-Host -ForegroundColor Magenta "Already connected to $OVName"
}

DoOperatingSystem
# Checkesx
# Disconnect-HPOVMgmt 
