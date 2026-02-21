# Requirements: AutomatedLab

**Defined:** 2026-02-21
**Core Value:** Every function handles errors explicitly, surfaces clear diagnostics, and stays modular enough that each piece can be tested and maintained independently.

## v2 Requirements (Cancelled)

~~The following requirements were planned for v1.8 Cloud Integration & Hybrid Labs but were cancelled when the project was completed at v1.7.~~

### ~~Azure Integration~~

~~- **AZ-01**: Operator can provision Azure VMs alongside Hyper-V VMs in a single lab definition~~
~~- **AZ-02**: Operator can specify Azure credentials and subscription in Lab-Config.ps1~~
~~- **AZ-03**: System validates Azure connectivity before provisioning (pre-flight check)~~
~~- **AZ-04**: Azure VMs appear in Get-LabVM output alongside local VMs~~

### ~~Hybrid Networking~~

~~- **HYB-01**: Operator can configure site-to-site VPN or ExpressRoute connectivity between on-prem and Azure~~
~~- **HYB-02**: Operator can define network rules allowing cross-premise communication~~
~~- **HYB-03**: System validates hybrid network configuration before applying~~
~~- **HYB-04**: VMs in both environments can communicate according to network topology~~

### ~~Cloud Image Management~~

~~- **IMG-01**: Operator can reference Azure Marketplace images in lab definitions~~
~~- **IMG-02**: Operator can specify custom Azure image templates~~
~~- **IMG-03**: System caches Azure image metadata to avoid redundant API calls~~

### ~~Cross-Platform Orchestration~~

~~- **XPL-01**: Common provisioning abstraction works for both Hyper-V and Azure VMs~~
~~- **XPL-02**: Operator can run common operations (start/stop/snapshot) across hybrid VMs~~
~~- **XPL-03**: System handles platform-specific operations transparently~~

## v2+ Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Cloud Features

- **ADV-01**: Multi-cloud support (AWS, GCP alongside Azure)
- **ADV-02**: Cloud-only lab deployments (no local Hyper-V required)
- **ADV-03**: Auto-scaling based on workload demand
- **ADV-04**: Cost optimization and rightsizing recommendations

### Enterprise Scenarios

- **ENT-01**: Multi-forest domain scenarios across regions
- **ENT-02**: Advanced network simulation (packet loss, latency injection)
- **ENT-03**: Disaster recovery and failover automation

## Out of Scope

| Feature | Reason |
|---------|--------|
| Real-time cloud sync | Scheduled sync sufficient for lab scenarios |
| Azure Cost Management | Use Azure Cost Advisor / Portal |
| Complex multi-region topologies | Focus on single-region hybrid first |
| Azure Policy integration | Use Azure Portal for governance |
| Cloud-only GUI redesign | CLI-first approach, GUI will display hybrid data |
| Migrating existing VMs to cloud | Manual export/import sufficient for v1.8 |

## Traceability

All requirements for v1.0-v1.7 have been completed. Requirements planned for v1.8 were cancelled when the project was finalized at v1.7.

**Cancelled Requirements (v1.8 Cloud Integration):**
- AZ-01 through AZ-04 (Azure Integration)
- HYB-01 through HYB-04 (Hybrid Networking)
- IMG-01 through IMG-03 (Cloud Image Management)
- XPL-01 through XPL-03 (Cross-Platform Orchestration)

**Coverage:**
- v1.0-v1.7 requirements: 161 total — **100% complete** ✓
- v1.8 requirements: 14 cancelled — Project complete at v1.7

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-02-21 — Project completed at v1.7*
