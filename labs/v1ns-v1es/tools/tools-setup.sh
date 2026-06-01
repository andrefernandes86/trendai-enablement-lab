#!/bin/bash
# Install attack tools — runs on any Ubuntu machine in the lab
exec >> /var/log/lab-tools.log 2>&1
echo "=== Tools setup started $(date) ==="
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

apt-get install -y python3-venv sshpass -q

python3 -m venv /opt/lab/venv

/opt/lab/venv/bin/pip install -q impacket
/opt/lab/venv/bin/pip install -q git+https://github.com/Pennyw0rth/NetExec.git || true

# Symlink venv scripts to /usr/local/bin
for s in /opt/lab/venv/bin/nxc \
         /opt/lab/venv/bin/wmiexec.py \
         /opt/lab/venv/bin/psexec.py \
         /opt/lab/venv/bin/secretsdump.py \
         /opt/lab/venv/bin/smbclient.py; do
  [ -f "$s" ] && ln -sf "$s" /usr/local/bin/$(basename "$s") && echo "linked $(basename $s)"
done

# If venv install of nxc failed, fall back to S3 scripts with impacket from venv
AWS_BIN=$(command -v aws || echo /usr/local/bin/aws)
if ! command -v nxc &>/dev/null; then
  echo "nxc venv install failed, skipping"
fi

# Verify
echo "--- Tool check ---"
for t in nxc wmiexec.py psexec.py secretsdump.py smbclient.py; do
  command -v "$t" &>/dev/null && echo "OK $t" || echo "MISSING $t"
done
echo "=== Tools setup complete $(date) ==="
