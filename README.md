# TrendAI / Trend Vision One Enablement Lab

A self-contained AWS lab for demonstrating TrendAI / Trend Vision One detection and response capabilities. One CloudFormation stack per participant deploys a full attacker/victim environment with automated attack phases.

## Architecture

```
VPC1 (Attacker)                    VPC2 (Protected Estate)
┌─────────────────┐                ┌──────────────────────────────────────────┐
│  Ubuntu          │   VPC Peering  │  Windows Server 2022                     │
│  Attacker Host  │◄──────────────►│  Ubuntu-1 (target)                       │
│  (attack.sh)    │                │  Ubuntu-2 (target + vulhub)              │
└─────────────────┘                │  DDI Appliance (traffic mirror)          │
                                   └──────────────────────────────────────────┘
                                              ↓ VPC Traffic Mirroring
                                   ┌──────────────────────┐
                                   │  Trend Vision One    │
                                   │  (XDR + Network      │
                                   │   Sensor + SWP)      │
                                   └──────────────────────┘
```

## Files

| File | Description |
|---|---|
| `trendai-enablement-lab.yaml` | CloudFormation template — deploy one stack per participant |
| `trendai-enablement-lab-runbook.md` | Facilitator runbook — setup, pre-lab steps, teardown |
| `trendai-attack-playbook.md` | Participant attack playbook — step-by-step attack phases |

## Prerequisites

- AWS account with permissions to create VPCs, EC2, IAM, CloudFormation
- VPC and Elastic IP quotas raised to at least `2 × number of participants`
- Active Trend Micro Deep Discovery Inspector (DDI) subscription in AWS Marketplace
- Trend Vision One tenant with enrollment tokens ready
- S3 bucket to host the template (template exceeds CloudFormation inline size limit)

## S3 Setup

The template references lab scripts stored in S3. Upload these before deploying:

```bash
# Upload the template
aws s3 cp trendai-enablement-lab.yaml s3://<your-bucket>/trendai-enablement-lab.yaml

# The bootstrap downloads attack scripts at instance launch — see bootstrap.sh in the template
```

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
| `AdminCidr` | `127.0.0.1/32` | Your public IP as `/32` — used to reach DDI management console |
| `StandardInstanceType` | `c5.xlarge` | Instance type for Ubuntu/Windows targets (must be Nitro-based for traffic mirroring) |
| `DdiInstanceType` | `m5.2xlarge` | DDI appliance instance type |
| `DdiAmiId` | `ami-09efe0d9de322e018` | DDI AMI ID (us-east-1). Leave blank to deploy without DDI. |

## Pre-Lab Checklist (complete before running attack phases)

1. **Activate DDI license** — log into the DDI console and complete activation
2. **Integrate DDI with Vision One** — generate enrollment token in V1, paste in DDI
3. **Enable Network Sensor** — Vision One > Marketplace > Network Sensor > Enable
4. **Install SWP agents** on Windows, Ubuntu-1, Ubuntu-2 via SSM Session Manager
5. **Configure SWP policies** — enable Anti-Malware, IPS (Prevent), Log Inspection, Integrity Monitoring
6. **Verify** all 3 agents and the Network Sensor show green in Vision One before attacking

## Attack Phases

The attacker host runs `/opt/lab/attack.sh` (aliased as `attack`) — an interactive menu with 17 phases:

| Phase | Technique | DDI / Vision One detection |
|---|---|---|
| 1 | Network Discovery (nmap) | Network sweep |
| 2 | Deep Vulnerability Scan (NSE scripts, Shellshock, Heartbleed) | Exploit probe signatures |
| 3 | SMB Null Session Enumeration | Recon / anomalous auth |
| 4 | Brute Force — SSH, SMB, RDP | Brute force / Event ID 4625 |
| 5 | SMB Auth Exec + SAM/LSA Dump | Lateral movement + credential theft |
| 6 | WMI Exec + Encoded PowerShell | Suspicious WMI + obfuscated PS |
| 7 | PSExec Lateral Movement | PSExec signature |
| 8 | secretsdump (credential harvest) | Credential harvesting |
| 9 | EternalBlue Probe (MS17-010) | Exploit probe |
| 10 | Log4Shell (CVE-2021-44228) | Exploit attempt |
| 11 | East-West Lateral: Ubuntu-2 → Windows | East-West lateral movement |
| 12 | C2 Beacon Simulation | C2 callback pattern |
| 13 | DNS Exfiltration Simulation | DNS tunneling |
| 14 | Anti-Forensics (hosts file + event log clearing) | Integrity Monitoring + Event ID 1102 |
| 15 | Custom Payload Drop (interactive URL input) | AV / behavioral detection |
| 16 | EICAR Anti-Malware Test (all 3 targets) | Anti-Malware alert |
| 17 | Ransomware Behavior Simulator (PowerShell IOCs) | Behavioral Analysis + shadow copy deletion |

## Connect to the Attacker

```bash
# Get the instance ID from stack outputs
aws cloudformation describe-stacks --stack-name <name> \
  --query 'Stacks[0].Outputs[?OutputKey==`AttackerInstanceId`].OutputValue' \
  --output text

# Open SSM session
aws ssm start-session --target <instance-id>

# Run the attack menu
attack
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name <participant-name>
```

## Notes

- All VPC2 machines are intentionally configured with reduced security (firewall off, Defender off, UAC off, WDigest enabled) to maximize attack surface for the lab.
- Traffic mirroring feeds all VPC2 east-west and north-south traffic to the DDI appliance.
- SSH/RDP/SMB on VPC2 are reachable only from VPC1 (10.0.0.0/16) — never from the internet.
- Workload access for setup steps is via SSM Session Manager (no inbound internet rules needed).
