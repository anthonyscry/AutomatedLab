# Feature Research

**Domain:** PowerShell Hyper-V Lab Automation Tool (Simplified)
**Researched:** 2026-02-09
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Single-command build** | Users want to type one command and get a working lab | MEDIUM | Core value prop - must work reliably |
| **AD domain creation** | Windows lab without AD is not a "domain lab" | MEDIUM | DC promotion, DNS setup, domain join |
| **VM lifecycle management** | Start, stop, restart VMs is basic expectation | LOW | Simple wrappers around Hyper-V cmdlets |
| **Network configuration** | VMs must communicate with each other | MEDIUM | Internal switch, IP assignment, basic routing |
| **Basic health checks** | Users need to know if lab is working | LOW | Status checks, connectivity tests |
| **ISO detection/validation** | Build fails silently without proper ISOs | LOW | Pre-flight checks before deployment |
| **Clean teardown** | Users need to reset/start over without manual cleanup | MEDIUM | Remove VMs, snapshots, checkpoints |
| **Error reporting** | Silent failures are unacceptable | LOW | Clear messages when things break |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Menu-driven interface** | Non-PowerShell experts can use it | LOW | Interactive menus guide users |
| **Snapshot-based rollback** | One command restores clean state | MEDIUM | LabReady snapshot concept |
| **Non-interactive mode** | Enables automation, CI/CD integration | LOW | Flags for unattended operations |
| **Fast startup workflow** | Devs want to start coding, not managing VMs | LOW | `start` command boots everything |
| **Run artifacts (JSON + text)** | Enables monitoring, audit trails | LOW | Machine-readable run reports |
| **Core-only mode** | Faster builds for Windows-only testing | LOW | Skip Linux VM when not needed |
| **Desktop shortcuts** | One-click access for daily operations | LOW | Creates desktop icons for common tasks |
| **Health gate validation** | Prevents broken lab states | MEDIUM | Post-deploy checks with auto-rollback |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Azure support** | "Hybrid lab sounds cool" | Adds complexity, billing risks, different failure modes | Focus on Hyper-V only |
| **Linux VMs** | "Need to test cross-platform" | Different automation model, slower builds, more failure points | Make optional/add-on (as current LIN1) |
| **Multi-domain forests** | "Enterprise scenarios" | Most users don't need this, adds config burden | Document how to extend |
| **GUI/Windows Forms** | "Easier than CLI" | Maintenance burden, doesn't scale, PowerShell-native is better | CLI with clear output |
| **Custom role system** | "Extensibility seems important" | Most users never use it, adds documentation burden | Simple hooks/extension points |
| **SQL Server role** | "Need database testing" | Heavy resource use, slow install, niche need | Document manual setup |
| **Cluster support** | "High availability testing" | Over-engineering for lab scenarios | Single-host only |
| **Complex network topologies** | "Realistic networking" | Most users want simple VLANs | Single internal switch + NAT |

## Feature Dependencies

```
[Hyper-V Host Detection]
    └──requires──> [ISO Validation]
                       └──requires──> [Lab Build]
                                          └──requires──> [Health Checks]
                                                             └──enables──> [Snapshot Rollback]

[Network Configuration] ──enhances──> [Lab Build]
                                   └──requires──> [VM Creation]

[Menu Interface] ──enhances──> [All Features]

[Non-Interactive Mode] ──enhances──> [Automation/CI]
```

### Dependency Notes

- **Lab Build requires ISO Validation**: Can't build without Windows ISOs in place
- **Health Checks enable Snapshot Rollback**: Only rollback to known-good states if you've verified they work
- **Network Configuration enhances Lab Build**: Required for VMs to communicate, but basic lab can work with defaults
- **Menu Interface enhances all features**: Makes tool accessible but doesn't change underlying functionality
- **Non-Interactive Mode enhances Automation**: Enables scripting and CI/CD integration

## MVP Definition

### Launch With (v1)

Minimum viable product - what's needed to validate the concept.

- [ ] **One-command build** - Core value prop; must work reliably
- [ ] **AD domain creation** - DC1 + DNS + domain join for client VMs
- [ ] **VM lifecycle** - Start, stop, status checks
- [ ] **Basic network** - Internal switch + IP assignment
- [ ] **ISO pre-flight** - Validate ISOs before attempting build
- [ ] **Clean teardown** - Remove lab artifacts without leaving junk
- [ ] **Error messages** - Clear output when things fail
- [ ] **Status command** - Show VM states, basic health

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] **Snapshot/rollback** - Trigger for: users breaking labs and wanting quick reset
- [ ] **Menu interface** - Trigger for: non-PowerShell users needing easier interaction
- [ ] **Non-interactive flags** - Trigger for: automation requests, CI/CD use cases
- [ ] **Health gate** - Trigger for: deploy issues, broken lab states
- [ ] **Run artifacts** - Trigger for: debugging, monitoring needs

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Linux VM support** - Defer: Different automation model, adds complexity
- [ ] **Custom roles/extensions** - Defer: Validate core use case first
- [ ] **Multi-domain scenarios** - Defer: Niche requirement, document manual approach
- [ ] **Azure integration** - Defer: Entirely different platform, doubles surface area
- [ ] **Advanced networking** - Defer: Most users happy with simple switch

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| One-command build | HIGH | MEDIUM | P1 |
| AD domain creation | HIGH | MEDIUM | P1 |
| VM lifecycle (start/stop/status) | HIGH | LOW | P1 |
| ISO validation | HIGH | LOW | P1 |
| Clean teardown | HIGH | MEDIUM | P1 |
| Basic networking | HIGH | MEDIUM | P1 |
| Error reporting | HIGH | LOW | P1 |
| Menu interface | MEDIUM | LOW | P2 |
| Snapshot/rollback | HIGH | MEDIUM | P2 |
| Non-interactive mode | MEDIUM | LOW | P2 |
| Health gate validation | MEDIUM | MEDIUM | P2 |
| Run artifacts (JSON/text) | LOW | LOW | P3 |
| Desktop shortcuts | LOW | LOW | P3 |
| Linux VM support | MEDIUM | HIGH | P3 |
| Azure support | LOW | HIGH | P3 |
| Custom role system | LOW | HIGH | P3 |
| Multi-domain forests | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | AutomatedLab | Vagrant + Hyper-V | SimpleLab (Our Approach) |
|---------|--------------|-------------------|--------------------------|
| **Learning curve** | Steep (many roles/options) | Medium (Vagrantfile concepts) | Low (one command) |
| **Windows domain focus** | Yes, with many roles | Via community boxes | Primary use case |
| **Linux support** | Yes (growing) | Yes (native) | Optional/add-on |
| **Azure support** | Yes | Via Azure provider | No (Hyper-V only) |
| **Configuration model** | PowerShell objects | Ruby DSL | Simple config file |
| **Snapshot management** | Basic | Via providers | First-class feature |
| **Health validation** | Basic | Via provisioners | Built-in health gate |
| **Error messages** | Mixed | Depends on provider | Clear, actionable |
| **Teardown** | Manual steps | `vagrant destroy` | One command |
| **Menu interface** | No | No | Yes (differentiator) |
| **Non-interactive** | Yes | Yes | Yes (by design) |

## Sources

### Primary Sources
- [AutomatedLab Official Website](https://automatedlab.org/) - MEDIUM confidence - Official project site
- [AutomatedLab GitHub Repository](https://github.com/AutomatedLab/AutomatedLab) - HIGH confidence - Source code, issues, documentation
- [AutomatedLab Active Directory Role Documentation](https://automatedlab.org/en/latest/Wiki/Roles/activedirectory/) - HIGH confidence - Official role documentation
- [AutomatedLab Hyper-V Documentation](https://automatedlab.org/en/latest/Wiki/Roles/hyperv/) - HIGH confidence - Platform-specific documentation
- [AutomatedLab Tutorial Part 1](https://devblogs.microsoft.com/scripting/automatedlab-tutorial-part-1-introduction-to-automatedlab/) - HIGH confidence - Microsoft official tutorial

### Alternative Tools
- [Vagrant with Hyper-V Provider](https://github.com/erichexter/vagrant-windows-hyperv) - MEDIUM confidence - Community project
- [Eryph Hyper-V Automation](https://www.eryph.io/guides/958273-hyper-v-automation-powershell) - MEDIUM confidence - Alternative approach

### Community Research
- [Getting Started with AutomatedLab](https://sysmansquad.com/2020/06/15/getting-started-with-automatedlab/) - MEDIUM confidence - Community guide
- [Building an Active Directory/Windows Server Lab](https://blog.sonnes.cloud/building-an-active-directory-windows-server-lab/) - LOW confidence - Blog post (verified with official docs)
- [Reddit: Hyper-V Automation Tools Discussion](https://www.reddit.com/r/HyperV/comments/v9cwlv/share_some_of_your_favorite_hyperv_automation/) - LOW confidence - Community discussion

### Industry Standards
- [Windows Active Directory 101: Home Lab Setup](https://yogesh-rathod.medium.com/windows-active-directory-101-a-beginners-guide-and-home-lab-setup-422480157314) - LOW confidence - Medium post (general practices)
- [Building an Effective Active Directory Lab Environment](https://adsecurity.org/?p=2653) - MEDIUM confidence - Security-focused lab guidance

### Issues and Limitations
- [AutomatedLab GitHub Issues](https://github.com/AutomatedLab/AutomatedLab/issues) - HIGH confidence - Real user problems
- [AutomatedLab Troubleshooting](https://theautomatedlab.com/article.html?content=troubleshooting-1) - MEDIUM confidence - Common issues

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **AutomatedLab capabilities** | HIGH | Verified via official docs and source code |
| **Windows lab requirements** | HIGH | Verified via Microsoft and industry sources |
| **User pain points** | MEDIUM | Based on GitHub issues and community discussions |
| **Alternative tools landscape** | MEDIUM | Web search only, limited depth on alternatives |
| **Simplified tool priorities** | MEDIUM | Inferred from current project and user needs |

---
*Feature research for: SimpleLab - PowerShell Hyper-V Lab Automation*
*Researched: 2026-02-09*
