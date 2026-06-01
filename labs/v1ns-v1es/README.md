# Vision One Enablement Lab — New Starter & Customer Session

A self-contained AWS lab for demonstrating Trend Vision One detection and response capabilities end-to-end. One CloudFormation stack per participant deploys a full attacker/victim environment with automated attack phases across 17 techniques.

---

## Detection Layers

This lab exercises **three complementary Vision One detection layers** that participants should understand before starting. Every VPC2 machine runs both the V1ES/V1SWP agent and the EDR module; DDI + Network Sensor covers the network layer.

### 1. V1ES / V1SWP — Endpoint Security (Server & Workload Protection)

**V1ES (Vision One Endpoint Security)** — also referred to as **V1SWP (Server & Workload Protection)** — is a lightweight security agent installed directly on each workload: Windows Server, Ubuntu-1, and Ubuntu-2.

It is the primary **host-level** prevention and detection engine. Unlike network sensors that inspect traffic passing between machines, V1SWP runs *inside* the OS and has full visibility into what the operating system is doing:

| Capability | What it detects in this lab |
|---|---|
| **Anti-Malware (Real-Time Scan)** | EICAR test file, ransomware simulator payload, suspicious executables dropped via SMB |
| **Behavioral Analysis** | Encoded PowerShell (IEX stager), shadow copy deletion, mass file rename, registry persistence keys |
| **Intrusion Prevention (IPS)** | Exploit attempt patterns — EternalBlue probe, Log4Shell JNDI injection at the process level |
| **Log Inspection** | Windows Event ID 4625 (failed logon from brute force), Event ID 1102 (audit log cleared), Event ID 4688 (process creation) |
| **Integrity Monitoring** | Changes to `C:\Windows\System32\drivers\etc\hosts`, system file modifications |
| **Application Control** | Execution of unauthorized binaries dropped by the attacker |

**How to install (pre-lab):**
Vision One > Endpoint Security > Agent Installer → download the appropriate installer for Windows or Linux → deploy via SSM Session Manager on each target instance.

**Policy to configure before the lab:**
```
Vision One > Endpoint Security > Server & Workload Protection > Policies
  ✓ Anti-Malware            → Real-Time Scan enabled
  ✓ Intrusion Prevention    → Mode: Prevent
  ✓ Log Inspection          → Rules: Windows Events (Security, System, Application)
  ✓ Integrity Monitoring    → Monitor: hosts file, system32, scheduled tasks
  ✓ Behavioral Analysis     → Enabled
```

Set IPS to **Prevent** mode — this creates natural teachable moments during the lab where the agent blocks an attack mid-phase, demonstrating both detection and prevention in action.

---

### 2. EDR — Endpoint Detection and Response

**EDR (Endpoint Detection and Response)** is active on all three VPC2 machines alongside the V1SWP agent. While V1SWP handles prevention (blocking malware, enforcing IPS rules), EDR is the telemetry and investigation layer: it records a continuous stream of process executions, network connections, file operations, and registry changes, and feeds that telemetry into the **Vision One XDR Workbench**.

EDR is what turns individual host events into a correlated attack story. When V1SWP blocks or flags something, EDR supplies the surrounding context — what process spawned it, what it touched, where it connected — so the Workbench can stitch attacker activity across all three hosts into a single incident timeline.

| Capability | What it contributes in this lab |
|---|---|
| **Process telemetry** | Execution chains: wmiexec → cmd.exe → net.exe, PSExec service install → payload |
| **Network telemetry** | Outbound C2 connections, east-west lateral connections from each endpoint's perspective |
| **File telemetry** | Payload drops, EICAR writes, mass file rename (ransomware sim) |
| **Registry telemetry** | Persistence key writes (Run keys, scheduled tasks) |
| **XDR correlation** | Links endpoint-side evidence to DDI network detections in the Workbench incident graph |

**How to enable (pre-lab):**
EDR is enabled at the policy level in Vision One > Endpoint Security > Server & Workload Protection > Policies → **Activity Monitoring** → turn on. This is what populates the XDR Workbench with endpoint telemetry.

> **Key concept for the session:** V1SWP blocks and alerts at the host boundary. EDR records everything the OS does so the Workbench can reconstruct the full attack chain. DDI sees the same activity on the wire. All three feed the same Workbench incident — each layer fills gaps the other two cannot cover alone.

---

### 3. NDR — Network Detection and Response (DDI + Network Sensor)

**Deep Discovery Inspector (DDI)** is a dedicated network appliance deployed in VPC2. It receives a full copy of all VPC2 traffic via **AWS VPC Traffic Mirroring** and inspects it for threats at the packet and protocol level — with no agent required on the endpoints.

**Network Sensor** is the Vision One integration that surfaces DDI detections in the XDR Workbench and correlates them with endpoint telemetry from V1SWP and EDR to build a complete attack timeline. Together, DDI and Network Sensor form the **NDR** layer.

---

### How the Three Layers Complement Each Other

| | V1ES / V1SWP (host prevention) | EDR (host telemetry) | NDR — DDI + Network Sensor |
|---|---|---|---|
| **Installed on** | Each workload (Windows, Ubuntu-1, Ubuntu-2) | Each workload (same agent, separate module) | Dedicated network appliance in VPC2 |
| **Sees** | OS-level events: processes, files, registry, logons | Continuous process/file/network/registry stream | Network traffic: packets, protocols, connections |
| **Catches** | Attacker actions *on* the machine — blocks in real time | Full execution context before and after an event | Attacker actions *between* machines |
| **Example** | PowerShell execution blocked, LSASS access alerted | Process chain: wmiexec → cmd → powershell -enc | Port scan, JNDI injection in HTTP, C2 beacon |
| **Vision One surface** | Endpoint Security > Endpoints | XDR Workbench (telemetry node graph) | Network Security > Network Sensor |
| **XDR correlation** | Yes — prevention events feed workbench | Yes — primary telemetry source for workbench | Yes — contributes network detections to workbench |

---

## Architecture

```
VPC1 (Attacker)                        VPC2 (Protected Estate)
┌───────────────────┐                  ┌────────────────────────────────────────────┐
│                   │                  │                                            │
│  Ubuntu           │                  │  Windows Server 2022  [V1SWP agent]        │
│  Attacker Host    │◄── VPC Peering ─►│  Ubuntu-1             [V1SWP agent]        │
│  (attack.sh       │                  │  Ubuntu-2 + Vulhub    [V1SWP agent]        │
│   17 phases)      │                  │                                            │
│                   │                  │  DDI Appliance ◄── VPC Traffic Mirroring   │
└───────────────────┘                  └────────────────────────────────────────────┘
                                                  │ all VPC2 traffic mirrored
                                                  ▼
                                       ┌────────────────────────────┐
                                       │      Trend Vision One      │
                                       │  ┌────────────────────┐    │
                                       │  │  XDR Workbench     │    │
                                       │  │  (correlated view) │    │
                                       │  └────────────────────┘    │
                                       │  Network Sensor ← DDI      │
                                       │  V1ES / V1SWP   ← agents   │
                                       └────────────────────────────┘
```

---

## Files

| File | Description |
|---|---|
| `trendai-enablement-lab.yaml` | CloudFormation template — deploy one stack per participant |
| `trendai-enablement-lab-runbook.md` | Facilitator runbook — setup, pre-lab steps, facilitation guide |
| `trendai-attack-playbook.md` | Participant attack playbook — step-by-step attack phases |

---

## Prerequisites

- AWS account with permissions to create VPCs, EC2, IAM, CloudFormation
- VPC and Elastic IP quotas raised to at least `2 × number of participants`
- Active Trend Micro Deep Discovery Inspector (DDI) subscription in AWS Marketplace
- Trend Vision One tenant with enrollment tokens ready
- S3 bucket to host the template and lab scripts (template exceeds CloudFormation inline size limit)

---

## S3 Setup

```bash
# Create a bucket if you don't have one
aws s3 mb s3://<your-bucket>

# Upload the CloudFormation template
aws s3 cp trendai-enablement-lab.yaml s3://<your-bucket>/trendai-enablement-lab.yaml
```

The bootstrap embedded in the template automatically downloads attack tools from S3 at instance launch — no manual setup needed on the attacker machine.

---

## Deploy

```bash
aws cloudformation deploy \
  --template-url https://<your-bucket>.s3.amazonaws.com/trendai-enablement-lab.yaml \
  --stack-name <participant-name> \
  --parameter-overrides ParticipantName=<name> \
  --capabilities CAPABILITY_IAM
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `ParticipantName` | *(required)* | Short unique name (e.g. `jdoe`). Used in resource names and tags. |
| `UserName` | `trendai` | Local user created on all VMs |
| `UserPassword` | `Trend@00p$` | Password for the lab user across all machines |
| `AdminCidr` | `127.0.0.1/32` | Your public IP as `/32` — used to reach the DDI management console |
| `StandardInstanceType` | `c5.xlarge` | Instance type for Ubuntu/Windows targets (must be Nitro-based for traffic mirroring) |
| `DdiInstanceType` | `m5.2xlarge` | DDI appliance instance type |
| `DdiAmiId` | `ami-09efe0d9de322e018` | DDI AMI ID (us-east-1). Leave blank to deploy without DDI. |

---

## Pre-Lab Checklist

Complete **all steps** before running any attack phase. Attacks will succeed but go undetected if agents are not installed and policies not active.

### Network Layer (DDI + Network Sensor)

- [ ] **PRE-LAB 01** — Activate DDI license: open `https://<DDI-IP>` → Administration > Product License > Activate
- [ ] **PRE-LAB 02** — Integrate DDI with Vision One: Vision One > Marketplace > Deep Discovery Inspector > Add Existing Product | then in DDI: Administration > Vision One Enrollment > paste token > Enroll
- [ ] **PRE-LAB 03** — Enable Network Sensor: Vision One > Marketplace > Network Sensor > Enable > select the enrolled DDI appliance

### Host Layer (V1ES / V1SWP agents)

- [ ] **PRE-LAB 04** — Install V1SWP agent on **Windows** via SSM: `aws ssm start-session --target <windows-id>` → run the Windows SWP installer from your V1 tenant
- [ ] **PRE-LAB 05** — Install V1SWP agent on **Ubuntu-1** via SSM: `aws ssm start-session --target <ubuntu1-id>` → run the Linux SWP installer
- [ ] **PRE-LAB 06** — Install V1SWP agent on **Ubuntu-2** via SSM: `aws ssm start-session --target <ubuntu2-id>` → run the Linux SWP installer
- [ ] **PRE-LAB 07** — Configure SWP policy: Vision One > Endpoint Security > Server & Workload Protection > Policies → enable Anti-Malware (Real-Time), IPS (**Prevent mode**), Log Inspection, Integrity Monitoring, Behavioral Analysis → assign policy to all 3 endpoints
- [ ] **PRE-LAB 08** — Verify everything is green: Endpoint Security > Endpoints (3 agents **Connected**) | Network Security > Network Sensor (DDI **Active**) → only proceed when all show green

---

## Attack Phases

Connect to the attacker and launch the interactive menu:

```bash
# Get the attacker instance ID from stack outputs
aws cloudformation describe-stacks --stack-name <name> \
  --query 'Stacks[0].Outputs[?OutputKey==`AttackerInstanceId`].OutputValue' \
  --output text

# Open a shell on the attacker via SSM
aws ssm start-session --target <instance-id>

# Launch the attack menu (all 17 phases)
attack
```

| Phase | Technique | V1SWP (host) detects | DDI / Network Sensor detects |
|---|---|---|---|
| 1 | Network Discovery (nmap) | — | Network sweep |
| 2 | Deep Vuln Scan (NSE, Shellshock, Heartbleed) | — | Exploit probe signatures |
| 3 | SMB Null Session Enumeration | Logon events | Anomalous SMB auth |
| 4 | Brute Force — SSH, SMB, RDP | **Event ID 4625** repeated failed logons | Brute force traffic pattern |
| 5 | SMB Auth Exec + SAM/LSA Dump | **Credential access** alert | Lateral movement via SMB |
| 6 | WMI Exec + Encoded PowerShell | **Obfuscated PS / suspicious WMI** | WMI remote execution traffic |
| 7 | PSExec Lateral Movement | **Service install** alert | PSExec network signature |
| 8 | secretsdump (credential harvest) | **LSASS access** alert | Credential harvesting traffic |
| 9 | EternalBlue Probe (MS17-010) | — | SMB exploit probe |
| 10 | Log4Shell (CVE-2021-44228) | **Process spawn from Java** | JNDI injection in HTTP headers |
| 11 | East-West Lateral: Ubuntu-2 → Windows | **Logon events** on Windows | East-West SMB/WMI traffic |
| 12 | C2 Beacon Simulation | **Suspicious outbound** process | C2 callback pattern |
| 13 | DNS Exfiltration Simulation | — | Suspicious DNS volume/pattern |
| 14 | Anti-Forensics (hosts file + event log clear) | **Integrity Monitoring** + Event ID 1102 | — |
| 15 | Custom Payload Drop (interactive URL) | **Anti-Malware / Behavioral Analysis** | Suspicious file transfer via SMB |
| 16 | EICAR Anti-Malware Test (all 3 targets) | **Anti-Malware alert on all 3 hosts** | — |
| 17 | Ransomware Behavior Simulator (PowerShell IOCs) | **Shadow copy deletion, mass file rename, registry persistence, C2** | Outbound C2 connection |

---

## Teardown

```bash
aws cloudformation delete-stack --stack-name <participant-name>
```

---

## Lab Design Notes

- **Machines are intentionally vulnerable.** All VPC2 targets run with Windows Firewall disabled, Defender disabled, UAC off, WDigest enabled, and LSA unprotected. This ensures all 17 attack phases succeed so participants focus on the *detection and response* story rather than troubleshooting connectivity.
- **IPS in Prevent mode creates the best demos.** When the agent blocks an attack mid-phase, it naturally leads to a discussion about the difference between detection-only and prevention — a key Vision One value proposition.
- **Traffic mirroring covers east-west traffic.** DDI sees not just attacker-to-target traffic but also target-to-target (Ubuntu-2 pivoting to Windows in Phase 11).
- **No internet inbound rules.** SSH/RDP/SMB on VPC2 are reachable only from VPC1 (10.0.0.0/16). All pre-lab setup is done via SSM Session Manager.
