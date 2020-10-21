# Latest Change 10/17/2020
#  
# Add servers to HPE OneView
#  Create Server profiles

[CmdletBinding()]
param
(
    [Parameter(Position = 0, Mandatory, HelpMessage = "Please provide the path and filename of the CSV file containing the server iLO's and crednetials.")]
    [ValidateNotNullorEmpty()]
    [string]$CSV = ".\data\iLOs.csv",

    [Parameter(Position = 1, Mandatory, HelpMessage = "Provide the appliance FQDN or Hostname to connect to.")]
    [String]$Hostname = "hpov.domain.local"

)

# Load powershell modules used in this script
if (-not (get-module HPEOneView.540)) {
    Import-Module HPEOneView.540
}

if (-not (get-module HPEiLOCmdlets)) {
    Import-Module HPEiLOCmdlets
}

# Build a array of hash tables
# $svrInfo = @{
#    "iloIP" = ""
#    "iloUser" = ""
#    "iloPass" = ""
#    "iloName" = ""
#    "spt" = ""
#    "profile" = ""
# }

function BuildServerInfo ([hashtable]$arg) {

    # Data for the program
    if (-not(Test-Path $CSV -PathType Leaf)) {
        Write-Error ("The CSV parameter value {0} does not resolve to a file. Please check the value and try again." -f $CSV) -ErrorAction Stop
    }

    # Read in the .csv file and create a "data structure"
    # with all the server info.  Data structure in this case
    # is just an array of hashtables.
    [Array]$ServersList = Import-Csv $CSV
    $ServersList | ForEach-Object {
        $svrInfo = @( 
            @{
                'iloIP'         = $_.iloip
                'iloUser'       = $_.account
                'iloPass'       = $_.password
                'iloName'       = $_.iloName
                'spt'           = $_.spt
                'profile'       = $_.Name + "_Profile"
                'iloLicense'    = $_.LicenseTier
                'Rack'          = $_.Rack
                'uLocation'     = $_.U
                'DataCenter'    = $_.DC
                'iloTest'       = "NO"
                'LicenseType'   = "OneViewNoiLO"
            }
        )
        $workArray = $workArray + @($svrInfo)
    }
    $workArray
}
# build server info

function TestiLO() {
    $svrArray | ForEach-Object {
        $secpasswd = ConvertTo-SecureString $_.iloPass -AsPlainText -Force
        $iLOCreds = New-Object System.Management.Automation.PSCredential($_.iloUser, $secpasswd)
        $iloconnection = connect-hpeilo -Address $_.iloip -Credential $iLOCreds -DisableCertificateAuthentication -ErrorAction SilentlyContinue
        if ($iloconnection) {
            $ilolicense = Get-HPEiLOLicense -Connection $iloconnection
           if ($ilolicense.LicenseTier -eq 'ADV') {
               $_.LicenseType = "OneViewNoiLO"
           }
           else {
               $_.LicenseType = "OneView"
           }    
        }
        else {
            Write-Host $_.iloip, "Failed ilo connection ... skipping"
        }

    }
}
function AddServerstoOV () {
    # First connect to the HP OneView appliance
    if (-not($ConnectedSessions)) {
        $ApplianceConnection = Connect-OVMgmt -hostname $Hostname
    }

    #Used to store the async task object for varification later
    $AsyncTaskCollection = New-Object System.Collections.ArrayList
    Write-Progress -ID 1 -Activity ("Adding Servers to {0}" -f $ApplianceConnection.Name) -Status "Starting" -PercentComplete 0
    $i = 1

    $svrArray | ForEach-Object {

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
        }new-ovserver

        Write-Progress -ID 1 -Activity ("Adding Servers to {0}" -f $ApplianceConnection.Name) -Status ("Processing {0}" -f $_.iloip) -PercentComplete ($i / $ServersList.Count * 100)
        $LicenseType = "OneView"
        # ToDO 
        # Before adding we might want to double check server is not already in OneView
        if ($_.iloName) {
            $Server = Get-OVServer -Name $_.iloName -ErrorAction SilentlyContinue
        } else {
            $Server = Get-OVServer -Name $_.iloip -ErrorAction SilentlyContinue
        }

        if (!$Server) {
            $Resp = Add-OVServer -hostname $_.iloip -Credential $iLOCreds -LicensingIntent $LicenseType -Async
            [void]$AsyncTaskCollection.Add($Resp)
            $counter++
        }
        else {
            Write-Host -ForegroundColor Red $_.iloip, " already in OneView inventory"
        } 
    }

    Write-Host 'We are all done.'
    Write-Host ("{0} async tasks were created." -f $AsyncTaskCollection.Count)
    Write-Host 'Displaying final status of tasks.'

    $AsyncTaskCollection | ForEach-Object { Send-OVRequest $_.uri } | Sort-Object status -Descending | Format-Table
}

Function ApplyProfiles() {
    # TODO
    # Noticed a bug.  I need to add a check for HardwareType.  This will apply a SPT
    # to a server that has a different HW type.  For example Gen8 1 and Gen8 2
    # there is an option to get the SPT (Get-OVServerProfileTemplate).
    # Need to investigate how to get the HWType out of that cmdlet and test before
    # applying the defined SPT
    # TODO

    $svrArray | ForEach-Object {
        Write-Host "Apply SPT:", $_.spt
        Write-Host $_.profile
        $Server = Get-OVServer -Name $_.iloip -ErrorAction SilentlyContinue
        New-OVServerProfile -server $Server -ServerProfileTemplate $_.spt -name $_.profile
    }
}

function BuildFacilities () {
    Write-Host 'Building Facility'
    $svrArray | ForEach-Object {
        $Rack = Get-OVRack -Name $_.Rack
        # Here is the Get-OVServer issue again.  Need iLO names ... try a test of variables for now
        if ($_.iloName) {
            $Server = Get-OVServer -Name $_.iloName
        } else {
            $Server = Get-OVServer -Name $_.iloip
        }
        Add-OVResourceToRack -InputObject $Server -Rack $Rack -ULocation $_.U
    }
}
# main
$svrArray = @()
$svrArray = BuildServerInfo
# $svrArray
# Only need to call this function if you do not trust the iLO ip address list
# TestiLO
AddServerstoOV
ApplyProfiles
BuildFacilities