##############################################################################
# InstallOS.ps1
# Version 0.1
# The script uses iLO PowerShell and VMware PowerCLI
# (C) Copyright 2013-2018 Hewlett Packard Enterprise Development LP 
# ToDo: Change to RedFish calls
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
    [int]$errorProfile = 0,
    [string]$dataDir = '.\Data\',
    [string]$resDir  = '.\Results\',
    [string]$ksDir   = '.\kickstart\',
    [string]$esxdata = $ksDir+'esxcfg.txt',
    [string]$iLOIPs  = $dataDir+'iLOs.csv'
)

##############################################################################
#
# ! Function DoOperatingSystem
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
    if ( -not (Test-path -Path $iLOIPs)) {
        write-host "No file specified or file $iLOIPs does not exist.  Unable to build environment"
        exit
    }

    # Read the CSV Users file
    $tempFile = [IO.Path]::GetTempFileName()
    Get-Content $iLOIPs | Where-Object { ($_ -notlike ",,,,,,,,*") -and  ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempFile   # Skip blank line
    $Servers = import-csv $tempFile

    foreach ( $svr in $Servers ) {
        # $server = Get-HPOVServer -Name $svr.blade

        # Generate Kickstart
        # Check if kickstart files exist
        $ksTemplate = $ksDir+$svr.ksTemplate
        if ( -not (Test-path -Path $ksTemplate)) {
            write-host -ForegroundColor Red $ksTemplate ":does not exist.  Unable to build environment"
            exit
        } 

        # Create a tmp file to use as we build the customizations for this particular KickStart file
        $tmpcfg = $resDir+'\tmpks.'+$svr.NewIP+".txt"

        # Make sure the file does not exist.  No need to keep old files
        if ( Test-Path -Path $tmpcfg ) {
            Write-Host -ForegroundColor Magenta $tmpcfg,":File exists, removing"
            Remove-Item -Path $tmpcfg
        }

        # Build customizations.  
        # HOSTIP will be the new host IP address, HOSTNM= new host name
        (Get-Content $ksTemplate) | Foreach-Object {
              $_.replace('$HOSTIP', $svr.NewIP).replace('$HOSTNM', $svr.NewHostName)
        } | Set-Content $svr.NewCfg
        Get-Content $svr.NewCfg, $esxdata | Set-Content $tmpcfg

        # Build the Microsoft Server name from the ISO path variable
        $Isopath = $svr.isoDir+$svr.iso
        
        $str1 = $($svr.isoDir).Replace("http:","")
        $str2 = $str1.Replace("/","\")
        $DestinationCFG = $str2+$svr.NewCfg
        Write-Host "Copy $tmpcfg to $DestinationCFG"
        Copy-Item $svr.Newcfg $DestinationCFG
        
        $iLoconn = Connect-HPEiLO $svr.iloIP -Username $svr.User -Password $svr.Pass -DisableCertificateAuthentication -ErrorAction SilentlyContinue
        if ( $null -eq $iLoconn ) {
            Write-Host -ForeGroundColor Magenta $iloIP," connection could not be established ... exiting"
            exit
        }

        $power = Get-HPEiLOServerPower -Connection $iLoconn -ErrorAction SilentlyContinue
        do {
            write-host -ForegroundColor Magenta "Server $($svr.iloIP) powering off ... waiting 10s"
            Set-HPEiLOServerPower -Connection $iLoconn -Power PressAndHold -ErrorAction SilentlyContinue
            Start-Sleep -seconds 10
            $power = Get-HPEiLOServerPower -Connection $iLoconn -ErrorAction SilentlyContinue
            Write-Host -ForegroundColor Magenta "Server Power State:", $power.Power
        } until ($power.Power -eq "off")
       
        write-host -ForegroundColor Magenta "Mounting $($Isopath) to $($svr.iloIP)"
        Mount-HPEiLOVirtualMedia  -connection $iLoconn -Device CD -ImageURL $Isopath -ErrorAction SilentlyContinue
        set-hpeiloonetimebootoption -connection $iLoconn -BootSourceOverrideTarget CD        
        write-host -ForegroundColor Magenta "Booting server to install OS"
        Set-HPEiLOServerPower -Connection $iLoconn -Power On -ErrorAction SilentlyContinue

        For ($i=720; $i -gt 1; $i--) {  
            Write-Progress -Activity "sleeping 10 minutes while OS image is installed" -Status "$i"
            Start-Sleep -Seconds 1
        }

        write-host -ForegroundColor Magenta "Waiting for $($svr.NewIP) to come online"
        while ( (Test-NetConnection -Computername $svr.NewIP -InformationLevel Quiet -WarningAction SilentlyContinue ) -ne "True" ) {
            Write-Host -foreground Green "Waiting for Server ",$svr.NewIP,"to boot ..."
            Start-Sleep -Seconds 20
        }
        
        Write-Host -ForegroundColor Magenta "$($svr.NewIP) is installed! Server will reboot to finish run once steps"  
    }
}

function CheckInstall {
   #Identify iLO IP by string match so we can use it to mount the ISO to the iLO virtual Media
   if ( -not (Test-path -Path $iLOIPs)) {
        write-host "No file specified or file $vCenterD$iLOIPs does not exist.  Unable to build environment"
        exit
    }

    # Read the CSV Users file
    $tempFile = [IO.Path]::GetTempFileName()
    Get-Content $iLOIPs | Where-Object { ($_ -notlike ",,,,,,,,*") -and  ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempFile   # Skip blank line
    $Servers = import-csv $tempFile

    foreach ( $svr in $Servers ) {
        $secpasswd = ConvertTo-SecureString $svr.ESXpwd -AsPlainText -Force
        $creds = New-Object System.Management.Automation.PSCredential ($svr.ESXUser, $secpasswd)
        $con = Connect-VIServer -Server $svr.NewIP -Credential $creds

        Get-VMHost -Name $con.Name | Select @{N='Install Date';E={$script:esxcli = Get-EsxCli -VMHost $_ -V2
            $epoch = $script:esxcli.system.uuid.get.Invoke().Split('-')[0] 
		    [timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds([int]"0x$($epoch)"))}}
    }
    Write-Host "All Servers Checked"
}

##############################################################################
## Main Program
#
# Note: this program could be called from an external script

DoOperatingSystem
CheckInstall
Write-Host "All done"