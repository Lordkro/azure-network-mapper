# Azure Network Inventory Mapper
# Exports network topology to CSV + Draw.IO diagram
# Author: Cass (OpenClaw)
# Version: 1.0

[CmdletBinding()]
param()

# Ensure Az module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Error "Az PowerShell module is not installed. Run: Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force"
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
$subscriptions = Get-AzSubscription
Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green

$allResources = @()
$diagramNodes = @()
$diagramEdges = @()

# Initialize Draw.IO document structure
$drawio = @"
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net">
  <diagram name="Azure Network Topology">
    <mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
"@

$nodeIdCounter = 2
$subscriptionColors = @{}
$random = [System.Random]::new()

# Helper: Generate a color per subscription
function Get-SubscriptionColor($subId) {
    if (-not $subscriptionColors.ContainsKey($subId)) {
        $subscriptionColors[$subId] = "#$($random.Next(0x1000000).ToString('X6') | ForEach-Object { $_.PadLeft(6, '0') })"
    }
    return $subscriptionColors[$subId]
}

foreach ($sub in $subscriptions) {
    Write-Host "Processing subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    # Get VNets
    $vnets = Get-AzVirtualNetwork
    foreach ($vnet in $vnets) {
        $vnetId = "vnet_$($vnet.Id -replace '[^a-zA-Z0-9]', '_')"
        $vnetName = $vnet.Name

        # Add VNet node to diagram (subnet container)
        $vnetColor = Get-SubscriptionColor $sub.Id
        $diagramNodes += @"
        <mxCell id="$vnetId" value="$vnetName`n$($vnet.AddressSpace.AddressPrefixes -join ', ')" style="rounded=1;whiteSpace=wrap;html=1;fillColor=$vnetColor;strokeColor=#000000;" vertex="1" parent="1">
          <mxGeometry x="$(($nodeIdCounter % 10) * 100)" y="$(([math]::Floor($nodeIdCounter / 10) * 100))" width="200" height="80" as="geometry"/>
        </mxCell>
"@
        $nodeIdCounter++

        # Process subnets
        foreach ($subnet in $vnet.Subnets) {
            $subnetId = "subnet_$($subnet.Id -replace '[^a-zA-Z0-9]', '_')"
            $subnetName = $subnet.Name
            $subnetPrefix = $subnet.AddressPrefix

            $diagramNodes += @"
            <mxCell id="$subnetId" value="$subnetName`n$subnetPrefix" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#E8F5E9;strokeColor=#000000;" vertex="1" parent="$vnetId">
              <mxGeometry x="20" y="20" width="160" height="40" as="geometry"/>
            </mxCell>
"@
            $nodeIdCounter++

            # Record subnet data
            $allResources += [PSCustomObject]@{
                Subscription = $sub.Name
                SubscriptionId = $sub.Id
                ResourceGroup = $vnet.ResourceGroupName
                Type = "Subnet"
                Name = $subnetName
                VNet = $vnetName
                AddressPrefix = $subnetPrefix
                NSG = $subnet.NetworkSecurityGroup?.Id -replace '.*/'
            }
        }

        # Get NICs in this VNet
        $nics = Get-AzNetworkInterface | Where-Object { $_.VirtualNetwork -and $_.VirtualNetwork.Id -eq $vnet.Id }
        foreach ($nic in $nics) {
            $nicId = "nic_$($nic.Id -replace '[^a-zA-Z0-9]', '_')"
            $nicName = $nic.Name
            $ipConfig = $nic.IPConfigurations[0]
            $privateIp = $ipConfig.PrivateIPAddress
            $subnetRef = "subnet_$($ipConfig.Subnet.Id -replace '[^a-zA-Z0-9]', '_')"

            # Create NIC node (outside VNet container, connected to subnet)
            $diagramNodes += @"
            <mxCell id="$nicId" value="$nicName`n$privateIp" style="shape=ellipse;whiteSpace=wrap;html=1;fillColor=#FFF3E0;strokeColor=#000000;" vertex="1" parent="1">
              <mxGeometry x="$(($nodeIdCounter % 10) * 100 + 50)" y="$(([math]::Floor($nodeIdCounter / 10) * 100) + 120)" width="120" height="40" as="geometry"/>
            </mxCell>
"@
            $nodeIdCounter++

            # Edge from subnet to NIC
            $diagramEdges += @"
            <mxCell id="edge_$($nodeIdCounter)" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" parent="1" source="$subnetRef" target="$nicId" edge="1">
              <mxGeometry relative="1" as="geometry"/>
            </mxCell>
"@
            $nodeIdCounter++

            # Check for Public IP on NIC
            if ($ipConfig.PublicIPAddress) {
                $publicIp = $ipConfig.PublicIPAddress
                $pipId = "pip_$($publicIp.Id -replace '[^a-zA-Z0-9]', '_')"
                $pipName = $publicIp.Name
                $pipAddress = $publicIp.IpAddress

                $diagramNodes += @"
                <mxCell id="$pipId" value="$pipName`n$pipAddress" style="shape=cloud;whiteSpace=wrap;html=1;fillColor=#FFEBEE;strokeColor=#000000;" vertex="1" parent="1">
                  <mxGeometry x="$(($nodeIdCounter % 10) * 100 + 100)" y="$(([math]::Floor($nodeIdCounter / 10) * 100) + 180)" width="100" height="50" as="geometry"/>
                </mxCell>
"@
                $nodeIdCounter++

                # Edge from NIC to Public IP
                $diagramEdges += @"
                <mxCell id="edge_$($nodeIdCounter)" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" parent="1" source="$nicId" target="$pipId" edge="1">
                  <mxGeometry relative="1" as="geometry"/>
                </mxCell>
"@
                $nodeIdCounter++

                $allResources += [PSCustomObject]@{
                    Subscription = $sub.Name
                    SubscriptionId = $sub.Id
                    ResourceGroup = $nic.ResourceGroupName
                    Type = "PublicIP"
                    Name = $pipName
                    IPAddress = $pipAddress
                    AssociatedWith = $nicName
                }
            }

            $allResources += [PSCustomObject]@{
                Subscription = $sub.Name
                SubscriptionId = $sub.Id
                ResourceGroup = $nic.ResourceGroupName
                Type = "NetworkInterface"
                Name = $nicName
                PrivateIP = $privateIp
                Subnet = $subnetName
                VNet = $vnetName
            }
        }
    }
}

# Close Draw.IO XML
$drawio += $diagramNodes -join "`n"
$drawio += $diagramEdges -join "`n"
$drawio += @"
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
"@

# Export outputs
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvPath = "network-inventory-$timestamp.csv"
$drawioPath = "network-topology-$timestamp.drawio"

$allResources | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
$drawio | Out-File -FilePath $drawioPath -Encoding UTF8

Write-Host "`nExported:" -ForegroundColor Green
Write-Host "  CSV:  $csvPath" -ForegroundColor Cyan
Write-Host "  DrawIO: $drawioPath" -ForegroundColor Cyan
Write-Host "`nImport the .drawio file into https://app.diagrams.net/ to view the topology." -ForegroundColor Yellow
