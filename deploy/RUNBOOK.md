# HoBs Production Deployment Runbook

> Deploy HoBs (self-hosted photo management) on a Raspberry Pi 5 connected to your home WiFi network.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Flash the Pi OS](#2-flash-the-pi-os)
3. [First Boot & SSH Access](#3-first-boot--ssh-access)
4. [Harden the Pi](#4-harden-the-pi)
5. [Install Docker](#5-install-docker)
6. [Set Up the External HDD](#6-set-up-the-external-hdd)
7. [Deploy HoBs](#7-deploy-hobs)
8. [Configure Your Router](#8-configure-your-router)
9. [Verify End-to-End](#9-verify-end-to-end)
10. [Operations & Maintenance](#10-operations--maintenance)
11. [Rollback Procedure](#11-rollback-procedure)
12. [Troubleshooting](#12-troubleshooting)
13. [Future Improvements](#13-future-improvements)

---

## 1. Prerequisites

### Hardware

| Item | Spec | Notes |
|------|------|-------|
| Raspberry Pi 5 | 8GB RAM | Must be the 8GB variant |
| Power supply | Official 27W USB-C | Third-party PSUs cause throttling |
| Case | With active cooling (fan) | Pi 5 runs hot under load |
| SD card | 32GB+, A2 rated | For OS only; data goes on HDD |
| External USB HDD | 4-8TB | Powered (not bus-powered); USB 3.0 |
| Ethernet cable | Cat5e or better | Strongly recommended over WiFi |

### Software (for setup only)

- [Raspberry Pi Imager](https://www.raspberrypi.com/software/)

---

## 2. Flash the Pi OS

1. Insert the SD card into your laptop
2. Open **Raspberry Pi Imager**
3. Select:
   - **Device**: Raspberry Pi 5
   - **OS**: Raspberry Pi OS Lite (64-bit) — no desktop, server only
   - **Storage**: Your SD card
4. Click the **gear icon** (or "Edit Settings") before writing:
   - **Hostname**: `raspberrypi` (or your preference)
   - **Enable SSH**: Yes, with password authentication
   - **Username**: `pi`
   - **Password**: Choose a strong password (write it down)
   - **WiFi**: Configure only if not using Ethernet (Ethernet is preferred)
   - **Locale**: Set your timezone
5. Click **Write** and wait for completion
6. Insert the SD card into the Pi

---

## 3. First Boot & SSH Access

1. Connect the Pi to your router via Ethernet (or it will use the WiFi configured above)
2. Connect power — the Pi will boot
3. Wait ~60 seconds for first boot to complete
4. Find the Pi's IP address (one of these methods):
   ```bash
   # From your laptop — try mDNS first
   ping raspberrypi.local

   # Or check your router's DHCP client list

   # Or scan the network
   nmap -sn 192.168.1.0/24
   ```
5. SSH into the Pi:
   ```bash
   ssh pi@<PI_IP_ADDRESS>
   ```
6. Verify you're in:
   ```bash
   uname -a
   # Should show: aarch64 GNU/Linux
   ```

---

## 4. Harden the Pi

### Update the system

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

SSH back in after reboot.

### Set up SSH key authentication (from your laptop)

```bash
# On your laptop — generate a key if you don't have one
ssh-keygen -t ed25519 -f ~/.ssh/id_pi -C "pi-access"

# Copy it to the Pi
ssh-copy-id -i ~/.ssh/id_pi pi@<PI_IP_ADDRESS>

# Verify key login works
ssh -i ~/.ssh/id_pi pi@<PI_IP_ADDRESS>
```

### Disable password authentication

```bash
# On the Pi
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

> **WARNING**: Ensure key-based login works BEFORE disabling password auth. Otherwise you'll lock yourself out.

### Configure firewall

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh          # Port 22
sudo ufw allow 80/tcp       # HTTP (HoBs web UI)
sudo ufw allow 53/tcp       # DNS (dnsmasq)
sudo ufw allow 53/udp       # DNS (dnsmasq)
sudo ufw enable
sudo ufw status
```

### Enable automatic security updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
# Select "Yes" when prompted
```

---

## 5. Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Add pi user to docker group (avoids needing sudo)
sudo usermod -aG docker pi

# Log out and back in for group change to take effect
exit
```

SSH back in, then verify:

```bash
docker --version
docker compose version
docker run hello-world
```

### Configure Docker log rotation

Prevent logs from filling the SD card:

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
sudo systemctl restart docker
```

---

## 6. Set Up the External HDD

### Identify the drive

```bash
lsblk
# Look for your HDD — likely /dev/sda with a large size (e.g., 4T)
```

### Partition and format (DESTRUCTIVE — erases all data on the drive)

```bash
# Create a single partition
sudo parted /dev/sda --script mklabel gpt mkpart primary ext4 0% 100%

# Format as ext4
sudo mkfs.ext4 -L immich-data /dev/sda1
```

### Create mount point and mount

```bash
sudo mkdir -p /mnt/hdd
sudo mount /dev/sda1 /mnt/hdd

# Verify
df -h /mnt/hdd
```

### Make it permanent (survives reboot)

```bash
# Get the UUID (more reliable than /dev/sda1 which can change)
DISK_UUID=$(sudo blkid -s UUID -o value /dev/sda1)
echo "UUID=${DISK_UUID} /mnt/hdd ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

# Verify fstab is correct
sudo mount -a
```

> The `nofail` option ensures the Pi still boots if the HDD is disconnected.

### Create directory structure

```bash
sudo mkdir -p /mnt/hdd/immich/{data,model-cache,postgres}
sudo chown -R pi:pi /mnt/hdd/immich
```

---

## 7. Deploy HoBs

### Copy deployment files to the Pi (from your laptop)

```bash
scp -i ~/.ssh/id_pi \
  deploy/docker-compose.yml \
  deploy/.env \
  pi@<PI_IP_ADDRESS>:~/
```

### Configure environment variables

SSH into the Pi, then edit `.env`:

```bash
ssh -i ~/.ssh/id_pi pi@<PI_IP_ADDRESS>
nano ~/.env
```

Update these values:

```env
UPLOAD_LOCATION=/data
DB_PASSWORD=<GENERATE_A_STRONG_PASSWORD>
DB_USERNAME=postgres
DB_DATABASE_NAME=immich

# Set this to the Pi's static IP (see Router section below)
PI_LOCAL_IP=192.168.1.100
```

> **IMPORTANT**: Change `DB_PASSWORD` from the default `postgres` to something strong:
> ```bash
> openssl rand -base64 24
> ```

### Pull images and start

```bash
cd ~
docker compose pull
docker compose up -d
```

### Verify all containers are running

```bash
docker compose ps
```

Expected output — all 6 services with status `Up`:

```
NAME                        STATUS
immich-deploy-database-1    Up
immich-deploy-dnsmasq-1     Up
immich-deploy-immich-machine-learning-1  Up
immich-deploy-immich-server-1            Up
immich-deploy-redis-1       Up
immich-deploy-watchtower-1  Up
```

### Verify HoBs is accessible locally on the Pi

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost
# Should return: 200
```

---

## 8. Configure Your Router

Every router is different, but the steps are the same:

### Step 1: Assign a static IP to the Pi

1. Log into your router (usually `http://192.168.1.1` or `http://192.168.0.1`)
2. Find **DHCP Reservation** / **Static Lease** / **Address Reservation**
3. Add an entry:
   - **MAC address**: The Pi's MAC (find it with `ip link show eth0` on the Pi)
   - **IP address**: `192.168.1.100` (or whatever you set as `PI_LOCAL_IP`)
4. Save

### Step 2: Set DNS to the Pi

1. In router settings, find **DHCP Settings** / **LAN Settings**
2. Set **Primary DNS Server** to the Pi's IP (e.g., `192.168.1.100`)
3. **Remove** or leave blank any secondary DNS (see [DNS discussion](#) — secondary DNS can cause intermittent hobs.in failures)
4. Save

### Step 3: Renew DHCP on your devices

Devices pick up the new DNS on their next DHCP renewal. To force it:

- **iPhone/iPad**: Settings > WiFi > tap your network > Renew Lease
- **Android**: Toggle WiFi off and on
- **Mac**: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`
- **Windows**: `ipconfig /flushdns` then reconnect WiFi
- **Linux**: `sudo dhclient -r && sudo dhclient`

Or just wait — leases typically renew within a few hours.

---

## 9. Verify End-to-End

From any device on your WiFi:

### DNS resolution

```bash
nslookup hobs.in
# Should return: 192.168.1.100 (your Pi's IP)

nslookup google.com
# Should resolve normally (upstream DNS working)
```

### Web UI

Open a browser on your phone/laptop and go to:

```
http://hobs.in
```

You should see the HoBs setup screen. Create your admin account.

### Upload test

1. Create an account on first visit
2. Upload a photo from the web UI
3. Verify it appears in the timeline
4. Verify the file exists on the HDD:
   ```bash
   # On the Pi
   ls /mnt/hdd/immich/data/
   ```

### Auto-update pipeline

1. Make a trivial code change on your laptop and push to `main`
2. Wait for GitHub Actions to build (~5 min)
3. Wait for Watchtower to poll (~15 min)
4. Check Watchtower logs on the Pi:
   ```bash
   docker compose logs --tail 20 watchtower
   # Should show "Found new ... image" and "Updated=1"
   ```

---

## 10. Operations & Maintenance

### View logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f immich-server
docker compose logs -f watchtower
docker compose logs -f dnsmasq
```

### Check disk usage

```bash
df -h /mnt/hdd
du -sh /mnt/hdd/immich/*
```

### Check service health

```bash
docker compose ps
# All containers should show "Up" and healthy
```

### Restart a service

```bash
docker compose restart immich-server
```

### Restart everything

```bash
docker compose down && docker compose up -d
```

### Manual image update (if Watchtower is too slow)

```bash
docker compose pull
docker compose up -d
```

### View dnsmasq query logs

```bash
docker compose logs -f dnsmasq
# Shows every DNS query hitting the Pi
```

### SSH access for future maintenance

From your laptop:

```bash
ssh -i ~/.ssh/id_pi pi@192.168.1.100
# or, once DNS is working:
ssh -i ~/.ssh/id_pi pi@hobs.in
```

---

## 11. Rollback Procedure

If a bad update breaks HoBs:

### Identify the previous working image

```bash
# Check Watchtower logs for the previous image digest
docker compose logs watchtower | grep "Found new"
```

### Pin to a specific image version

Edit `docker-compose.yml` and replace `latest` with a specific commit tag:

```yaml
immich-server:
  image: ghcr.io/rajulbabel/immich-server:commit-<SHA>
```

Then:

```bash
docker compose pull immich-server
docker compose up -d immich-server
```

### Stop Watchtower temporarily (prevent it from updating back)

```bash
docker compose stop watchtower
```

Remember to start it again once the issue is resolved:

```bash
docker compose start watchtower
```

---

## 12. Troubleshooting

### HoBs not loading in browser

| Check | Command |
|-------|---------|
| Is the Pi reachable? | `ping 192.168.1.100` |
| Is DNS working? | `nslookup hobs.in 192.168.1.100` |
| Are containers running? | `ssh pi@hobs.in 'docker compose ps'` |
| Server logs? | `ssh pi@hobs.in 'docker compose logs --tail 50 immich-server'` |

### DNS not resolving `hobs.in`

1. Check dnsmasq is running: `docker compose ps dnsmasq`
2. Check dnsmasq logs: `docker compose logs dnsmasq`
3. Verify router DNS is set to the Pi's IP
4. Flush DNS cache on your device (see Section 8, Step 3)

### Database connection errors

```bash
docker compose logs database
# Check for disk space issues
df -h /mnt/hdd
```

### HDD not mounted after reboot

```bash
lsblk                    # Is the drive detected?
sudo mount -a            # Try mounting from fstab
sudo journalctl -b | grep sda   # Check for drive errors
```

### Pi running slow / high temperature

```bash
vcgencmd measure_temp    # Should be under 80C
htop                     # Check CPU/memory usage
```

If overheating, ensure the case fan is working and the Pi has adequate ventilation.

### Watchtower not updating

```bash
docker compose logs --tail 20 watchtower
# Check for "Session done" with "Updated=0"
# If Failed > 0, check registry connectivity:
docker pull ghcr.io/rajulbabel/immich-server:latest
```

---

## 13. Future Improvements

- **Database backups** — Nightly `pg_dump` cron job to a second location (second HDD, Google Drive, or S3 Glacier via rclone)
- **Photo backups** — rsync to a second external HDD or cloud storage for 3-2-1 backup compliance
- **Remote access** — Tailscale or Cloudflare Tunnel to access HoBs from outside the home network
- **HTTPS** — Buy a cheap domain (~$2/year), use Let's Encrypt with DNS-01 challenge via Caddy
- **Monitoring** — Enable the optional Prometheus + Grafana containers for dashboards; add UptimeKuma or a simple healthcheck ping to get alerts if the Pi goes down
- **UPS** — A small USB UPS to survive brief power outages and allow graceful shutdown
- **Swap file** — Add a small swap on the HDD to prevent OOM kills on the 8GB Pi under heavy ML workloads
