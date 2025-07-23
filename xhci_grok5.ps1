<#
Script: USB Controller Modifier
Author: Softhe
Description: Disables Interrupt Moderation (IMOD) or Interrupt Threshold Control in USB controllers.
#>

param (
    [string]$ConfigPath = "$PSScriptRoot\usb_controller_config.txt",
    [string]$KXToolPath = "C:\_\Programs\_exe\KX.exe"
)

# PowerShell version check
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "This script requires PowerShell 5 or higher."
    exit 1
}

# Start as administrator and propagate exit code
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $process = Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`" -KXToolPath `"$KXToolPath`"" -Verb RunAs -PassThru
    $process.WaitForExit()
    exit $process.ExitCode
}

$LocalKX = "$PSScriptRoot\KX.exe"

function Log-Output {
    param([string]$message)
    $logPath = "$PSScriptRoot\log.txt"
    # Write to log file with timestamp
    "$([DateTime]::Now) - $message" | Out-File -Append -FilePath $logPath
    # Write to console
    Write-Host $message
}

function KX-Exists {
    $ToolsKXExists = Test-Path -Path $KXToolPath -PathType Leaf
    $LocalKXExists = Test-Path -Path $LocalKX -PathType Leaf
    return @{LocalKXExists = $LocalKXExists; ToolsKXExists = $ToolsKXExists}
}

function Get-KX {
    $KXExists = KX-Exists
    if ($KXExists.ToolsKXExists) { return $KXToolPath } else { return $LocalKX }
}

function Check-For-Tool-Viability {
    try {
        $Value = & "$(Get-KX)" /RdMem32 "0x0"
        if ($Value -match 'Kernel Driver can not be loaded') {
            Log-Output "Kernel Driver cannot be loaded. A certificate was explicitly revoked by its issuer."
            Log-Output "In some cases, you might need to disable Microsoft Vulnerable Driver Blocklist for the tool to work."
            Log-Output "It will be done automatically, but it can also be done through the UI, in the Core Isolation section. If it doesn't work immediately, it may require a restart."
            Log-Output "If you are getting this message, it means you need to do this, otherwise you cannot run any type of tool that does this kind of change. Therefore, doing this would not be possible if you undo this change; the next reboot, it would stop working again. Enable or Disable at your own risk."

            # User confirmation for registry change
            $confirmation = Read-Host "Proceed with disabling Vulnerable Driver Blocklist? (y/n)"
            if ($confirmation -ne 'y') {
                Log-Output "User aborted registry modification."
                throw "Registry modification aborted by user."
            }

            New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\CI\Config\" -Name VulnerableDriverBlocklistEnable -PropertyType Dword -Value 0 -Force -ErrorAction Stop | Out-Null
            Log-Output "Registry modified successfully."
        }
    } catch {
        Log-Output "Error in Check-For-Tool-Viability: $_"
        throw
    }
}

function Get-Config {
    try {
        if (Test-Path -Path $ConfigPath) {
            return Get-Content -Path $ConfigPath | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' }
        } else {
            Log-Output "Configuration file not found at $ConfigPath. Please create it with Device IDs."
            return $null
        }
    } catch {
        Log-Output "Error reading config file: $_"
        return $null
    }
}

function Get-All-USB-Controllers {
    try {
        [PsObject[]]$USBControllers = @()

        $allUSBControllers = Get-CimInstance -ClassName Win32_USBController -ErrorAction Stop | Select-Object -Property Name, DeviceID
        foreach ($usbController in $allUSBControllers) {
            $allocatedResource = Get-CimInstance -ClassName Win32_PNPAllocatedResource -ErrorAction Stop | Where-Object { $_.Dependent.DeviceID -like "*$($usbController.DeviceID)*" } | Select @{N="StartingAddress";E={$_.Antecedent.StartingAddress}}
            $deviceMemory = Get-CimInstance -ClassName Win32_DeviceMemoryAddress -ErrorAction Stop | Where-Object { $_.StartingAddress -eq "$($allocatedResource.StartingAddress)" }

            $deviceProperties = Get-PnpDeviceProperty -InstanceId $usbController.DeviceID -ErrorAction Stop
            $locationInfo = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_LocationInfo' | Select -ExpandProperty Data
            $PDOName = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_PDOName' | Select -ExpandProperty Data

            $moreControllerData = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.DeviceID -eq "$($usbController.DeviceID)" } | Select-Object Service
            $Type = if ($moreControllerData.Service -ieq 'USBXHCI') {'XHCI'} elseif ($moreControllerData.Service -ieq 'USBEHCI') {'EHCI'} else {'Unknown'}

            if ([string]::IsNullOrWhiteSpace($deviceMemory.Name)) {
                continue
            }

            $USBControllers += [PsObject]@{
                Name = $usbController.Name
                DeviceId = $usbController.DeviceID
                MemoryRange = $deviceMemory.Name
                LocationInfo = $locationInfo
                PDOName = $PDOName
                Type = $Type
            }
        }
        return $USBControllers
    } catch {
        Log-Output "Error retrieving USB controllers: $_"
        return @()
    }
}

function Get-Type-From-Service {
    param ([string] $value)
    if ($value -ieq 'USBXHCI') {
        return 'XHCI'
    }
    if ($value -ieq 'USBEHCI') {
        return 'EHCI'
    }
    return 'Unknown'
}

function Convert-Decimal-To-Hex {
    param ([int64] $value = 0)
    return '0x' + [System.Convert]::ToString($value, 16).ToUpper()
}

function Convert-Hex-To-Decimal {
    param ([string] $value = "0x0")
    if ($value -notmatch '^0x[0-9A-Fa-f]+$') {
        throw "Invalid hex value: $value"
    }
    return [convert]::ToInt64($value, 16)
}

function Convert-Hex-To-Binary {
    param ([string] $value)
    if ($value -notmatch '^0x[0-9A-Fa-f]+$') {
        throw "Invalid hex value: $value"
    }
    $ConvertedValue = [Convert]::ToString([Convert]::ToInt64($value, 16), 2)
    return $ConvertedValue.PadLeft(32, '0')
}

function Convert-Binary-To-Hex {
    param ([string] $value)
    if ($value -notmatch '^[01]+$') {
        throw "Invalid binary value: $value"
    }
    $convertedValue = [Convert]::ToInt64($value, 2)
    return Convert-Decimal-To-Hex -value $convertedValue
}

function Get-Hex-Value-From-Tool-Result {
    param ([string] $value)
    if ($value.Split(" ").Length -lt 20) {
        Log-Output "KX.exe output format unexpected. Expected at least 20 fields, but found $(($value.Split(" ")).Length). This might indicate a change in the tool's output format."
        return "0x0" # Return a default value to avoid breaking the script
    }
    return $value.Split(" ")[19].Trim()
}

function Get-R32-Hex-From-Address {
    param ([string] $address)
    try {
        if ($address -notmatch '^0x[0-9A-Fa-f]+$') {
            throw "Invalid address format: $address"
        }
        $timeout = 10  # seconds
        $startTime = Get-Date
        $Value = $null
        while ([string]::IsNullOrWhiteSpace($Value) -and ((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
            $Value = & "$(Get-KX)" /RdMem32 $address
            Start-Sleep -Milliseconds 500
        }
        if ([string]::IsNullOrWhiteSpace($Value)) {
            throw "Timeout waiting for value from address $address"
        }
        return Get-Hex-Value-From-Tool-Result -value $Value
    } catch {
        Log-Output "Error in Get-R32-Hex-From-Address: $_"
        throw
    }
}

function Get-Left-Side-From-MemoryRange {
    param ([string] $memoryRange)
    if ([string]::IsNullOrWhiteSpace($memoryRange) -or $memoryRange -notmatch '-') {
        throw "Invalid memory range: $memoryRange"
    }
    return $memoryRange.Split("-")[0]
}

function Get-BitRange-From-Binary {
    param ([string] $binaryValue, [int] $from, [int] $to)
    if ($from -gt $to -or $from -lt 0 -or $to -ge $binaryValue.Length) {
        throw "Invalid bit range: from $from to $to"
    }
    $length = $to - $from + 1
    return $binaryValue.Substring($binaryValue.Length - 1 - $from, $length)
}

function Find-First-Interrupter-Data {
    param ([string] $memoryRange)
    try {
        $LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
        $CapabilityBaseAddressInDecimal = Convert-Hex-To-Decimal -value $LeftSideMemoryRange
        $RuntimeRegisterSpaceOffsetInDecimal = Convert-Hex-To-Decimal -value "0x18"
        $SumCapabilityPlusRuntime = Convert-Decimal-To-Hex -value ($CapabilityBaseAddressInDecimal + $RuntimeRegisterSpaceOffsetInDecimal)
        $Value = Get-R32-Hex-From-Address -address $SumCapabilityPlusRuntime
        $ValueInDecimal = Convert-Hex-To-Decimal -value $Value
        $TwentyFourInDecimal = Convert-Hex-To-Decimal -value "0x24"
        $Interrupter0PreAddressInDecimal = $CapabilityBaseAddressInDecimal + $ValueInDecimal + $TwentyFourInDecimal

        $FourInDecimal = Convert-Hex-To-Decimal -value "0x4"
        $HCSPARAMS1InHex = Convert-Decimal-To-Hex -value ($CapabilityBaseAddressInDecimal + $FourInDecimal)

        return @{ Interrupter0PreAddressInDecimal = $Interrupter0PreAddressInDecimal; HCSPARAMS1 = $HCSPARAMS1InHex }
    } catch {
        Log-Output "Error in Find-First-Interrupter-Data: $_"
        throw
    }
}

function Build-Interrupt-Threshold-Control-Data {
    param ([string] $memoryRange)
    try {
        $LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
        $LeftSideMemoryRangeInDecimal = Convert-Hex-To-Decimal -value $LeftSideMemoryRange
        $TwentyInDecimal = Convert-Hex-To-Decimal -value "0x20"
        $MemoryBase = Convert-Decimal-To-Hex -value ($LeftSideMemoryRangeInDecimal + $TwentyInDecimal)
        $MemoryBaseValue = Get-R32-Hex-From-Address -address $MemoryBase
        $ValueInBinary = Convert-Hex-To-Binary -value $MemoryBaseValue
        $ReplaceValue = '00000000'
        # Bits 23:16 (0-based from right) for ITC
        $ValueInBinaryLeftSide = $ValueInBinary.Substring(0, 8)  # Bits 31:24
        $ValueInBinaryRightSide = $ValueInBinary.Substring(16)   # Bits 15:0
        $ValueAddress = Convert-Binary-To-Hex -value ($ValueInBinaryLeftSide + $ReplaceValue + $ValueInBinaryRightSide)
        return [PsObject]@{ValueAddress = $ValueAddress; InterruptAddress = $MemoryBase}
    } catch {
        Log-Output "Error in Build-Interrupt-Threshold-Control-Data: $_"
        throw
    }
}

function Find-Interrupters-Amount {
    param ([string] $hcsParams1)
    try {
        $Value = Get-R32-Hex-From-Address -address $hcsParams1
        $ValueInBinary = Convert-Hex-To-Binary -value $Value
        $MaxIntrsInBinary = Get-BitRange-From-Binary -binaryValue $ValueInBinary -from 8 -to 18
        $InterruptersAmount = Convert-Hex-To-Decimal -value (Convert-Binary-To-Hex -value $MaxIntrsInBinary)
        return $InterruptersAmount
    } catch {
        Log-Output "Error in Find-Interrupters-Amount: $_"
        throw
    }
}

function Disable-IMOD {
    param (
        [string] $address,
        [string] $value = "0x00000000"
    )
    try {
        if ($address -notmatch '^0x[0-9A-Fa-f]+$') {
            throw "Invalid address format: $address"
        }
        if ($value -notmatch '^0x[0-9A-Fa-f]+$') {
            throw "Invalid value format: $value"
        }
        $timeout = 10  # seconds
        $startTime = Get-Date
        $Result = $null
        while ([string]::IsNullOrWhiteSpace($Result) -and ((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
            $Result = & "$(Get-KX)" /WrMem32 $address $value
            Start-Sleep -Milliseconds 500
        }
        if ([string]::IsNullOrWhiteSpace($Result)) {
            throw "Timeout writing to address $address"
        }
        return $Result
    } catch {
        Log-Output "Error in Disable-IMOD: $_"
        throw
    }
}

function Get-All-Interrupters {
    param ([int64] $preAddressInDecimal, [int32] $interruptersAmount)
    try {
        [PsObject[]]$Data = @()
        if ($interruptersAmount -lt 1 -or $interruptersAmount -gt 1024) {
            Log-Output "Device interrupters amount is out of range (1-1024): Found $interruptersAmount - Skipping IMOD disable for this device."
            return $Data
        }
        for ($i = 0; $i -lt $interruptersAmount; $i++) {
            $AddressInDecimal = $preAddressInDecimal + (32 * $i)
            $InterrupterAddress = Convert-Decimal-To-Hex -value $AddressInDecimal
            $Address = Get-R32-Hex-From-Address -address $InterrupterAddress
            $Data += [PsObject]@{ValueAddress = $Address; InterrupterAddress = $InterrupterAddress; Interrupter = $i}
        }
        return $Data
    } catch {
        Log-Output "Error in Get-All-Interrupters: $_"
        throw
    }
}

function Log-Device-Details {
    param ([PsObject] $item, [string] $interruptersAmount = 'None')
    Log-Output "Device Details:"
    Log-Output " - Name: $($item.Name)"
    Log-Output " - Device ID: $($item.DeviceId)"
    Log-Output " - Location Info: $($item.LocationInfo)"
    Log-Output " - PDO Name: $($item.PDOName)"
    Log-Output " - Device Type: $($item.Type)"
    Log-Output " - Memory Range: $($item.MemoryRange)"
    Log-Output " - Interrupters Count: $interruptersAmount"
    Log-Output "------------------------------------------------------------------"
}

function Execute-IMOD-Process {
    Log-Output "Started disabling Interrupt Moderation (XHCI) or Interrupt Threshold Control (EHCI) in USB controllers"

    # Get all USB controllers
    $USBControllers = Get-All-USB-Controllers
    Log-Output "Retrieved $($USBControllers.Length) USB controllers."

    if ($USBControllers.Length -eq 0) {
        Log-Output "Script didn't find any valid USB controllers to disable. Please check your system."
        return
    } else {
        Log-Output "Available USB Controllers:"
        $USBControllers | ForEach-Object { 
            Log-Output "$($_.Name) - Type: $($_.Type) - Device ID: $($_.DeviceId)" 
        }
    }

    # Check for configuration file
    $configuredDeviceIds = Get-Config
    if ($null -eq $configuredDeviceIds) {
        Log-Output "No valid configuration found. Exiting process."
        return
    }

    # Filter USB controllers based on the config file
    $USBControllers = $USBControllers | Where-Object { $configuredDeviceIds -contains $_.DeviceId }

    if ($USBControllers.Length -eq 0) {
        Log-Output "No USB controllers match the configured Device IDs."
        return
    }

    Log-Output "Processing $($USBControllers.Length) controllers based on configuration."

    # Process the selected controllers
    foreach ($item in $USBControllers) {
        $InterruptersAmount = 'None'

        if ($item.Type -eq 'XHCI') {
            Log-Output "Processing XHCI controller: $($item.Name) - Device ID: $($item.DeviceId)"

            # Fetch the interrupter data and disable IMOD
            $FirstInterrupterData = Find-First-Interrupter-Data -memoryRange $item.MemoryRange
            $InterruptersAmount = Find-Interrupters-Amount -hcsParams1 $FirstInterrupterData.HCSPARAMS1
            $AllInterrupters = Get-All-Interrupters -preAddressInDecimal $FirstInterrupterData.Interrupter0PreAddressInDecimal -interruptersAmount $InterruptersAmount

            foreach ($interrupterItem in $AllInterrupters) {
                $DisableResult = Disable-IMOD -address $interrupterItem.InterrupterAddress
                Log-Output "Disabled IMOD - Interrupter $($interrupterItem.Interrupter) - Interrupter Address: $($interrupterItem.InterrupterAddress) - Value Address: $($interrupterItem.ValueAddress) - Result: $DisableResult"
            }
        }

        if ($item.Type -eq 'EHCI') {
            Log-Output "Processing EHCI controller: $($item.Name) - Device ID: $($item.DeviceId)"
            # For EHCI, build interrupt threshold control data
            $InterruptData = Build-Interrupt-Threshold-Control-Data -memoryRange $item.MemoryRange
            $DisableResult = Disable-IMOD -address $InterruptData.InterruptAddress -value $InterruptData.ValueAddress
            Log-Output "Disabled Interrupt Threshold Control - Interrupt Address: $($InterruptData.InterruptAddress) - Value Address: $($InterruptData.ValueAddress) - Result: $DisableResult"
        }

        Log-Device-Details -item $item -interruptersAmount $InterruptersAmount
    }
}

# Main execution with global error handling
try {
    Check-For-Tool-Viability
    Execute-IMOD-Process
    Log-Output "Script completed successfully."
    exit 0
} catch {
    Log-Output "Script failed: $_"
    exit 1
}