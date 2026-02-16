# Azure Network Inventory Mapper
# Exports network topology to CSV
# Author: Lordkro
# Version: 1.2 - Optimized with parallel processing

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Maximum number of subscriptions to process in parallel")]
    [ValidateRange(1, 20)]
    [int]$MaxParallelSubscriptions = 5
)

# Ensure required Az modules are installed (lightweight)
$requiredModules = @('Az.Accounts', 'Az.Network')
$missingModules = @()
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        $missingModules += $mod
    }
}
if ($missingModules.Count -gt 0) {
    Write-Error "Required Az modules missing: $($missingModules -join ', '). Run:`nInstall-Module -Name $($missingModules -join ', ') -Scope CurrentUser -Repository PSGallery -Force"
    exit 1
}

# Check if already authenticated, otherwise prompt
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount
}

# Get all subscriptions in tenant
Write-Host "Fetching subscriptions..." -ForegroundColor Cyan
$subscriptions = @(Get-AzSubscription)
Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green

# Thread-safe collections for parallel processing
$allResources = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
$recordedPublicIpIds = [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()
$orphanedPublicIPs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
$processedCount = [ref]0
$totalSubs = $subscriptions.Count

Write-Host "Processing subscriptions in parallel (max $MaxParallelSubscriptions at a time)..." -ForegroundColor Cyan
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$subscriptions | ForEach-Object -ThrottleLimit $MaxParallelSubscriptions -Parallel {
    $sub = $_
    # Import thread-safe collections from parent scope
    $resources = $using:allResources
    $recordedPips = $using:recordedPublicIpIds
    $orphanPips = $using:orphanedPublicIPs
    
    try {
        # Each parallel runspace needs its own Az context
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        Write-Host "  [$($sub.Name)] Starting..." -ForegroundColor Gray

        # Get all VNets
        $vnets = @(Get-AzVirtualNetwork -ErrorAction SilentlyContinue)

        # Batch fetch all resources for this subscription
        $allNics = @(Get-AzNetworkInterface -ErrorAction SilentlyContinue)
        $allPublicIps = @(Get-AzPublicIpAddress -ErrorAction SilentlyContinue)
        $allNsgs = @(Get-AzNetworkSecurityGroup -ErrorAction SilentlyContinue)
        $loadBalancers = @(Get-AzLoadBalancer -ErrorAction SilentlyContinue)
        $appGateways = @(Get-AzApplicationGateway -ErrorAction SilentlyContinue)

        # Index NICs by VNet Id (via subnet association)
        $nicsByVnet = @{}
        foreach ($nic in $allNics) {
            foreach ($ipConfig in $nic.IpConfigurations) {
                if ($ipConfig.Subnet -and $ipConfig.Subnet.Id) {
                    $subnetId = $ipConfig.Subnet.Id
                    $vnetId = $subnetId -replace '/subnets/.*$', ''
                    if (-not $nicsByVnet.ContainsKey($vnetId)) { $nicsByVnet[$vnetId] = @() }
                    if ($nicsByVnet[$vnetId] -notcontains $nic) {
                        $nicsByVnet[$vnetId] += $nic
                    }
                }
            }
        }

        # Index Public IPs by Id for quick lookup
        $publicIpsById = @{}
        foreach ($pip in $allPublicIps) {
            $publicIpsById[$pip.Id] = $pip
        }

        foreach ($vnet in $vnets) {
            $vnetName = $vnet.Name

            # Process subnets
            foreach ($subnet in $vnet.Subnets) {
                $subnetName = $subnet.Name
                $subnetPrefix = if ($subnet.AddressPrefix -is [System.Collections.IEnumerable] -and $subnet.AddressPrefix -isnot [string]) {
                    ($subnet.AddressPrefix -join ', ')
                } else {
                    $subnet.AddressPrefix
                }

                $nsgName = if ($subnet.NetworkSecurityGroup) { $subnet.NetworkSecurityGroup.Id -replace '.*/' } else { '' }
                $resources.Add([PSCustomObject]@{
                    Subscription   = $sub.Name
                    SubscriptionId = $sub.Id
                    ResourceGroup  = $vnet.ResourceGroupName
                    Type           = "Subnet"
                    Name           = $subnetName
                    VNet           = $vnetName
                    IPRange        = $subnetPrefix
                    PrivateIP      = ''
                    PublicIP       = ''
                    NSG            = $nsgName
                    AssociatedWith = ''
                })
            }

            # Get NICs in this VNet
            $nics = $nicsByVnet[$vnet.Id] ?? @()
            
            foreach ($nic in $nics) {
                $nicName = $nic.Name
                $ipConfig = $nic.IPConfigurations[0]
                $privateIp = $ipConfig.PrivateIPAddress
                $nicSubnetName = $ipConfig.Subnet.Id -replace '.*/subnets/', '' -replace '/.*', ''

                # Check for Public IP on NIC
                if ($ipConfig.PublicIPAddress) {
                    $publicIpObj = $ipConfig.PublicIPAddress
                    $pipId = "pip_$($publicIpObj.Id -replace '[^a-zA-Z0-9]', '_')"
                    $pipName = $publicIpObj.Name
                    # Get actual IP address from our indexed collection
                    $pipAddress = if ($publicIpsById.ContainsKey($publicIpObj.Id)) { $publicIpsById[$publicIpObj.Id].IpAddress } else { '' }

                    $resources.Add([PSCustomObject]@{
                        Subscription   = $sub.Name
                        SubscriptionId = $sub.Id
                        ResourceGroup  = $nic.ResourceGroupName
                        Type           = "PublicIP"
                        Name           = $pipName
                        VNet           = $vnetName
                        IPRange        = ''
                        PrivateIP      = ''
                        PublicIP       = $pipAddress
                        NSG            = ''
                        AssociatedWith = $nicName
                    })
                    $recordedPips.TryAdd($pipId, $true) | Out-Null
                }

                $resources.Add([PSCustomObject]@{
                    Subscription   = $sub.Name
                    SubscriptionId = $sub.Id
                    ResourceGroup  = $nic.ResourceGroupName
                    Type           = "NetworkInterface"
                    Name           = $nicName
                    VNet           = $vnetName
                    IPRange        = ''
                    PrivateIP      = $privateIp
                    PublicIP       = ''
                    NSG            = if ($nic.NetworkSecurityGroup) { $nic.NetworkSecurityGroup.Id -replace '.*/' } else { '' }
                    AssociatedWith = $nicSubnetName
                })
            }

            # Process Load Balancers
            foreach ($lb in $loadBalancers) {
                $lbFrontendIpConfig = $lb.FrontendIpConfigurations | Where-Object { 
                    $_.Subnet -and ($_.Subnet.Id -like "$($vnet.Id)/subnets/*")
                }
                if (-not $lbFrontendIpConfig) { continue }

                $lbName = $lb.Name
                $lbPrivateIp = if ($lbFrontendIpConfig.PrivateIPAddress) { $lbFrontendIpConfig.PrivateIPAddress } else { '' }
                $lbPublicIp = ''
                
                if ($lbFrontendIpConfig.PublicIPAddress -and $publicIpsById.ContainsKey($lbFrontendIpConfig.PublicIPAddress.Id)) {
                    $lbPublicIp = $publicIpsById[$lbFrontendIpConfig.PublicIPAddress.Id].IpAddress
                }

                $resources.Add([PSCustomObject]@{
                    Subscription   = $sub.Name
                    SubscriptionId = $sub.Id
                    ResourceGroup  = $lb.ResourceGroupName
                    Type           = "LoadBalancer"
                    Name           = $lbName
                    VNet           = $vnetName
                    IPRange        = ''
                    PrivateIP      = $lbPrivateIp
                    PublicIP       = $lbPublicIp
                    NSG            = ''
                    AssociatedWith = "Backend: $($lb.BackendAddressPools.Name -join ', ')"
                })

                # Record Frontend Public IP
                if ($lbFrontendIpConfig.PublicIPAddress) {
                    $lbPipId = "pip_$($lbFrontendIpConfig.PublicIPAddress.Id -replace '[^a-zA-Z0-9]', '_')"
                    if ($recordedPips.TryAdd($lbPipId, $true)) {
                        $lbPipObj = $publicIpsById[$lbFrontendIpConfig.PublicIPAddress.Id]
                        if ($lbPipObj) {
                            $resources.Add([PSCustomObject]@{
                                Subscription   = $sub.Name
                                SubscriptionId = $sub.Id
                                ResourceGroup  = $lbPipObj.ResourceGroupName
                                Type           = "PublicIP"
                                Name           = $lbPipObj.Name
                                VNet           = $vnetName
                                IPRange        = ''
                                PrivateIP      = ''
                                PublicIP       = $lbPipObj.IpAddress
                                NSG            = ''
                                AssociatedWith = "LB: $lbName"
                            })
                        }
                    }
                }
            }

            # Process Application Gateways
            foreach ($appGw in $appGateways) {
                $appGwFrontendIpConfig = $appGw.FrontendIPConfigurations | Where-Object { 
                    $_.Subnet -and ($_.Subnet.Id -like "$($vnet.Id)/subnets/*")
                }
                if (-not $appGwFrontendIpConfig) { continue }

                $appGwName = $appGw.Name
                $appGwPrivateIp = if ($appGwFrontendIpConfig.PrivateIPAddress) { $appGwFrontendIpConfig.PrivateIPAddress } else { '' }
                $appGwPublicIp = ''
                
                if ($appGwFrontendIpConfig.PublicIPAddress -and $publicIpsById.ContainsKey($appGwFrontendIpConfig.PublicIPAddress.Id)) {
                    $appGwPublicIp = $publicIpsById[$appGwFrontendIpConfig.PublicIPAddress.Id].IpAddress
                }

                $resources.Add([PSCustomObject]@{
                    Subscription   = $sub.Name
                    SubscriptionId = $sub.Id
                    ResourceGroup  = $appGw.ResourceGroupName
                    Type           = "ApplicationGateway"
                    Name           = $appGwName
                    VNet           = $vnetName
                    IPRange        = ''
                    PrivateIP      = $appGwPrivateIp
                    PublicIP       = $appGwPublicIp
                    NSG            = ''
                    AssociatedWith = "Backend: $($appGw.BackendAddressPools.Name -join ', ')"
                })

                # Record Frontend Public IP
                if ($appGwFrontendIpConfig.PublicIPAddress) {
                    $agwPipId = "pip_$($appGwFrontendIpConfig.PublicIPAddress.Id -replace '[^a-zA-Z0-9]', '_')"
                    if ($recordedPips.TryAdd($agwPipId, $true)) {
                        $agwPipObj = $publicIpsById[$appGwFrontendIpConfig.PublicIPAddress.Id]
                        if ($agwPipObj) {
                            $resources.Add([PSCustomObject]@{
                                Subscription   = $sub.Name
                                SubscriptionId = $sub.Id
                                ResourceGroup  = $agwPipObj.ResourceGroupName
                                Type           = "PublicIP"
                                Name           = $agwPipObj.Name
                                VNet           = $vnetName
                                IPRange        = ''
                                PrivateIP      = ''
                                PublicIP       = $agwPipObj.IpAddress
                                NSG            = ''
                                AssociatedWith = "AppGw: $appGwName"
                            })
                        }
                    }
                }
            }
        }

        # Detect orphaned Public IPs within this subscription (no extra API call needed!)
        foreach ($pip in $allPublicIps) {
            $pipId = "pip_$($pip.Id -replace '[^a-zA-Z0-9]', '_')"
            if (-not $recordedPips.TryAdd($pipId, $true)) { continue }  # Already recorded

            $isAttached = $false
            if ($pip.IpConfiguration) { $isAttached = $true }
            elseif ($pip.LoadBalancer) { $isAttached = $true }
            elseif ($pip.ApplicationGateway) { $isAttached = $true }

            $orphanStatus = -not $isAttached
            if ($orphanStatus) {
                $orphanPips.Add($pip)
            }

            $resources.Add([PSCustomObject]@{
                Subscription   = $sub.Name
                SubscriptionId = $sub.Id
                ResourceGroup  = $pip.ResourceGroupName
                Type           = "PublicIP"
                Name           = $pip.Name
                VNet           = ''
                IPRange        = ''
                PrivateIP      = ''
                PublicIP       = $pip.IpAddress
                NSG            = ''
                AssociatedWith = if ($isAttached) { 'LoadBalancer/AppGateway' } else { if ($orphanStatus) { 'ORPHANED' } else { '' } }
            })
        }

        Write-Host "  [$($sub.Name)] Done - $($vnets.Count) VNets, $($allNics.Count) NICs, $($allPublicIps.Count) PIPs" -ForegroundColor Green
    }
    catch {
        Write-Host "  [$($sub.Name)] Error: $_" -ForegroundColor Red
    }
}

$stopwatch.Stop()

$stopwatch.Stop()

# Summary of orphans
$orphanCount = $orphanedPublicIPs.Count
if ($orphanCount -gt 0) {
    Write-Host "`nFound $orphanCount orphaned public IP(s) (not attached to any resource)." -ForegroundColor Yellow
} else {
    Write-Host "`nNo orphaned public IPs found." -ForegroundColor Green
}

# Convert thread-safe collection to array for export
$resourceList = @($allResources.ToArray())

# Export CSV output
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvPath = "network-inventory-$timestamp.csv"

$resourceList | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "`nExported:" -ForegroundColor Green
Write-Host "  CSV: $csvPath" -ForegroundColor Cyan
Write-Host "`nTotal resources inventoried: $($resourceList.Count)" -ForegroundColor Green
Write-Host "Completed in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) seconds" -ForegroundColor Cyan
