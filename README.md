# Trend Vision One — Enablement Materials

This repository contains hands-on lab materials designed to support two audiences:

- **New hires and SEs** getting up to speed with Trend Vision One capabilities
- **Customer enablement sessions** — structured labs that demonstrate real attack scenarios and how Vision One detects and responds to them

## Labs

| Folder | Lab | Description |
|---|---|---|
| [`labs/v1ns-v1es`](labs/v1ns-v1es/) | Vision One New Starter / Enablement Session | Full attacker-victim lab on AWS. 17 automated attack phases covering recon, lateral movement, credential theft, exploits, ransomware simulation, and exfiltration — all detected by Vision One XDR, DDI Network Sensor, Server & Workload Protection, and EDR. Three detection layers: V1ES/V1SWP, EDR, and NDR. |
| [`labs/v1aisec-v1cloudsec`](labs/v1aisec-v1cloudsec/) | Vision One AI Security & Cloud Security | Live AI chatbot (Ollama LLM + demo web app) on AWS. Five Vision One controls exercised simultaneously: AI Guard (prompt injection blocking), AI Scanner (OWASP LLM Top 10 probes), File Security (upload scanning), Container Security (runtime container attacks), and Code Security (repo scanning). |

## How to use

Each lab folder contains:
- A **CloudFormation template** to deploy the environment on AWS
- A **facilitator runbook** with pre-lab setup steps and facilitation guidance
- A **participant attack playbook** with step-by-step attack instructions

More labs will be added over time covering additional Vision One modules and use cases.
