##############################################################################
# ConfigESX.ps1
# Version 0.1
# Example script to demonstrate Applying profiles to servers in OneView 
# (C) Copyright 2013-2018 Hewlett Packard Enterprise Development LP 
##############################################################################

##############################################################################
#
# define a few parmeters to point to the csv files
# 
# ApplianceData.csv is the OneView appliance IP, username, password
# ProfileData.csv is information about the actual install
# vCenterDAta.csv is the ip, username and password for vcenter
# 
# Use of CSV files allow this to be done for more than one appliance and/or vCenter

param (
    [int]$ErrorProfile = 0,
    [string]$ApplianceData =".\data\appliances.csv",
    [string]$ProfileData =".\data\iLOs.csv"
)

##############################################################################
#
# Function DoOperatingSystem
#
# This routine is used to install esxi
# The process is similar to the other loops.  Use the ProfileData.csv file for informmation about the servers.
# Run through that list of servers 
#   Look up the Servername in OneView, grap the IP address for iLO
#   Add the extra kickstart commands specific to this server to the ks.cfg
#   Use the iLO powershell cmdlets to mount the remote media (remember this requires HTTP)
#   let the installation go

function ConfigProfile {
    #Identify iLO IP by string match so we can use it to mount the ISO to the iLO virtual Media
    if ( -not (Test-path -Path $ProfileData)) {
        write-host "No file specified or file $vCenterData does not exist.  Unable to install system"
        exit
    }
    # Read the CSV Users file
    $tempFile = [IO.Path]::GetTempFileName()
    Get-Content $ProfileData | Where-Object { ($_ -notlike ",,,,,,,,*") -and  ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempFile   # Skip blank line
    # Get-Content $ProfileData > $tempFile   # Skip blank line ($_ -notlike '"*') -and
    
    $svrs = import-csv $tempFile
    $OVsvrs = Get-OVServer 

    foreach ( $svr in $svrs ) {
        $ProfileName = $svr.Name+"Profile"
        $s = $OVsvrs | Where-Object { $_.Name -eq $svr.iloName}
        Write-Host "Creating Profile: ", $ProfileName
        Write-Host "Server: ",$s.Name
        Write-Host -ForegroundColor Magenta "$($svr.Name) is installed!"  
    }
}

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
# Get-Content $ProfileData > $tempFile   # Skip blank line ($_ -notlike '"*') -and

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

ConfigProfile