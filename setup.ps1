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
    Remove-NetNat -Name $NATName
}

New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix $NATPrefix

# IPsec Port Forwarding
# ============================

$maxRetries = 5
$retryDelay = 5
$attempt = 0
$PublicIP = $null
$ipRegex = '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$'

do {
    try {
        $PublicIP = Invoke-RestMethod -Uri "http://checkip.amazonaws.com/" -ErrorAction Stop
        $PublicIP = $PublicIP.Trim()

        if ($PublicIP -match $ipRegex) {
            Write-Host "Public IP Address: $PublicIP"
            break
        } else {
            Write-Warning "Invalid IP format received: $PublicIP"
            $PublicIP = $null
        }
    } catch {
        Write-Warning "Attempt $($attempt + 1) failed: $_"
    }

    $attempt++
    if ($attempt -lt $maxRetries) {
        Start-Sleep -Seconds $retryDelay
    } else {
        Write-Error "Failed to retrieve a valid public IP address after $maxRetries attempts."
    }
} while ($attempt -lt $maxRetries)

# Port Forwarding for IPsec
netsh interface portproxy add v4tov4 listenport=500 listenaddress=1$PublicIP connectport=500 connectaddress=192.168.100.200
netsh interface portproxy add v4tov4 listenport=4500 listenaddress=$PublicIP connectport=4500 connectaddress=192.168.100.200

# Update GNS3 VM to use the new switch
# ============================

Connect-VMNetworkAdapter -VMName "GNS3 VM" -SwitchName "$SwitchName"

Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
Set-VMNetworkAdapter -VMName $VMName -MacAddressSpoofing On
