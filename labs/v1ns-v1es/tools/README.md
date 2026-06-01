# Tools

Scripts used by the lab environment. These files are automatically downloaded to the attacker machine at boot via the CloudFormation bootstrap — no manual upload needed if deploying fresh.

| File | Used on | Purpose |
|---|---|---|
| `attack.sh` | Attacker (VPC1) | Interactive attack menu — 17 phases, run with `attack` |
| `tools-setup.sh` | All Ubuntu machines | Installs nxc, impacket, evil-winrm via Python venv + symlinks to `/usr/local/bin` |
| `ransom_sim.ps1` | Windows (via SMB drop) | Ransomware behavior simulator — shadow copy deletion, mass file rename, registry persistence, C2 beacon (Phase 17) |
| `wmiexec.py` | Attacker + Ubuntu-1/2 | impacket — WMI remote execution on Windows |
| `psexec.py` | Attacker + Ubuntu-1/2 | impacket — PSExec lateral movement on Windows |
| `secretsdump.py` | Attacker + Ubuntu-1/2 | impacket — SAM/LSA/NTDS credential dump from Windows |
| `smbclient.py` | Attacker + Ubuntu-1/2 | impacket — SMB file operations |

## S3 bucket

These files are also hosted in S3 and referenced by the CloudFormation bootstrap:

```
s3://cf-templates-19r23id7c3eko-us-east-1/lab/
```

If you are adapting this lab for your own environment, upload these files to your own S3 bucket and update the bootstrap references in `trendai-enablement-lab.yaml`.
