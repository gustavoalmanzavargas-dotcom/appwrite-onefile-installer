# Appwrite One-File Installer (LXC/Proxmox Friendly)

This repository contains a single-file automated installer for Appwrite 1.6.x with Traefik v3 support, Docker API compatibility fixes, and SMTP configuration support.

## 🚀 One-Line Install

Run inside your Ubuntu/Debian LXC container:

```bash
curl -fsSL https://raw.githubusercontent.com/<YOUR-USERNAME>/appwrite-onefile-installer/main/install_appwrite.sh \
  | sudo bash -s -- install \
    --dir /opt/appwrite/appwrite \
    --domain appwrite.ceyeberkeep.com \
    --email-name "CeyeberKeep" \
    --email-address "no-reply@ceyeberkeep.com" \
    --smtp-host mail.ceyeberkeep.com \
    --smtp-port 587 \
    --smtp-secure tls \
    --smtp-username no-reply@ceyeberkeep.com \
    --smtp-password "Billy1992!"
