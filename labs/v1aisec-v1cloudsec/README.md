# Vision One AI Security & Cloud Security Lab

A self-contained AWS lab for demonstrating Trend Vision One protection across the
full AI application stack. One CloudFormation stack per participant deploys a live
AI chatbot (Ollama LLM + demo web app) and exercises five Vision One controls
across runtime, scanning, container, and code layers.

The existing demo app ([`demo-v1-app-sec-file-sec`](https://github.com/andrefernandes86/demo-v1-app-sec-file-sec))
ships with **V1 AI Guard** and **V1 File Security** already wired in. This lab adds
**AI Scanner**, **Container Security**, and **Code Security** around it.

---

## Detection Layers

This lab exercises **five Vision One controls** across three categories.
Every participant sees all five active against the same running application.

---

### Category 1 — AI Security

#### 1a. V1 AI Guard — Runtime Prompt Protection

**AI Guard** wraps every message sent to and received from the Ollama LLM.
It inspects the prompt before it reaches the model and the model's response
before it reaches the user, blocking or flagging policy violations in real time.

| Capability | What it catches in this lab |
|---|---|
| **Prompt injection detection** | All 7 built-in injection vectors in the demo app UI |
| **Jailbreak / role manipulation** | DAN-style bypasses, XML tag escapes, instruction overrides |
| **Insecure output filtering** | Model responses containing malicious code, credential leakage |
| **Multi-language bypass** | Foreign-language evasion attempts |
| **Enforcement side** | Configurable: user, assistant, or both |

**Configured at:** Vision One > AI Security > AI Guard  
**API endpoint:** `https://api.xdr.trendmicro.com/beta/aiSecurity/guard`

---

#### 1b. V1 AI Scanner — Proactive LLM Vulnerability Assessment

**AI Scanner** probes the LLM endpoint directly — without going through the app —
to assess what the raw model will do when AI Guard is bypassed or not present.
It maps findings to the OWASP LLM Top 10.

| Phase | OWASP LLM | What the scanner tests |
|---|---|---|
| Prompt injection probes | LLM01 | 7 injection payloads sent directly to Ollama API |
| Model extraction | LLM10 | Probes the model for training data / architecture disclosure |
| Insecure output | LLM02 | Asks the model to generate malicious code (exfil scripts) |
| DoS via large context | LLM04 | Floods the context window to test resource exhaustion |
| Sensitive data in context | LLM06 | Checks if the model echoes back secrets embedded in the prompt |

**How to run:** `ai-scan` (preinstalled on the EC2 instance) or `ai-scan --full`  
**Scan reports:** saved to `/opt/lab/scan-reports/` on the instance

> **Key teaching moment:** AI Scanner shows what an attacker sees when they hit the
> raw LLM endpoint. AI Guard shows what a user sees when the same attacks go through
> the protected app. Running both back-to-back makes the protection value concrete.

---

### Category 2 — File Security

#### 2. V1 File Security (V1FS) — Upload Scanning

**File Security** scans every file uploaded through the demo app before it is
processed, using the Trend Micro threat intelligence backend.

| Test | What fires |
|---|---|
| EICAR test file upload | Anti-malware detection — file blocked |
| Hello World (benign) | Clean scan — baseline pass |
| Custom malicious file | Detection based on hash / content signature |

**Configured at:** Vision One > File Security  
**Toggle in app UI:** Settings > File Security Enabled

---

### Category 3 — Application & Cloud Security

#### 3a. Container Security — Runtime Container Protection

**Container Security** monitors the running Docker containers on the lab instance
for suspicious runtime behavior: privilege escalation attempts, unexpected process
execution, reverse shell connections, IMDS credential theft, and sensitive file reads.

| Attack phase | What Container Security detects |
|---|---|
| Privileged escalation attempt | Container escape via host filesystem |
| Malicious script drop + exec | Unexpected binary execution in `/tmp` |
| IMDS credential theft (T1552.005) | Outbound request to `169.254.169.254` |
| Internal network scan | Unexpected network recon from container process |
| Reverse shell | Anomalous outbound TCP to non-standard port |
| Sensitive file read | `/etc/shadow`, `/proc/1/environ` access |

**How to enroll:** `cs-enroll <token>` (token from Vision One > Container Security > Clusters > Add > Standalone)  
**Attack simulation:** `cs-attack` (preinstalled on the EC2 instance)  
**Monitor in:** Vision One > Container Security > Runtime Events

---

#### 3b. Code Security — Source Code & Dependency Scanning

**Code Security** connects to the GitHub repository of the demo app and scans for
hardcoded secrets, vulnerable dependencies, and IaC misconfigurations. It runs
on every push and pull request via a GitHub App integration.

| What it scans | Examples in this lab's repo |
|---|---|
| **Secrets / hardcoded credentials** | API keys in `.env.example`, config files |
| **Vulnerable dependencies** | `requirements.txt` — Python package CVEs |
| **IaC misconfigurations** | `docker-compose.yml` — privileged flags, exposed ports |
| **SAST (static analysis)** | `app.py` — injection sinks, unsafe deserialization |

**How to connect:** Vision One > Code Security > Repositories > Add Repository > GitHub  
**Scan results:** Code Security > Findings — grouped by severity and file

---

### How the Five Controls Work Together

```
 Developer pushes code
        │
        ▼
 ┌──────────────────┐
 │  Code Security   │  ← scans repo: secrets, CVEs, IaC misconfig
 └──────────────────┘
        │ deploys
        ▼
 ┌──────────────────────────────────────────────┐
 │            Docker Container (EC2)            │
 │                                              │
 │  ┌─────────────────────────────────────┐     │
 │  │     Demo App (FastAPI + Ollama)     │     │
 │  │                                     │     │
 │  │  User msg → [AI Guard] → Ollama     │  ◄──┼── Container Security
 │  │  Ollama resp → [AI Guard] → User    │     │   (runtime events)
 │  │  File upload → [V1FS] → result      │     │
 │  └─────────────────────────────────────┘     │
 └──────────────────────────────────────────────┘
        │
        ▼
 ┌──────────────────┐
 │   AI Scanner     │  ← probes raw Ollama API directly (bypasses app)
 └──────────────────┘
```

| Control | Layer | When it runs |
|---|---|---|
| **Code Security** | Source / build | On every git push / PR |
| **Container Security** | Container runtime | Continuously while containers are running |
| **AI Guard** | Application runtime | On every chat message (both directions) |
| **File Security** | Application runtime | On every file upload |
| **AI Scanner** | Proactive assessment | On-demand (facilitator-driven during the lab) |

---

## Architecture

```
GitHub repo (demo-v1-app-sec-file-sec)
        │ push / PR
        ▼
┌───────────────────────────────────────┐
│  GitHub Actions                       │
│  trendmicro/tmas-scan-action@v2       │  ← Code Security scan
│  (secrets, CVEs, malware)             │
└───────────────────────────────────────┘
        │ findings
        ▼
AWS — single VPC, 2 AZs
┌──────────────────────────────────────────────────────────────┐
│  EKS Cluster (trendai-aisec-<name>)                          │
│                                                              │
│  namespace: trendmicro-system                                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Container Security (Helm)                           │   │
│  │  • Admission controller (policy at deploy time)      │   │
│  │  • Runtime sensor DaemonSet (Falco-based)            │   │
│  │  • Oversight controller (continuous compliance)      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  namespace: trendai-lab                                      │
│  ┌──────────────┐    ┌─────────────────────────────────┐    │
│  │  ollama pod  │◄───│  trendai-app pod                 │    │
│  │  :11434      │    │  (FastAPI + AI Guard + V1FS)     │    │
│  └──────────────┘    │  :8000  ← NLB LoadBalancer       │    │
│       ▲ PVC          └─────────────────────────────────┘    │
│  (model storage)                                             │
│                                                              │
│  Bootstrap EC2 (t3.small, SSM only)                          │
│  • kubectl + helm pre-configured                             │
│  • ai-scan, cs-attack scripts                                │
└──────────────────────────────────────────────────────────────┘
        │ outbound HTTPS
        ▼
┌───────────────────────────────┐
│      Trend Vision One         │
│  AI Guard   ←── chat msgs     │
│  File Sec   ←── uploads       │
│  Container  ←── runtime evts  │
│  Code Sec   ←── GitHub push   │
└───────────────────────────────┘
```

---

## Files

| File | Description |
|---|---|
| `trendai-aisec-lab.yaml` | CloudFormation template — EKS cluster + bootstrap EC2, one stack per participant |
| `trendai-aisec-lab-runbook.md` | Facilitator runbook — setup, modules, facilitation guide |
| `trendai-aisec-attack-playbook.md` | Attack playbook — step-by-step test cases for all 5 controls |
| `k8s/namespace.yaml` | Kubernetes namespace manifest |
| `k8s/ollama.yaml` | Ollama Deployment, Service, PVC, and model-pull Job |
| `k8s/app.yaml` | Demo app Deployment, ConfigMap, Secret, and NLB LoadBalancer Service |
| `k8s/container-security-overrides.yaml` | Helm values template for Vision One Container Security |
| `github-actions/v1-code-security.yml` | GitHub Actions workflow template — add to your demo repo fork |

---

## Prerequisites

- AWS account with EC2, VPC, IAM, CloudFormation permissions
- VPC and Elastic IP quotas: at least `1 × participants` in target region
- Active Trend Vision One tenant with:
  - **AI Security** module enabled (for AI Guard and AI Scanner)
  - **File Security** module enabled
  - **Container Security** module enabled
  - **Code Security** module enabled (GitHub App installed on the demo repo)
  - API key with scopes: AI Security, File Security, Container Security

---

## Deploy

```bash
aws cloudformation deploy \
  --template-file trendai-aisec-lab.yaml \
  --stack-name trendai-aisec-<name> \
  --parameter-overrides \
    ParticipantName=<name> \
    V1ApiKey=<your-v1-api-key> \
    V1Region=us-east-1 \
    ContainerSecurityToken=<bootstrap-token-from-v1-portal> \
  --capabilities CAPABILITY_IAM
```

**Timing:** allow ~20 minutes from deploy to app ready (EKS takes ~15 min to provision).

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `ParticipantName` | *(required)* | Short unique name (e.g. `jdoe`) |
| `AdminCidr` | `127.0.0.1/32` | Your public IP as `/32` — allows access to the app UI and Ollama port |
| `V1ApiKey` | *(required)* | Vision One API key (AI Security + File Security scopes) |
| `V1Region` | `us-east-1` | V1FS region |
| `V1GuardUrlBase` | *(us endpoint)* | AI Guard API URL — change for non-US tenants |
| `OllamaModel` | `llama3.2:3b` | LLM model to pull. `llama3.2:3b` is the default and gives the best prompt injection demo responses; `tinyllama` starts faster if bandwidth is limited |
| `InstanceType` | `c5.2xlarge` | EC2 instance type — minimum c5.2xlarge for Ollama |
| `KeyPairName` | *(blank)* | Optional SSH key pair. Leave blank to use SSM only |

---

## Pre-Lab Checklist

- [ ] **PRE-LAB 01** — Stack deployed and `CREATE_COMPLETE`
- [ ] **PRE-LAB 02** — App UI reachable at `http://<PublicIp>:8000`
- [ ] **PRE-LAB 03** — AI Guard responding: send a test message in the app, confirm the guard status appears in the response
- [ ] **PRE-LAB 04** — File Security working: upload the EICAR test from the app UI, confirm detection
- [ ] **PRE-LAB 05** — Container Security enrolled: run `cs-enroll <token>` via SSM, confirm the cluster appears in Vision One
- [ ] **PRE-LAB 06** — Code Security connected: Vision One > Code Security > Repositories > add the demo repo, confirm initial scan completes
- [ ] **PRE-LAB 07** — AI Scanner working: run `ai-scan` via SSM, confirm probes complete and report is written

---

## Teardown

```bash
aws cloudformation delete-stack --stack-name trendai-aisec-<name>
```
