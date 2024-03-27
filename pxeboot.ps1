Function log($msg){

    $logFilePath = "$PSScriptRoot\ps_log.txt"

    $msg | Out-File -FilePath $logFilePath -Append

}

Write-Host "Set PXE-BOOT PS script started"
log("Set PXE-BOOT PS script started")

#  Get root directory
Write-Host "Set PXE-BOOT PS running in $PSScriptRoot"
log("Set PXE-BOOT PS running in $PSScriptRoot")


Function CheckRunAsAdministrator()
{
  #Get current user context
  $CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
  
  #Check user is running the script is member of Administrator Group
  if($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))
  {
       Write-host "Script is running with Administrator privileges!"
       log("Script is running with Administrator privileges!")
  }
  else
    {
       #Create a new Elevated process to Start PowerShell
       $ElevatedProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";
 
       # Specify the current script path and name as a parameter
       $ElevatedProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'"
 
       #Set the Process to elevated
       $ElevatedProcess.Verb = "runas"
 
       #Start the new elevated process
       [System.Diagnostics.Process]::Start($ElevatedProcess)
 
       #Exit from the current, unelevated, process
       Exit
 
    }
}
 
#Check Script is running with Elevated Privileges
CheckRunAsAdministrator


# Set WOL for PC
# https://itinsights.org/Enable-wake-on-lan-WOL-with-PowerShell/

function Set-WakeEnabled
{
<#
.SYNOPSIS

Set WoL on nic

Author: Jan-Henrik Damaschke (@jandamaschke)
License: BSD 3-Clause
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION

Set Wake on Lan (WOL) settings for specific network interface card

.PARAMETER InterfaceName

Specifies the name of the interface where WoL setting should be changed

.PARAMETER WakeEnabled

Specifies if WoL should be enabled or disabled

.EXAMPLE

PS C:\> Set-WakeEnabled -InterfaceName Ethernet -WakeEnabled $true

.LINK

http://itinsights.org/
#>

[CmdletBinding()] Param(
        [Parameter(Mandatory = $True, ParameterSetName="InterfaceName")]
        [String]
        $InterfaceName,

        [Parameter(Mandatory = $True)]
        [String]
        $WakeEnabled,

        [Parameter(Mandatory = $True, ParameterSetName="ConnectionID")]
        [String]
        $NetConnectionID
)

    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
        Break
    }

    $nicsWakeEnabled = Get-CimInstance -ClassName MSPower_DeviceWakeEnable -Namespace root/wmi
    $nics = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object NetEnabled -eq $true

    if ($InterfaceName){
        $nic = $nics | Where-Object Name -eq $InterfaceName
    }
    else {
        $nic = $nics | Where-Object NetConnectionID -eq $NetConnectionID
    }

    $nicWakeEnabled = $nicsWakeEnabled | Where-Object InstanceName -like "*$($nic.PNPDeviceID)*"
    
    $enabled = $nicWakeEnabled.Enable

    if (!($enabled -and $WakeEnabled)){
        Set-CimInstance $nicWakeEnabled -Property @{Enable=$enabled}
    }
}


Set-WakeEnabled -InterfaceName Ethernet -WakeEnabled $true


# Read the GUIDs from the text file and populate the $allowedGUID array
Write-Host "Checking if file exists in: $PSScriptRoot\guid.txt"
log("Checking if file exists in: $PSScriptRoot\guid.txt")

$guidFilePath = "$PSScriptRoot\guid.txt"

# check if allowed guid text file exists
if (-not (Test-Path $guidFilePath)){
    Write-Host "Guid.txt does not exist: $guidFilePath"
    log("Guid.txt does not exist: $guidFilePath")
    # exit 775
}

$allowedGUID = Get-Content -Path $guidFilePath | ForEach-Object { $_.Trim() }

#check if GUID is allowed
$UUID = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$allow = 0

if(-not [string]::IsNullOrEmpty($UUID)){
    Write-Host "Host GUID/UUID:$UUID"
    log("Host GUID/UUID:$UUID")
    foreach ($guid in $allowedGUID) {
        if($guid -eq $UUID){
            $allow = 1
            break
        }   
    }
}
else{
    Write-Host "No GUID found in system"
    log("No GUID found in system")
    Exit 776  
}

if(!$allow){
    Write-Host "GUID: $guid not allowed to set PXE-BOOT"
    log("GUID: $guid not allowed to set PXE-BOOT")
    Exit 777
}

Write-Host "Set PXE BOOT: $guid"
log("Set PXE BOOT: $guid")


#Read more: https://www.sharepointdiary.com/2015/01/run-powershell-script-as-administrator-automatically.html#ixzz8Rc9ivRpx


# This script will force a PXE boot on next boot if the computer is configured for UEFI boot (instead of Legacy boot).
# Error Code 999 = Legacy Boot
# Error Code 888 = PXE Boot option likely missing from script


# Check for folder existence and create if missing.
$FolderName = "C:\temp"
if (Test-Path $FolderName) { 
    Write-Host "$FolderName exists"
    log("$FolderName exists")
}
else
{
    New-Item $FolderName -ItemType Directory
    Write-Host "$FolderName created successfully"
    log("$FolderName created successfully")
}

# Create list of boot options.
bcdedit /enum firmware > $FolderName\firmware.txt

# Check for Legacy Boot and exit if found.
$fwbootmgr = Select-String -Path "$FolderName\firmware.txt" -Pattern "{fwbootmgr}"
if (!$fwbootmgr){
Write-Host "Device is configured for Legacy Boot. Please change to UEFI boot."
log("Device is configured for Legacy Boot. Please change to UEFI boot.")
Exit 999
}
Else {
Write-Host "UEFI boot confirmed"
log("UEFI boot confirmed")
}

Try{
# Get the line of text with the GUID for the PXE boot option.
# IPV4 = most PXE boot options
# EFI Network = Hyper-V PXE boot option
$FullLine = (( Get-Content $FolderName\firmware.txt | Select-String "IPV4|EFI Network" -Context 1 -ErrorAction Stop ).context.precontext)[0]

# Remove all text but the GUID
$GUID = '{' + $FullLine.split('{')[1]

# Add the PXE boot option to the top of the boot order on next boot
bcdedit /set "{fwbootmgr}" bootsequence "$GUID"

Write-Host "Device will PXE boot on restart."
log("Device will PXE boot on restart.")
}
Catch {
Write-Host "An error occurred. The PXE boot option for this device may need to added to the script. Confirm the PXE boot option in the $FolderName\firmware.txt file."
log("An error occurred. The PXE boot option for this device may need to added to the script. Confirm the PXE boot option in the $FolderName\firmware.txt file.")
Exit 888
}