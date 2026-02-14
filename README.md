# Azure Network Mapper

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A PowerShell script that maps your entire Azure tenant's network infrastructure and exports it to both CSV and Draw.IO diagram format.

## What it does

- Enumerates all subscriptions in your Azure tenant
- Discovers:
  - Virtual Networks (VNet) and their address spaces
  - Subnets within each VNet
  - Network Interfaces (NICs) with private IPs
  - Public IP addresses attached to NICs
- Generates two outputs:
  1. **CSV** — full inventory for spreadsheets/databases
  2. **Draw.IO diagram** — visual topology map (import into https://app.diagrams.net/)

## Prerequisites

- **PowerShell 5.1** or later
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

# Run the script
.\AzureNetworkMapper.ps1
```

The script will:
1. Check for existing Azure login, or prompt you to login
2. Fetch all subscriptions you have access to
3. Iterate through each subscription, collecting network resources
4. Export two files with a timestamp:
   - `network-inventory-YYYYMMDD-HHMMSS.csv`
   - `network-topology-YYYYMMDD-HHMMSS.drawio`

## Importing the Diagram

1. Go to https://app.diagrams.net/
2. File → Import → Select the `.drawio` file
3. The file contains **two pages**:
   - **"Azure Network Topology"** — the visual map
   - **"Legend"** — explains the shapes, colors, and connections
4. Switch between pages using the page tabs at the bottom

**Legend page includes:**
- What each shape means (VNet, Subnet, NIC, Public IP)
- Color coding (subscriptions)
- Connection types
- Quick reference guide

## Example Output

### CSV Columns
| Subscription | ResourceGroup | Type | Name | VNet | Subnet | AddressPrefix | PrivateIP | PublicIP | ... |

### Draw.IO
Visual topology with containers for VNets, nested subnets, and connected resources. Great for documentation, audits, and architecture reviews.

## Future Enhancements

### v1.2 (Planned)
- [ ] Query Azure Resource Graph for faster enumeration (large tenants)
- [ ] Include Load Balancers and Application Gateways (with backend pools, rules)
- [ ] Include Azure Firewall and Route Tables
- [ ] Add Azure Bastion hosts
- [ ] Show VPN Gateways / ExpressRoute circuits

### v1.1 (In Progress)
- [x] Batched queries (single Get-AzNetworkInterface call per subscription) — huge speedup
- [x] Detect orphaned/unused public IPs (cost savings)
- [x] Add NSG names as edge labels on subnet→NIC connections
- [x] Embedded Legend page inside Draw.IO file
- [x] Minimal Az modules (Accounts + Network only)

Later:
- [ ] Export to HTML interactive report
- [ ] Highlight overlapping IP ranges across VNets
- [ ] Support for Private Endpoints and Private DNS Zones
- [ ] Include Application Security Groups (ASGs)
- [ ] Integrate with Azure Policy to show non-compliant resources

## License

MIT License — feel free to modify and share.

## Contributing

Pull requests welcome! Open an issue if you find bugs or have feature requests.

---

**Built for Azure Cloud Engineers, by someone who needed it for work.**
