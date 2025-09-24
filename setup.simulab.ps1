# Vars
# ============================

$VMName = "GNS3 VM"
$SwitchName = "InternalSwitch"
$IPAddress = "192.168.100.1"
$SubnetMask = "255.255.255.0"
$NATName = "NATNetwork"
$NATPrefix = "192.168.100.0/24"

# Create new VM switch
# ============================

New-VMSwitch -Name $SwitchName -SwitchType Internal

$MaxRetries = 10
$DelaySeconds = 3
$NetAdapter = $null

for ($i = 1; $i -le $MaxRetries; $i++) {
    Write-Host "Checking for network adapter..."
    $NetAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }

    if ($NetAdapter) {
        Write-Host "Network adapter found: $($NetAdapter.Name)"
        break
    } else {
        Write-Host "Adapter not found. Waiting $DelaySeconds seconds before retrying..."
        Start-Sleep -Seconds $DelaySeconds
    }
}

# Final check
if (-not $NetAdapter) {
    Write-Error "Failed to find network adapter for switch '$SwitchName' after $MaxRetries attempts."
} else {
    # Proceed with IP configuration
    New-NetIPAddress -InterfaceAlias $NetAdapter.Name -IPAddress $IPAddress -PrefixLength 24
}

# Create new NAT
# ============================

# Remove existing NAT if it exists
$existingNat = Get-NetNat -Name $NATName -ErrorAction SilentlyContinue
if ($existingNat) {
    Remove-NetNat -Name $NATName -Confirm:$false
}

New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix $NATPrefix

# Update GNS3 VM to use the new switch
# ============================

Connect-VMNetworkAdapter -VMName "GNS3 VM" -SwitchName "$SwitchName"

Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
Set-VMNetworkAdapter -VMName $VMName -MacAddressSpoofing On

# Update VM Memory
# ============================

# Check if the VM exists
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "VM '$VMName' not found." -ForegroundColor Red
    exit
}

# Update memory and cores limit
$StartupMemoryBytes = 48GB
$NumberOfCores = 8

Set-VMMemory -VMName $VMName `
    -DynamicMemoryEnabled $false `
    -StartupBytes $StartupMemoryBytes

Write-Host "VM memory set to $([math]::Round($StartupMemoryBytes / 1GB))GB" -ForegroundColor Green

Set-VMProcessor -VMName $VMName `
    -Count $NumberOfCores

Write-Host "VM virtual cores set to $NumberOfCores" -ForegroundColor Green