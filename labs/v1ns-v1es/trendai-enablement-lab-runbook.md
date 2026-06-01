# TrendAI Enablement Lab - Facilitator & Participant Runbook

Deploy and operate Trend Vision One across endpoint, network, and cloud, then
generate detections and investigate them. One CloudFormation stack per person.

Three detection layers are active on every VPC2 machine: **V1ES/V1SWP** (host
prevention), **EDR** (host telemetry → XDR Workbench), and **NDR** (DDI + Network
Sensor). The lab is designed so all three contribute to the same Workbench incident.

The lab runs two parallel tracks on the same environment:

- **SE track**: deploy the sensors, generate an attack, investigate the correlation.
- **CSM track**: read the same environment as a customer outcome - posture score,
  detection-to-value story, and a health-check checklist.

Everyone does Modules 0-4 together. Modules 5+ split by track and rejoin for the debrief.

---

## Architecture at a glance

| VPC | Hosts | Purpose |
|-----|-------|---------|
| VPC1 (10.0.0.0/16) | 1 Ubuntu | Single endpoint target, public subnet |
| VPC2 (10.1.0.0/16) | Windows, Ubuntu-1, Ubuntu-2, DDI | Multi-surface scenario + traffic mirroring |

- Ubuntu-2 is the **test-runner** (nmap + a benign attack script preloaded).
- The 3 VMs in VPC2 mirror their traffic to the DDI data port via AWS VPC Traffic Mirroring.
- Access is through **SSM Session Manager**. No SSH or RDP ports are open to the internet.
- Egress for agent enrollment: NAT gateway (VPC2) and a public IP (VPC1).

---

## Prerequisites (facilitator, do this days before)

1. **Raise AWS quotas in the lab region** (this is the real blocker for one-stack-per-person):
   - *VPCs per Region*: at least `2 x participants` (default is 5).
   - *EC2-VPC Elastic IPs*: at least `2 x participants` (default is 5).
   - Request both in Service Quotas; approval can take a day or two.
2. **Subscribe to DDI in AWS Marketplace** ("Trend Micro Deep Discovery Inspector"),
   accept the terms, and record the **regional AMI ID**. This is the `DdiAmiId` parameter.
   There is no static ID, and it differs per region and version.
3. **Trend Vision One tenant**: confirm everyone can log in. Pre-create or note:
   - Endpoint / Server & Workload Protection **agent installer + enrollment token**.
   - A **Cloud Accounts** onboarding flow ready (generates its own CloudFormation).
4. **Cost guardrail**: set an AWS Budget alert on the lab account. Each stack is roughly
   4x c5.xlarge + 1x c5.2xlarge + a NAT gateway. Plan to **stop instances overnight** and
   **tear down same day** if it is a single-day session.
5. **Confirm SSM works**: the template attaches an instance profile with
   `AmazonSSMManagedInstanceCore`. Verify your account allows Session Manager.

---

## Per-participant deploy (5 minutes)

Each person deploys the stack with their own `ParticipantName`:

```bash
aws cloudformation create-stack \
  --stack-name trendai-lab-<name> \
  --template-body file://trendai-enablement-lab.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters \
    ParameterKey=ParticipantName,ParameterValue=<name> \
    ParameterKey=DdiAmiId,ParameterValue=<ami-id-from-marketplace> \
    ParameterKey=AdminCidr,ParameterValue=<your-public-ip>/32
```

When the stack reaches `CREATE_COMPLETE`, read the **Outputs** tab for instance IDs,
private IPs, the DDI management IP, and the ready-to-run test-runner command.

---

## Module 0 - Connect (everyone, 5 min)

- Open **AWS Systems Manager > Session Manager**, start a session to each VM by instance ID.
- For Windows RDP, use **Fleet Manager > Remote Desktop** or an SSM port-forward.
- Confirm all five instances appear as **Managed** in Fleet Manager. If one is missing,
  the SSM agent has not checked in yet; wait a minute or check egress.

**Teaching point:** this is how customers reach hardened hosts with no inbound exposure.

---

## Module 1 - Endpoint agents (V1ES/V1SWP + EDR) (everyone, 20 min)

Install the Vision One endpoint / Server & Workload Protection agent on the three
endpoint targets (VPC1 Ubuntu, VPC2 Windows, VPC2 Ubuntu-1). This single agent
delivers both **V1ES/V1SWP** (prevention: anti-malware, IPS, log inspection,
integrity monitoring) and **EDR** (telemetry: continuous process, file, network,
and registry recording that feeds the XDR Workbench).

- In Vision One, copy the deployment script / installer and the enrollment token.
- Paste and run it inside each host's SSM session (Linux) or via Fleet Manager (Windows).
- Watch each host appear in the Vision One endpoint inventory.
- After enrollment, apply a policy with **Activity Monitoring** enabled — this
  activates the EDR module on each host. Without it, the Workbench incident graph
  will have network events from DDI but no host-side execution context.

**Teaching point:** participants run the same enrollment flow a customer would, end to end.
The single agent covers both the prevention layer (V1ES/V1SWP) and the investigation
layer (EDR); the network layer (NDR) is DDI + Network Sensor from Module 2.

---

## Module 2 - DDI network detection (everyone, 15 min)

- The stack already created the DDI appliance, the traffic mirror target, filter, and
  three mirror sessions. Confirm the sessions exist under **VPC > Traffic Mirroring**.
- Open the DDI console at the **DDI management IP** from the Outputs (reachable only from
  your `AdminCidr`). Complete first-boot setup and **register DDI to Vision One**.
- Verify DDI shows the mirrored interfaces as active.

**Note:** on AWS, DDI swaps NIC order - the data port is eth0 and management is eth1.
The template wired this correctly, but call it out so the team understands it.

---

## Module 3 - Cloud posture + CloudTrail (everyone, 15 min)

Use the native Vision One onboarding, not a hand-built template:

- In Vision One go to **Cloud Security > Cloud Accounts > AWS > Add Account**.
- Choose **CloudFormation**, generate the stack, and launch it in the lab account.
  This connects the account and can enable posture checks, agentless vulnerability and
  threat detection, CloudTrail-based detections, and cloud response.
- After it completes, review the account's risk and misconfiguration findings.

**Teaching point:** this is the exact onboarding customers run. Practicing it is the lesson.

---

## Module 4 - Generate detections (everyone, 10 min)

From the **test-runner** (VPC2 Ubuntu-2), run the preloaded script. The Outputs tab gives
you the exact command with the target IPs filled in:

```bash
sudo /opt/lab/run-attacks.sh <windows-private-ip> <ubuntu1-private-ip>
```

It does three safe things: writes the benign **EICAR** AV test string, attempts an EICAR
download, and runs an **nmap** scan against the other VPC2 hosts. All of this is harmless
and is the standard way to light up AV and network detection.

Wait a few minutes, then move to your track.

---

## Module 5A - SE track: investigate (25 min)

- Open the **Vision One Workbench** and find the correlated incident.
- Trace the story across all three layers: endpoint AV hit (EICAR, V1ES/V1SWP) +
  host execution telemetry (EDR: process chain that wrote the file) + network scan
  seen by DDI (NDR), all tied to one host.
- Pivot through the **execution profile / observed attack techniques** — the Workbench
  node graph should show EDR telemetry nodes (process trees) alongside the DDI network
  detection nodes.
- Take one **response action**: isolate the Windows host, then release it.
- Bonus: write the two-sentence "what happened and what we did" summary an SE would
  hand a customer.

**Success when:** you can show a single incident that fuses all three layers —
V1ES/V1SWP prevention events, EDR host telemetry, and DDI network detections —
and you have isolated and released a host.

---

## Module 5B - CSM track: outcome & health-check (25 min)

- Open the cloud **posture / risk score** from Module 3 and note the top findings.
- Translate one detection into a customer outcome: what risk it represents, what the
  customer should do, what the renewal/expansion angle is.
- Run a mini **health-check**: are all sensors reporting, is coverage complete across the
  five hosts, are there gaps (any host without an agent)?
- Draft a 3-bullet **value recap** suitable for a customer QBR.

**Success when:** you can state coverage status, one prioritized risk, and one outcome
sentence a customer would care about.

---

## Debrief (everyone, 15 min)

- SEs show the correlated incident. CSMs show the value recap.
- Discuss where the deploy flow was rough and how that maps to real customer friction.

---

## Cost & lifecycle

- **Stop, do not terminate, between days:** stop all instances to pause compute cost.
  Note the NAT gateway and Elastic IPs still bill while allocated.
- **Tear down at the end:**

  ```bash
  aws cloudformation delete-stack --stack-name trendai-lab-<name>
  ```

  Confirm each participant's stack is deleted so VPC and Elastic IP quota is released.
- **Marketplace:** DDI usage bills per the Marketplace listing while the appliance runs.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|--------|--------------|-----|
| Stack fails at VPC or EIP creation | Quota hit | Raise VPC / Elastic IP quotas, then retry |
| Instance not in Fleet Manager | SSM agent not checked in | Wait, or verify NAT/public egress and the instance profile |
| DDI console unreachable | `AdminCidr` wrong | Update the stack with your current public IP /32 |
| No DDI detections | Mirror session or registration | Confirm 3 mirror sessions exist and DDI is registered to Vision One |
| Agent will not enroll | Token or egress | Re-copy the enrollment token; confirm the host can reach the internet |

---

## What the template does and does not do

- **Does:** all networking, the five hosts, SSM access, DDI wiring, traffic mirroring,
  and the benign attack tooling.
- **Does not:** install the Vision One agents or onboard the cloud account. Those are
  done live in Modules 1 and 3 on purpose, because doing them by hand is the enablement.
