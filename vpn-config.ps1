param (
    [Parameter(Mandatory = $true)]
    [string]$RESOURCE_GROUP,

    [Parameter(Mandatory = $true)]
    [string]$VPG_NAME,

    [Parameter(Mandatory = $true)]
    [string]$PRESHARED_KEY 
)

# Get the Virtual Network Gateway details
$VPG = az network vnet-gateway show `
    --name $VPG_NAME `
    --resource-group $RESOURCE_GROUP `
    | ConvertFrom-Json

# Extract public IP resource IDs into an array
$PUBLIC_IP_IDS = @($VPG.ipConfigurations | ForEach-Object { $_.publicIpAddress.id })

# Retrieve public IPs by index
$VGW_PUBLIC_IP1 = az network public-ip show --ids $PUBLIC_IP_IDS[0] | ConvertFrom-Json
$VGW_PUBLIC_IP2 = az network public-ip show --ids $PUBLIC_IP_IDS[1] | ConvertFrom-Json

# Display the IP addresses
Write-Host "Tunnel 1 Public IP: $($VGW_PUBLIC_IP1.ipAddress)"
Write-Host "Tunnel 2 Public IP: $($VGW_PUBLIC_IP2.ipAddress)"

# Build the configuration content
$config = @"
# ESP + IKE ===========

set vpn ipsec esp-group ESP-GROUP lifetime '3600'
set vpn ipsec esp-group ESP-GROUP pfs disable
set vpn ipsec esp-group ESP-GROUP proposal 1 encryption 'aes256'
set vpn ipsec esp-group ESP-GROUP proposal 1 hash 'sha1'

set vpn ipsec ike-group IKE-GROUP dead-peer-detection action 'restart'
set vpn ipsec ike-group IKE-GROUP dead-peer-detection interval '10'
set vpn ipsec ike-group IKE-GROUP dead-peer-detection timeout '30'
set vpn ipsec ike-group IKE-GROUP key-exchange 'ikev2'
set vpn ipsec ike-group IKE-GROUP lifetime '28800'
set vpn ipsec ike-group IKE-GROUP proposal 1 dh-group '2'
set vpn ipsec ike-group IKE-GROUP proposal 1 encryption 'aes256'
set vpn ipsec ike-group IKE-GROUP proposal 1 hash 'sha1'

# TUNNEL 1 ===========

set interfaces vti vti0 address '169.254.0.1/30'
set interfaces vti vti0 description 'VPC tunnel 1'
set interfaces vti vti0 ip adjust-mss 1350
set interfaces vti vti0 mtu '1436'

set protocols static route 10.0.0.0/16 interface vti0
set protocols static route 10.2.0.0/16 interface vti0

set vpn ipsec authentication psk Azure-T1 id $($VGW_PUBLIC_IP1.ipAddress)
set vpn ipsec authentication psk Azure-T1 id 192.168.100.200
set vpn ipsec authentication psk Azure-T1 secret '$PRESHARED_KEY'

set vpn ipsec site-to-site peer Azure-T1 authentication mode 'pre-shared-secret'
set vpn ipsec site-to-site peer Azure-T1 connection-type 'initiate'
set vpn ipsec site-to-site peer Azure-T1 description 'ipsec'
set vpn ipsec site-to-site peer Azure-T1 ike-group IKE-GROUP
set vpn ipsec site-to-site peer Azure-T1 local-address '192.168.100.200'
set vpn ipsec site-to-site peer Azure-T1 remote-address '$($VGW_PUBLIC_IP1.ipAddress)'
set vpn ipsec site-to-site peer Azure-T1 vti bind 'vti0'
set vpn ipsec site-to-site peer Azure-T1 vti esp-group ESP-GROUP
set vpn ipsec site-to-site peer Azure-T1 force-udp-encapsulation

# TUNNEL 2 ===========

set interfaces vti vti1 address '169.254.0.2/30'
set interfaces vti vti1 description 'VPC tunnel 2'
set interfaces vti vti1 ip adjust-mss 1350
set interfaces vti vti1 mtu '1436'

set protocols static route 10.0.0.0/16 interface vti1
set protocols static route 10.2.0.0/16 interface vti1

set vpn ipsec authentication psk Azure-T2 id $($VGW_PUBLIC_IP2.ipAddress)
set vpn ipsec authentication psk Azure-T2 id 192.168.100.200
set vpn ipsec authentication psk Azure-T2 secret '$PRESHARED_KEY'

set vpn ipsec site-to-site peer Azure-T2 authentication mode 'pre-shared-secret'
set vpn ipsec site-to-site peer Azure-T2 connection-type 'initiate'
set vpn ipsec site-to-site peer Azure-T2 description 'ipsec'
set vpn ipsec site-to-site peer Azure-T2 ike-group IKE-GROUP
set vpn ipsec site-to-site peer Azure-T2 local-address '192.168.100.200'
set vpn ipsec site-to-site peer Azure-T2 remote-address '$($VGW_PUBLIC_IP2.ipAddress)'
set vpn ipsec site-to-site peer Azure-T2 vti bind 'vti1'
set vpn ipsec site-to-site peer Azure-T2 vti esp-group ESP-GROUP
set vpn ipsec site-to-site peer Azure-T2 force-udp-encapsulation
"@

# Write to output file
$config | Set-Content -Path "vpn-config.txt"