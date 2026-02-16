# Azure Network Mapper

[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-5391FE?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A PowerShell script that maps your entire Azure tenant's network infrastructure and exports it to CSV.

## What it does

- Enumerates all subscriptions in your Azure tenant **in parallel**
- Discovers:
  - Virtual Networks (VNets) and their address spaces
  - Subnets within each VNet
  - Network Interfaces (NICs) with private IPs
  - Public IP addresses (attached and orphaned)
  - Load Balancers with frontend/backend configurations
  - Application Gateways
  - Network Security Groups (NSGs)
- Generates a **CSV inventory** for spreadsheets, databases, or further analysis

## Prerequisites

- **PowerShell 7.0** or later (required for parallel processing)
- **Minimal Az modules** (lightweight, ~30MB total vs ~500MB for full Az):
  ```powershell
  Install-Module -Name Az.Accounts -Scope CurrentUser -Repository PSGallery -Force
  Install-Module -Name Az.Network -Scope CurrentUser -Repository PSGallery -Force
  ```
- Azure authentication: You must be logged in (`Connect-AzAccount`) or have sufficient permissions to read network resources

## Usage

```powershell
# Clone/download this repo
cd azure-network-mapper

# Run the script (default: 5 parallel subscriptions)
.\AzureNetworkMapper.ps1

# Or specify parallelism level (1-20)
.\AzureNetworkMapper.ps1 -MaxParallelSubscriptions 10
```

The script will:
1. Check for existing Azure login, or prompt you to login
2. Fetch all subscriptions you have access to
3. Process subscriptions **in parallel** for faster execution
4. Export a timestamped CSV file: `network-inventory-YYYYMMDD-HHMMSS.csv`

## Example Output

### CSV Columns
| Column | Description |
|--------|-------------|
| Subscription | Subscription name |
| SubscriptionId | Subscription GUID |
| ResourceGroup | Resource group name |
| Type | Resource type (Subnet, NetworkInterface, PublicIP, LoadBalancer, ApplicationGateway) |
| Name | Resource name |
| VNet | Associated Virtual Network |
| IPRange | Address prefix (for subnets) |
| PrivateIP | Private IP address |
| PublicIP | Public IP address |
| NSG | Associated Network Security Group |
| AssociatedWith | Parent/related resource (e.g., subnet for NIC, backend pools for LB) |

### Orphaned Public IPs
The script automatically detects public IPs that are not attached to any resource and marks them as `ORPHANED` in the `AssociatedWith` column — useful for cost optimization.

## Performance

The script uses parallel processing to dramatically improve performance on large tenants:

| Subscriptions | Sequential (v1.1) | Parallel (v1.2) |
|---------------|-------------------|-----------------|
| 5 | ~2.5 min | ~30 sec |
| 20 | ~10 min | ~2 min |
| 50+ | ~25 min | ~5 min |

*Times vary based on resource count and API latency.*

## Future Enhancements

- [ ] Query Azure Resource Graph for faster enumeration (large tenants)
- [ ] Include Azure Firewall and Route Tables
- [ ] Add Azure Bastion hosts
- [ ] Show VPN Gateways / ExpressRoute circuits
- [ ] Export to HTML interactive report
- [ ] Highlight overlapping IP ranges across VNets
- [ ] Support for Private Endpoints and Private DNS Zones
- [ ] Include Application Security Groups (ASGs)

## Changelog

### v1.2 (Current)
- ✅ **Parallel subscription processing** — up to 5x faster on large tenants
- ✅ Configurable parallelism via `-MaxParallelSubscriptions` parameter
- ✅ Thread-safe collections for concurrent operations
- ✅ Integrated orphan detection (no redundant API calls)
- ✅ Execution time reporting
- ✅ Requires PowerShell 7.0+

### v1.1
- ✅ Batched queries (single `Get-AzNetworkInterface` call per subscription)
- ✅ Detect orphaned/unused public IPs
- ✅ Load Balancers and Application Gateways support
- ✅ NSG associations
- ✅ Minimal Az modules (Accounts + Network only)

## License

MIT License — feel free to modify and share.

## Contributing

Pull requests welcome! Open an issue if you find bugs or have feature requests.

---

**Built for Azure Cloud Engineers, by someone who needed it for work.**
