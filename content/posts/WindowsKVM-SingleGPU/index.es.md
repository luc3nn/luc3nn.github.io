---
title: "Windows 11 en KVM con Single GPU Passthrough"
featureimage: "img/portada.jpg"
showHero: true
heroStyle: "basic"   #
date: 2025-07-13T01:00:00+02:00
draft: false
description: "Guía completa para configurar una máquina virtual de Windows 11 en KVM/QEMU con Single GPU Passthrough, CPU Pinning y Hugepages en Arch Linux."
tags: [
  "kvm",
  "qemu",
  "gpu-passthrough",
  "vfio",
  "arch-linux",
  "windows11",
  "gaming",
  "virtualizacion",
  "cpu-pinning",
  "hugepages"
]
categories: ["Virtualización", "Linux", "Gaming"]
showTableOfContents: true
---

Después del boom de la inteligencia artificial, todas las empresas (incluidas **microchoft**) han decidido implementar IA en todo lo que pueden. Esto se traduce en Windows11 con funciones como **RECALL**, **COPILOT**, **ESTE MISMO EN** **Bing**, **Office**, **Fotos**, etc.
Un montón de servicios y procesos corriendo en segundo plano que son los culpables que niños de 15 años me ganen en Valorant, por lo que cansado de tener que **reinstalar** Windows11 cada 4-6 meses para que no se atragante con su propia mierda, decidí pasarme a **Linux**, lose que novedad. La cosa es que el gaming en Linux no es una experiencia tan fluida como en windows11, no me malinterpreteís ha avanzado mucho, pero necesitaba una excusa para hacer esta máquina virtual y sinceramente cuando me siento a jugar no tengo ganas de a media partida ponerme a ver cual ha sido la razón por la que arch (en realidad wayland) ha decidido cerrar mi juego y básicamente porque en Windows11 los juegos tienen mas FPS.

Bueno, una vez ya he expuesto mi excusa para hacer este proyecto, hablaré a groso modo de los objetivos a cumplir en este pequeño proyecto y algunos benchmarks.

Lo que diferencia esta máquina virtual de cualquier otra como Virtual box o VMWare (las mas usadas para usuarios finales), es que estas necesitan virtualizar todo de nuevo, mas adelante me explayo más, la cosa es que este es el rendimiento que conseguimos:


El rendimiento bare metal:
![](<img/Pasted image 20260929222656.png>)

El rendimiento en VM:
![](<img/Pasted image 20260929222730.png>)
Junto a algunos higlights
![](<img/PHOTO-2026-10-09-01-18-32.jpg>)
## REQUISITOS

- Drivers para juegos instalados (drivers propietarios de nvidia o amd)
- sistema actualizado
## Instalación de KVM

Primero vamos a empezar instalando KVM/qemu este nos permitirá convertir nuestro sistema operativo en un en un virtualizador de tipo 1 (como Proxmox o VMware ESXi). Esto hace que a diferencia de VMware o VirtualBox (virtualizadores de segundo nivel), no tener que virtualizar nuestro hardware por encima del sistema operativo sino que lo hacemos directamente, haciendo que tengamos mejor rendimiento y como hemos visto anteriormente casi como si no estuvieramos virtualizando.

### Revisando Soporte para KVM
#### Soporte para virtualización

Primero revisaremos si tenemos la virtualización en la bios activada

```bash
lscpu | grep -i Virtualization
# tambien podemos utilizar el siguiente comando
cat /proc/cpuinfo | grep -E "vmx|svm|0xc0f" # Son lo mismo
```

![](<img/Pasted image 20251130211933.png>)
![](<img/Pasted image 20251130212736.png>)
`VT-x` es para Intel y `AMD-Vi` es para AMD (duh), en el caso de que no nos aparezca nada, quiere decir que la virtualización no esta activada por lo que deberemos entrar en la bios y activarla.
#### Soporte del kernel
Ahora debemos verificar que nuestro kernel tiene los módulos de KVM y que dichos módulos se cargan automáticamente, para ello:
```bash
zgrep CONFIG_KVM /proc/config.gz
```

![](<img/Pasted image 20251130213608.png>)

Cuando el output nos muestra `y` este quiere decir que el modulo viene cargado con el kernel, cuando muestra `m` quiere decir que el modulo no esta cargado pero puede ser cargado (que también es parte del kernel) y, por ultimo si nos aparece `n` o esta vacío, esto quiere decir que nuestro kernel no tiene soporte para este modulo, en ese caso podríamos re-compilar el kernel con soporte para KVM o instalar un kernel que ya lo incluya (lo mas sencillo).

Ahora para asegurarnos que los modulos se cargan automaticamente ejecutamos el siguiente comando:

```bash
lsmod | grep kvm
```

![](<img/Pasted image 20251130214105.png>)

Si en el output no nos aparece nada, podemos probar a cargarlos manualmente con `modprobe`, en este caso deberíamos cargar `kvm` y `kvm_intel` o `kvm_amd` .
- Para que los módulos del kernel carguen automáticamente debemos crear un archivo de configuración con los módulos a cargar:

```bash
sudo nano /etc/modules-load.d/kvm.conf
# Dentro de nano 
kvm
kvm_intel # o kvm_amd
```

- Guardamos el archivo, reiniciamos el ordenador y [verificamos si los módulos han cargado]().
##### Virtualización anidada

Si queremos poder virtualizar dentro de nuestras maquinas virtuales podemos habilitar la `nested virtualization` o virtualización anidada, para ello podemos hacerlo manualmente des-cargando modulos del kernel y volviendo a cargarlos con argumentos:

```bash
modprobe -r kvm_intel # Des-cargamos el modulo de kvm de itel
modprobe kvm_intel nested=1 # Lo cargamos con el argumento de nested activo
```

También podemos hacer como antes para cargar automáticamente con la virtualización  anidada activada

```bash
sudo nano /etc/modules-load.d/kvm_nested.conf
options kvm_intel nested=1 # options para indicar que le damos un parametro
```

##### SEGURIDAD EXTRA - AMD SEV / INTEL TDX

En la gama de servidores encontramos tecnologías que mejoran la seguridad de las maquinas virtuales. 

A partir de los procesadores EPYC de AMD y XEON de Intel, existen tecnologías como **AMD SEV** e **INTEL TDX**. Estas a grandes rasgos nos permiten cifrar la memoria RAM de la maquina virtual para de esta manera ni el **host** (SO), ni el **hypervisor** (VMware, KVM, etc.), ni el usuario **ROOT** puedan leer esta.

Esto se traduce en que si el sistema anfitrión es comprometido por malware o ciber-criminales, estos no puedan leer la memoria RAM de la máquina virtual, si roban un servidor (bastante difícil) o el hypervisor tenga alguna vulnerabilidad puedan leer, de nuevo, la memoria de la máquina virtual.

Para habilitarlo (por ejemplo AMD SEV) es tan sencillo como hemos hecho anteriormente.
Cargamos con modprobe los módulos al kernel en un archivo de config para q se carguen automáticamente.

```bash
sudo nano /etc/modules-load.d/kvm.conf
options kvm_amd sev=1 # options para decirle q le ponemos un argumento
```

Lo habilitamos en GRUB:

```bash
sudo nano /etc/default/grub
GRUB_CMDLINE_LINUX="... mem_encrypt=on kvm_amd.sev=1"
```

Guardamos, generamos nueva config y reiniciamos

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg # o donde tengamos isntalado grub
sudo reboot
```

### Instalando QEMU, libvirt, viewers y tools.

Una vez nos hemos asegurado que nuestro `CPU` y `kernel` tienen soporte tanto para virtualización como KVM activada vamos a instalar las herramientas necesarias para crear, gestionar y optimizar nuestras máquinas virtuales, como `qemu-full`, `libvirt`, `virt-manager`, entre otras.

```bash
sudo pacman -S qemu-full qemu-img libvirt virt-install virt-manager virt-viewer edk2-ovmf dnsmasq swtpm guestfs-tools libosinfo tuned
```

- `qemu-full` : encargado de la comunicación entre el host y las VMs
- `qemu-img`: para crear y convertir imágenes de disco (como convertir disco de virtualbox a qemu).
- `libvirt`: API y demonio para la gestión de la plataforma de virtualización (para poder administrar kvm).
- `virt-install`& `virt-manager`: Nos permiten creación y administración de máquinas invitadas tanto desde la línea de comandos como mediante una interfaz gráfica.
- `virt-viewer` : para poder acceder a consolas gráficas (se comunica con SPICE para dar video)
- `edk2-ovmf` : Habilitar soporte **UEFI**.
- `dnsmasq` : para dar **DHCP** y **DNS** a las redes **NAT** dentro de **QEMU/KVM**.
- `swtpm`: Emulador TMP.
- `guestfs-tools` : Binario que nos permite comandos avanzados para gestionar las máquinas virtuales.
- `libosinfo` : Es el encargado de autodetectar el sistema operativo para la creacion de la máquina virtual en **Virt Manager**.
- `tuned` : Optimizador del rendimiento del hipervisor ajustandolo a nuestras necesidades.

### Habilitando el demonio de libvirt

Una vez hemos instalado las herramientas necesarias vamos a iniciar el demonio libvirt en modo “modular” ya que el monolitico no es compatible con virtualbox.

```bash
for drv in qemu interface network nodedev nwfilter secret storage; do
    sudo systemctl enable virt${drv}d.service;
    sudo systemctl enable virt${drv}d{,-ro,-admin}.socket;
done
```

![](<img/Pasted image 20251201134606.png>)

### Verificando Virtualización
Verificamos el estado de la virtualización

```bash
sudo virt-host-validate qemu
```

![](<img/Pasted image 20251201135125.png>)

### Habilitamos le IOMMU en con GRUB

```bash
sudo nano /etc/default/grub
...
GRUB_CMDLINE_LINUX="... intel_iommu=on iommu=pt" # o amd_iommu=on para AMD
# Guardamos el archivo y salimos
# Regeneramos el archivo de config de grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot # Reiniciamos
```

### TuneD

Como indiqué anteriormente instalamos tuned para optimizar el sistema para virtualizar, este se encarga de *twekear* parametros como:
- CPU governor ( decide si subir MHz o bajar o si priorizar rendimiento o ahorro de energia)
- I/O scheduler ( En rasgos generales permite reducir latencia, mas eficiencia  y rendimiento.)
- Ajustes de red (puede aumentar el tamaño de buffer TCP)
- Frecuencia de GPU (irrelevante vamos a pasarla a la VM)
- Energía / rendimiento

Primero habilitamos el inicio automático de este y lo activamos ahora.

```shell
sudo systemctl enable --now tuned.service
```

![](<img/Pasted image 20251201165131.png>)

Una vez habilitado modificamos el perfil actual a `virtual-host`.

```shell
tuned-adm active # ver el perfil actual
# Current active profile: balanced
tuned-adm list # listamos los perfiles y nos aparece virtual-host
sudo tuned-adm profile virtual-host # lo cambiamos a virtual-host
tuned-adm active # Verificamos de nuevo el perfil actual
# Current active profile: virtual-host
sudo tuned-adm verify # Verificar si el perfil se ha aplicado correctamente
```

![](<img/Pasted image 20251201165228.png>)
### Libvirt en system mode

Actualmente si verificamos el estado de libvirt encontraremos que esta en modo `sesion`, esto quiere decir que esta en modo usario. En este estado tenemos privilegios muy limitados y no podemos hacer la principal ventaja de esta guia que es `GPU PASSTHROUGH`, por lo que vamos a cambiarlo a modo sistema.

Para ello primero verificamos en que modo estamos:

```bash
sudo virsh uri
# qemu:///session
```

Añadimos nuestro usuario a el grupo libvirt

```bash
sudo usermod -aG libvirt $USER
```

Modificamos nuestro archivo de configuracion de shell para que el default url sea `system`

```bash
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc # o .zshrc
sudo virsh uri

```

![](<img/Pasted image 20251201161353.png>)

### Modificando los permisos de imagenes

Las imagenes de las maquinas virtuales se guardan en `/var/lib/libvirt/images`, este es un directorio que solo root puede acceder, por lo que vamos a modificarlo para que nosotros como usuario normal podamos acceder a este.

Borramos las ACL existentes

```bash
sudo setfacl -R -b /var/lib/libvirt/images/
```

Damos permiso a nuestro usuario

```bash
sudo setfacl -R -m "u:${USER}:rwX" /var/lib/libvirt/images/
```

Otorgamos permiso a archivos futuros:

```bash
sudo setfacl -m "d:u:${USER}:rwx" /var/lib/libvirt/images/
```

### Redes en KVM

Por defecto en KVM las máquinas virtuales se conectan a la red NAT default de este, la cosa es que si queremos poder conectarla a la red y poder conectarnos desde otros pc o algo por el estilo, debemos crear una red *bridge*, en el caso de que no quieras, puedes skipear esto.

En el caso de las redes bridge no funcionan en NICs inhalambricos (wifi), solo en puertos eth, si tienes Wifi, de nuevo skipea esto.

En este caso la guia de Redes en KVM esta basada en `NetworkManager` asi que si usas otro manager de redes, usa ese.

#### Default Network

Para la gente que tenga un NIC de wifi o no quiera sacar a su red las VMs, vamos a configurar un poco mas la red default para aumentar la seguridad. ya que aunque por defecto **KVM** nos genere una red **NAT** y sus respecivas iptables, te voy a enseñar a modificar la red NAT y vamos a setear reglas de **firewall** para mejorar la seguridad.

Para listar las redes virtuales
```bash
sudo virsh net-list --all
```

![](<img/Pasted image 20251201195108.png>)

Para activar una red 

```bash
sudo virsh net-start default
```

![](<img/Pasted image 20251201195156.png>)

Para hacer que auto-inicie

```bash
sudo virsh net-autostart default
```

![](<img/Pasted image 20251201195248.png>)

Dumpear el .xml de la red default

```bash
virsh net-dumpxml default > default.xml
```

![](<img/Pasted image 20251201195832.png>)

Podemos basarnos en este archivo para modificarlo y generar nuevas redes NAT. Vamos a setear el firewall, es el siguiente archivo:

```bash
#!/usr/bin/nft -f

flush ruleset; # limpia todas las posibles reglas que haya para poner una nueva

define qemu_iface = "virbr0"; # actua sobre la interfaz virbr0 (default)

table inet filter { 
	chain input { # que va a nuestro PC host
		type filter hook input priority filter; policy drop; # tira todas las conexiones al pc

		ct state established,related accept; # Pero mantiene las conexiones como por ejemplo cuando envias una traza icmp que te devuelva la respuesta

		iifname "lo" accept comment "allow loopback"; # permite loopback
		iifname $qemu_iface accept comment "allow qemu"; # permite trafico de las vms al host, si no lo quieres quitalo

		tcp dport http accept comment "allow sending http"; # permite web
		tcp dport https accept comment "allow sending https"; # de nuevo
		udp dport 67 udp sport 68 accept comment "allow sending dhcp"; # permite dhcp
		tcp dport ssh accept comment "allow ssh"; # permite ssh

		counter drop; # deshabilita todo el resto.
	}

	chain forward { # salida a internet
		type filter hook forward priority filter; policy drop; # droppea todo

		ct state established,related accept; # pero mantiene las relacionadas

		iifname $qemu_iface accept comment "forward qemu input";
		oifname $qemu_iface accept comment "forward qemu output";
# mantiene trafico entre maquinas virtuales e internet
		counter drop; # el resto lo tira
	}
}

table ip nat { # setea que el trafico sea en ipv4
	chain postrouting {
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr 192.168.122.0/24 masquerade;
	} # todo lo que salga de 192.168.122.0/24 lo hace masquerade (NAT)
}

```

Para poder usar estas reglas de firewall no debemos usar ni UFW ni firewalld ya que entran en conflicto.

#### Bridge Network

Esto es para los que quieran que salga en bridge la maquina virtual. Para ello primero debemos ver el nombre de nuestra interfaz.

```bash
sudo nmcli device status
```

![](<img/Pasted image 20251203155426.png>)

Usando nmcli vamos a crear una interfaz para el bridge

```bash
sudo nmcli connection add type bridge con-name bridge0 ifname bridge0
```

![](<img/Pasted image 20251203155610.png>)

Conectamos la interfaz ethernet (`enp102s0`)  a la nueva interfaz bridge

```bash
sudo nmcli connection add type ethernet slave-type bridge con-name 'Bridge connection 1' ifname enp2s0 master bridge0
```

![](<img/Pasted image 20251203160132.png>)

Ativamos la nueva interfaz, le habilitamos el autoconect (que se auto inicie) & listamos las interfaces.

```bash
sudo nmcli connection up bridge0
sudo nmcli connection modify bridge0 connection.autoconnect-slaves 1
sudo nmcli connection up bridge0
sudo nmcli device status
```

![](<img/Pasted image 20251203160229.png>)

##### Habilitar en virsh (Virtual Machine Manager) la interfaz bridge

Una vez hemos creado la interfaz, vamos a *setearla* en Virtual Machine Manager. Por lo que vamos a crear un archivo `.xml` llamado bridge con el nombre de la red `bridge`, el modo `bridge` y la interfaz `bridge0`

```xml
<network>
    <name>bridge</name>
    <forward mode="bridge" />
    <bridge name="bridge0" />
</network>
```

![](<img/Pasted image 20251203160514.png>)

Añadimos la red en virsh `net-define`, le habilitamos el autostart y ya esta.

![](<img/Pasted image 20251203160733.png>)

## Configurando la maquina virtual de Windows 11

 Para crear la maquina virtual de Windows 11 en este caso es sencillo, simplemente debemos abrir `Virtual Machine Manager`. Una vez abierto entramos en File>Edit > Preferences 

  ![](<img/Pasted image 20251205201841.png>)

Una vez dentro Habilitamos `Enable XML editing` y nos dirigimos a la pestaña `New VM` 

![](<img/Pasted image 20251205203937.png>)

Una vez dentro, vamos a cambiar el storage format de qcow2 a Raw (en el caso de que no tengamos un disco hdd/ssd/nvme al que hacer passthrough), ya que este nos permite tener mas velocidad, entraremos mas en profundidad mas tarde.

![](<img/Pasted image 20251206143830.png>)
Una vez hecho el cambio, debería verse de la siguiente manera:
![](<img/Pasted image 20251206143840.png>)

Una vez hecho, cerramos y hacemos click al icono de `Create a new virtual machine`

![](<img/Pasted image 20251205201851.png>)

Le damos a forward.

![](<img/Pasted image 20251205202758.png>)

Hacemos click en `Browse` para seleccionar nuestra iso, una vez hecho, le damos a `Forward`
![](<img/Pasted image 20251205202916.png>)

Seleccionamos la ram que queramos para la maquina virtual y los nucleos lo podemos dejar en 4, ya que despues lo vamos a modificar.

![](<img/Pasted image 20251205202928.png>)

En este caso seleccionamos el tamañano de disco que queremos que tenga nuestro windows (en este caso he escogido 60g). 

![](<img/Pasted image 20251206143946.png>)

Y una vez en esta ultima pantalla, le ponemos el nombre que queremos a la vm y **SELECCIONAMOS** `Customize configuration before install`. Esto nos permitira seguir configurando la maquina virtual.

![](<img/Pasted image 20251206144001.png>)

Una vez aqui, nos aseguramos que tengamos el chipset en `Q35` y firmware `UEFI`.

![](<img/Pasted image 20251206144019.png>)

Ahora la **CPU**, la cosa es que si lo dejamos como esta y expandimos `Topology`, podemos ver que ha configurado nuestra maquina virtual con 4 `sockets` y cada uno con 1 `core` y 1 `thread`. En este caso quiere decir que **el hipervisor (KVM/QEMU)** nos ha creado 4 cpus por lo que windows piensa que tenemos 4 procesadores de 1 nucleo y 1 hilo. Por lo que vamos a seleccionar `Manually set CPU topology` para configurarlo correctamente.

![](<img/Pasted image 20251206144043.png>)

En este caso para setear los nucleos y procesadores de la maquina virtual correctamente, vamos a fijarnos en el numero que tenemos arriba donde pone `Logical host CPUs:`

![](<img/Pasted image 20251222160522.png>)

En este caso tenemos 20, por lo que quiere decir que en total mi procesador tiene 20 cpus lógicas por lo que si vieramos la topología de nuestro procesador (**lo haremos mas tarde**), seria algo como 10 nucleos y 2 hilos por cada nucleo por lo que en total (2\*10 = 20) tenemos 20 CPUs lógicas o vCPUs. En este caso vamos a darle 16 vCPUs para dejar 4 al host.

Por lo que para ello dejaremos en sockets 1 (que solo tenga un procesador nuestra maquina virtual), le podré 8 nucleos y 2 hilos por cada nucleo. Quedará de la siguiente manera:

![](<img/Pasted image 20251206150746.png>)

Una vez acabado, vamos al apartado de Nuestro disco, en este caso, si entramos, encontramos que es de tipo SATA, este lo vamos a cambiar a VirtIO, ya que obtenemos diferentes ventajas, entre ellas:
- Menor latencia
- Menor uso de CPU (no tiene que emular)
- Arranca mas rápido
- Y mucho mas.

![](<img/Pasted image 20251206185704.png>)

Por lo que despues de enumerar las diferentes ventajas de VirtIO como dirver de nuestro disco, vamos a cambiarlo de SATA a este y adicionalmente vamos a cambiar el cache a `none` (El SO invitado gestiona su propia caché) y Discard mode `unmap` (Cuando archivos se borran, los bloques se liveran). Para ello vamos a hacer los cambios, y se debería ver de la siguiente manera:

![](<img/Pasted image 20251206185726.png>)

Una vez hecho el cambio del driver de disco, necesitamos añadir los drivers para poder detectarlo dentro de windows por lo que para ello nos dirigiremos a `Add Hardware` 

![](<img/Pasted image 20251206185800.png>)

 Dentro seleccionamos en `Device Type` : `CDROM`  y le damos en `Manage` para seleccionar nuestra iso.
 (link para descargar la iso: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/?C=M;O=D)
Una vez seleccionado le damos a `Add` 

![](<img/Pasted image 20251206185856.png>)

Nos dirigimos en Boot Options para seleccionar el orden de arranque de los discos.

![](<img/Pasted image 20251206185913.png>)

Seleccionamos la ISO que acabamos de añadir y lo ponemos como primera opción.

![](<img/Pasted image 20251206185931.png>)

Ahora vamos  a configurar el internet y TMP2.0 y ya estamos.
En este caso, le damos a `NIC :XX:XX:XX`, una vez dentro modificamos de donde vendrá nuestro internet (en este caso haré NAT).

![](<img/Pasted image 20251206190330.png>)

Y en este caso cambiamos el device model de `e1000e` a `virtio`.

![](<img/Pasted image 20251206190345.png>)

Eliminamos este “modulo”, llamado `Tablet` el cual no lo necesitamos.

![](<img/Pasted image 20251206190406.png>)

![](<img/Pasted image 20251222162312.png>)

Una vez eliminado nos dirigimos a `TPM vNone` 

![](<img/Pasted image 20251206190429.png>)

Y modificamos el version a `2.0`  y ya estamos.

![](<img/Pasted image 20251206190435.png>)

Ahora solo hacemos click en el botón de arriba a la izquierda donde pone `Begin Instalation` y ya podemos iniciar con la instalación de Windwos11.

![](<img/Pasted image 20251206190631.png>)

## Instalación de Windows 11

Una vez hemos acabado la configuración de windows 11, simplemente debemos hacer la gran tarea de hacer click a `Siguiente` varias veces, esto hasta llegar al apartado del disco.

![](<img/Pasted image 20251206190734.png>)

Una vez en el apartado del disco, notamos que no nos aparece ningún disco, esto se debe ya que windows no es capaz de detectar el tipo de disco que tenemos, por lo que vamos a instalar el driver de virtio, para poder detectar el disco e instalar el SO, por lo que para ello, le damos a `Cargar Controlador`.

![](<img/Pasted image 20251206190815.png>)

Una vez dentro, Vamos a seleccionar el disco `virtio-win-X.X.XXX` Dentro de este haremos click en `amd64`>`w11` y le damos a `aceptar`. 

![](<img/Pasted image 20251206223932.png>)

Instalamos el driver y ahora nos aparecerá el disco. Ya podemos seguir con el proceso de instalación normal hasta llegar al apartado de crear una cuenta online.

![](<img/Pasted image 20251206223954.png>)

![](<img/Pasted image 20251206224014.png>)
Procedemos como siempre. 
![](<img/Pasted image 20251206224512.png>)

Ahora estamos en el apartado de crear una cuenta online o conectarla con una ya existente, por lo que si queremos, simplemente instalamos el driver como hemos hecho antes, pero en este caso vamos a bypasear la cuenta online. Para ello hacemos click a las teclas `SHIFT + F10`. Este nos abrira un cmd.

![](<img/Pasted image 20251206224551.png>)

Dentro de este CMD ejecutaremos el siguiente comando `oobe\BypassNRO.cmd` (en mi caso solo escribo bypa y hago `TAB` ). Pulsamos Enter para ejecutarlo.

![](<img/Pasted image 20251206224620.png>)

Despues de esto se nos va a reiniciar el ordenador y volvemos a hacer el setup de nuevo, como si nada. Hasta llegar al apartado de `Vamos a conectarte a una red` .

![](<img/Pasted image 20251206224633.png>)

Una vez aqui, vemos que tenemos opción de seleccionar la opción `No tengo internet`.

![](<img/Pasted image 20251206224654.png>)

Despues de esto nos va a dejar crear una cuenta ofline.

![](<img/Pasted image 20251206224715.png>)
Acabamos de configurar los ultimos pasos.
![](<img/Pasted image 20251206224751.png>)

Y ya estamos dentro de nuestra maquina virtual. Ahora solo nos queda instalar drivers, GPU passthrough, CPU pinning y por ultimo Paginación de memoria (casi nada). por lo que para instalar los drivers, simplemente entramos en el explorador de archivos y entramos dentro de la unidad de virtio drivers

![](<img/Pasted image 20251206225031.png>)

Dentro de la raiz del disco, ejecutamos las guest tools.

![](<img/Pasted image 20251206225058.png>)

 Hacemos click a siguiente e instalar.

![](<img/Pasted image 20251206225133.png>)

Una vez instalado le damos a close y ya podemos cerrar todo eso.

![](<img/Pasted image 20251206225219.png>)

Ahora para poder agilizar nuestro windows 11, vamos a ejecutar powershell como administrador.

![](<img/Pasted image 20251206225250.png>)

Una vez dentro, vamos a ejecutar el siguiente comando `irm christitus.com/win | iex`.
Este es un script que nos permite tanto instalar como desinstalar aplicaciones del sistema, en este caso lo utilizo para poder instalar firefox sin tener que entrar en edge y `aceptar los terminos y condiciones`.

![](<img/Pasted image 20251206225351.png>)

Una vez dentro, selecciono Firefox y le doy a `Install/Upgrade Applications`. En este caso aparte de firefox tambien instalará `winget` que es como un gestor de paquetes en terminal para windows. Algo asi como `apt`.

![](<img/Pasted image 20251206225422.png>)

Una vez haya terminado de instalarse, veremos que nos aparece firefox en nuestro escritorio. Aún dentro del script vamos al apartado `Tweaks`.

![](<img/Pasted image 20251206230606.png>)

Dentro de aqui vamos a seleccionar todo lo qe deseamos eliminar y le damos a `Run Tweaks`. Esto me ha permitido pasar de windows sin nada de background ocupar 4gb de ram (en un sistema de 8gb) y 12% de cpu, a 1,2gb de ram y 2% de cpu.

![](<img/Pasted image 20251206231006.png>)

Una vez acabado, podemos cerrarlo y ahora solo voy a eliminar el botón del escritorio de `Mas información`.

![](<img/Pasted image 20251206233452.png>)

Si quereis eliminarlo Entra dentro del directorio `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel key`

Creamos una nueva `DWORD (32-bit)` llamada `{2cc5ca98-6485-489a-920e-b3e88a6ccce3}` y le ponemos de valor en hexadecimal de 1. Y ya esta, si volvemos al escritorio no lo encontraremos. 

![](<img/Pasted image 20251206233517.png>)

## GPU Passthrough

Una vez instalado Windows 11 y configurado, ahora tenemos que hacer el passthrough de la gráfica, para ello primero debemos de verificar que se encuentre en el mismo grupo de IOMMU (Tus dispositivos PCI se dividen en grupos, denominados grupos IOMMU. Tu GPU se encuentra en uno o varios de estos grupos, y debe pasar a la máquina virtual la totalidad del grupo que contiene su GPU.). Por lo que ejecutaremos el siguiente script dentro de nuestra terminal para revisar que nuestra gráfica se encuentre con su audio dentro del mismo grupo IOMMU

```bash
#!/bin/bash
shopt -s nullglob
for g in /sys/kernel/iommu_groups/*; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
```

![](<img/Pasted image 20251222165846.png>)

En este caso mi grafica y mi audio (HDMI) estan dentro del mismo grupo, por lo que por mucho que no vaya a usar el audio por HDMI, también lo tengo que pasar a la maquina virtual.

Vamos a configurar libvirt, en este caso debemos modificar el siguiente archivo  y descomentar las siguientes lineas.

```bash
sudo nano /etc/libvirt/libvirtd.conf
```

```bash
unix_sock_group = "libvirt"

unix_sock_rw_perms = "0770"
```

![](<img/Pasted image 20251207005549.png>)

Una vez hecho metemos a nuestro usuario actual dentro de los grupos kvm y libvirt.

```bash
sudo usermod -a -G kvm,libvirt $(whoami)
```

![](<img/Pasted image 20251207005640.png>)

Una vez hecho reiniciamos libvirt.

```bash
for drv in qemu interface network nodedev nwfilter secret storage; do
    sudo systemctl restart virt${drv}d.service;
    sudo systemctl restart virt${drv}d{,-ro,-admin}.socket;
done
```

Una vez reiniciado, modificamos el siguiente archivo, donde entre las lineas `518` y `524` deberemos reemplazara `root` por nuestro usuario, en este caso `isma`.

```bash
sudo nano /etc/libvirt/qemu.conf
```

![](<img/Pasted image 20251207010036.png>)

![](<img/Pasted image 20251207010059.png>)

### Parcheando la vbios de la GPU

Ahora debemos parchear la ROM de nuestra GPU, esto es obligatorio dentro de NVIDIA aunque algunos AMD también, el proceso es bastante sencillo, pero que cada uno lo haga bajo su propio riesgo, si quieres intentarlo bajo tu responsabilidad.

Descargar la herramienta [NVFLASH](https://www.techpowerup.com/download/nvidia-nvflash/) ([AMDVFLASH](https://www.techpowerup.com/download/ati-atiflash/) para amd), haces click sobre `CTRL + ALT + F2`, una vez ahí, te loguees y paras el display manager (en mi caso sddm)

```bash
sudo systemctl stop sddm # en el caso que uses systemd
```

Una vez dentro, descargamos los modulos de nvidia del kernel en el siguiente orden:

```markdown
1. sudo rmmod nvidia_uvm
2. sudo rmmod nvidia_drm
3. sudo rmmod nvidia_modeset
4. sudo rmmod nvidia
```

(Aveces en algunas GPUs un servicio llamado `nvidia-persistenced` te puede frenar al intentar descargar algunos modulos, para ello simplemente ejecuta el siguiente comando para pararlo temporalmente:`sudo systemctl stop nvidia-persistenced`)

Una vez descargado solo hacemos lo siguiente:
```bash
# Donde hayamos descargado el script de nvflash
sudo chmod +x nvflash
sudo ./nvflash --save vbios.rom
```

Y ya esta, ahora simplemente podemos cargarlos los modulos de kernel de nuevo

```bash
sudo modprobe nvidia
sudo modprobe nvidia_uvm
sudo modprobe nvidia_drm
sudo modprobe nvidia_modeset

# y ejecutamos nuestro display manager (en mi caso sddm)

sudo systemctl start sddm
```

Este ejemplo es para Nvidia, en el caso de amd los modulos que se tienen que descargar son los siguientes:

```bash
# DEscargar modulos AMD
sudo rmmod drm_kms_helper
sudo rmmod amdgpu
sudo rmmod radeon

# Dumpear vbios
sudo chmod +x amdvbflash
sudo ./amdvbflash -s 0 vbios.rom

# Cargar modulos
sudo modprobe drm_kms_helper
sudo modprobe amdgpu
sudo modprobe radeon
```

Si no te sientes seguro dumpeando tu rom, puedes descargarla desde [aqui](https://www.techpowerup.com/vgabios/), de nuevo, bajo tu propia responsabilidad.

Una vez tenemos la vbios, vamos a patchearla, para ello la abrimos dentro de `OKTETA`.

![](<img/Pasted image 20251207031108.png>)

Una vez dentro hacemos click sobre `CTRL + F` para filtrar por `VIDEO` en `Char`.

![](<img/Pasted image 20251207031217.png>)

Una vez encontrado, seleccionamos desde la `U` que hay enfrente de `VIDEO`

![](<img/Pasted image 20251207031353.png>)
Cambia el modo a edit con la tecla `insert` y pulsa `DEL` para eliminar todo eso para que quede de la siguiente manera:

![](<img/Pasted image 20251207034312.png>)

Una vez hecho, creamos una carpeta llamada vgabios y lo metemos ahi con los permisos 644.

```bash
sudo mkdir /usr/share/vgabios
sudo cp patched.rom /usr/share/vgabios/
cd /usr/share/vgabios
sudo chmod 644 patched.rom
sudo chown $(whoami):$(whoami) patched.rom
```


### Scripts

Una vez parcheada la rom, vamos a “hijackear” la gpu de linux y pasarsela en caliente a windows, por lo que para ello utilizaremos hooks (Creamos el directorio para el:).

```bash
sudo mkdir /etc/libvirt/hooks
```

![](<img/Pasted image 20251207140040.png>)

Una vez dentro, instalamos tree para poder visualizar mejor la estructura de directorios.

![](<img/Pasted image 20251207140226.png>)

Crearemos la estructura de archivos dada por la documentación de [libvirt](https://www.libvirt.org/hooks.html#id8), los tenemos que crear dentro del directorio `/etc/libvirt/hooks` y la carpeta que va despues de **qemu.d** (`win11`), debeis sustituirlo por el nombre de la maquina virtual.

```bash
mkdir -p qemu.d/win11/prepare/begin/
mkdir -p qemu.d/win11/release/end/
```

![](<img/Pasted image 20251207140336.png>)

Una vez hecho tendrá la estructura mostrada en el `tree`, dentro de `/etc/libvirt/hooks` vamos a descargarnos un script.

```bash
sudo wget 'https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/qemu' -O /etc/libvirt/hooks/qemu

sudo chmod +x /etc/libvirt/hooks/qemu # le damos permisos de ejecución
```

![](<img/Pasted image 20251207141815.png>)

Ahora vamos a crear el script que se ejecutara antes de iniciar la maquina virtual, para ello hacemos nano (o el editor de texto que queramos) al siguiente directorio.

```bash
nano qemu.d/win11/prepare/begin/start.sh 
```

El primer paso del script es (como cuando dumpeamos la vbios) parar el **display manager**.

Para saber cual tenemos debemos ejecutar el siguiente comando:

```bash
readlink /etc/systemd/system/display-manager.service
```

En este caso tengo sddm

![](<img/Pasted image 20251222180850.png>)

Por lo que el script se vería de la siguiente manera:

```bash
#!/bin/bash
systemctl stop sddm
systemctl isolate multi-user.target

sleep 5 # Esperamos 5 segundos para asegurarnos de que se para el servicio sddm
```

Ahora debemos asegurarnos de cuantas `vtconsoles` tenemos, por lo que para ello ejecutamos el siguiente comando:

```bash
ls /sys/class/vtconsole
```

![](<img/Pasted image 20251207143647.png>)

En este caso tenemos 2 (la 0 y la 1) por lo que hacemos bind a esas 2, despues unbindeamos el framebuffer del efi, los modulos de nvidia y por ultimo cargamos los modulos de vfio.

```bash 
systemctl stop sddm
systemctl isolate multi-user.target

while systemctl is-active --quiet sddm.service; do
	sleep 1
done

echo 0 > /sys/class/vtconsole/vtcon0/bind
echo 0 > /sys/class/vtconsole/vtcon1/bind

echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

## Unload NVIDIA GPU drivers ##
modprobe -r nvidia_uvm
modprobe -r nvidia_drm
modprobe -r nvidia_modeset
modprobe -r nvidia
modprobe -r i2c_nvidia_gpu
modprobe -r drm_kms_helper
modprobe -r drm

## Load VFIO-PCI driver ##
modprobe vfio
modprobe vfio_pci
modprobe vfio_iommu_type1
```

Una vez hecho, vamos a hacer lo mismo pero al revés para `/release/end/revert.sh`. Se debería ver de la siguiente manera:

![](<img/Pasted image 20251207161337.png>)

Una vez hecho, vamos a `virtual machine manager`, y en `Add`>`PCI Host Device`. Añadimos tanto la grafica como el audio HDMI.

![](<img/Pasted image 20251207144603.png>)

Entramos en la grafica y en XML, le añadimos la siguiente linea para darle el archivo ROM:

```XML
`<rom file='/usr/share/vgabios/patched.rom'/>`
```

![](<img/Pasted image 20251222154732.png>)

Adicionalmente **eliminamos**  cualquier `spice` o `virtual monitor`. Una vez hecho, iniciamos la VM.

Una vez ejecutada vemos que seguimos sin grafica, para ello le tenemos que instralar los drivers.

![](<img/Pasted image 20251207163251.png>)

Dentro de administrador de tareas tampoco sale.

![](<img/Pasted image 20251207163259.png>)

Procedemos con la instalación de los drivers NORMALES de nuestra grafica.

![](<img/Pasted image 20251207163308.png>)

![](<img/imagen.png>)

![](<img/2.png>)

Una vez acabe, ahí reconocerá nuestra targeta grafica.

![](<img/3.png>)

Si entramos en ajustes, vemos como nos esta soportando 2k a 165hz.

![](<img/4.png>)
### CPU PINING

Una vez finalizada la configuración de **GPU Passthrough**, el siguiente paso es implementar **CPU Pinning**. Para comprender su utilidad, es importante analizar primero el contexto actual **sin CPU Pinning**.

En la situación actual, mientras la máquina virtual está en ejecución, el sistema host (**Arch Linux**, en mi caso, **btw**) y el sistema invitado (**Windows**) compiten dinámicamente por el uso de los núcleos del procesador. Esta contención de recursos provoca que, en escenarios donde el procesador tiene un papel determinante —especialmente en videojuegos, además de la carga gráfica—, el rendimiento no sea óptimo.

El **CPU Pinning** soluciona este problema asignando de forma explícita determinados núcleos del procesador a la máquina virtual. De este modo, dichos núcleos quedan reservados exclusivamente para el sistema invitado, impidiendo que el host los utilice y garantizando así un acceso estable y predecible a los recursos de CPU, lo que se traduce en una mejora notable del rendimiento y la latencia.

Por lo que primero debemos configurar la topologia de nuestro procesador, para ello utilizaremos el siguiente comando:

```bash
lscpu -e

lstopo # es mas grafico
```

![](<img/Pasted image 20251207161441.png>)

```bash
lstopo
```

![](<img/Pasted image 20251207161519.png>)

Encontramos en nuestra topologia de procesador que tenemos 5 P-cores (Performance) y 8 E-cores (Efficient), en este caso tenemos HiperThreading activado, pero solo en 5 nucleos de los 13.
En este caso como tenemos que quitarle video de la maquina y paramos el display manager (sddm), pues como el host solo va a correr cosas como: `systemd`, `I/O scheduler` (o no si hacemos usb pasthrough), por lo que en este contexto 2 E-cores que son 2 nucleos y 2 hilos tienen la suficiente “potencia” como para gestionar esto por lo que nos quedaremos con todos los `P-Cores` para la vm.

Si volvemos a ejecutar `lscpu -e` podemos ver que en este caso seran los vCPUs 18 y 19 que dejaremos al host, por lo que para hacer ello utilizaremos `systemctl` para indicarles que nucleos puede usar el sistema, para que de esta manera el resto se reserven solo para la vm.


```bash
systemctl set-property --runtime -- user.slice AllowedCPUs=18-19
systemctl set-property --runtime -- system.slice AllowedCPUs=18-19
systemctl set-property --runtime -- init.scope AllowedCPUs=18-19
```


Una vez añadamos esto a nuestra configuración, en cuento nuestra máquina virtual inicie, Linux solo podra utilizar los `E-cores` 18 y 19. Por lo que vamos a añadir esto a 
`qemu.d/win11/prepare/begin/start.sh`

```bash
#/etc/libvirt/hooksqemu.d/win11/prepare/begin/start.sh
...
## Load VFIO-PCI driver ##

modprobe vfio
modprobe vfio_pci
modprobe vfio_iommu_type1

## CPU PINNING ##

systemctl set-property --runtime -- user.slice AllowedCPUs=18-19
systemctl set-property --runtime -- system.slice AllowedCPUs=18-19
systemctl set-property --runtime -- init.scope AllowedCPUs=18-19
```

Y una vez puesto hacemos lo mismo pero para release, en este caso le pondremos todos los nucleos (0-19)

```bash
#/etc/libvirt/hooksqemu.d/win11/release/end/revert.sh
## CPU PINNING RELEASE ##

systemctl set-property --runtime -- user.slice AllowedCPUs=0-19
systemctl set-property --runtime -- system.slice AllowedCPUs=0-19
systemctl set-property --runtime -- init.scope AllowedCPUs=0-19


## Unload VFIO-PCI driver ##

modprobe -r vfio_pci
modprobe -r vfio_iommu_type1
modprobe -r vfio
...


```

Ahora Windows no estará constantemente peleándose con arch sobre quien tiene que utilizar que.

Por lo que vamos a configurar la topología de la CPU en la configuración de la VM, para ello entramos en `Virtual Machine Manager`, En la maquina le damos a `Show Virtual Hardware` Y dentro de `Overview` entramos en XML

![](<img/Pasted image 20251212154620.png>)

En vez de usar 16vCPUs vamos a usar 18:

```xml
  <cputune>
    <vcpupin vcpu="0" cpuset="0"/>
    <vcpupin vcpu="1" cpuset="1"/>
    <vcpupin vcpu="2" cpuset="2"/>
    <vcpupin vcpu="3" cpuset="3"/>
    <vcpupin vcpu="4" cpuset="4"/>
    <vcpupin vcpu="5" cpuset="5"/>
    <vcpupin vcpu="6" cpuset="6"/>
    <vcpupin vcpu="7" cpuset="7"/>
    <vcpupin vcpu="8" cpuset="8"/>
    <vcpupin vcpu="9" cpuset="9"/>
    <vcpupin vcpu="10" cpuset="10"/>
    <vcpupin vcpu="11" cpuset="11"/>
    <vcpupin vcpu="12" cpuset="12"/>
    <vcpupin vcpu="13" cpuset="13"/>
    <vcpupin vcpu="14" cpuset="14"/>
    <vcpupin vcpu="15" cpuset="15"/>
    <vcpupin vcpu="16" cpuset="16"/>
    <vcpupin vcpu="17" cpuset="17"/>
  </cputune>
```

![](<img/Pasted image 20251212160413.png>)

Con esto cada ver que se inicie la maquina virtual (de manera automatica) (y durante su ejecucción) arch no podrá acceder a esos nucleos.
## HUGE PAGES

Ahora solo queda la paginación de la RAM. Podemos hacer paginación de RAM estatica, pero en este caso la haremos dinamica, ya que si lo hacemos estatica la RAM estará reservada desde el inicio de ARCH por lo que con solo 16gb de RAM, no es una opción viable.

En este caso le hemos dado “14336”Mib de RAM a la vm, por lo que vamos a hacer que una vez se pare el sddm por lo que en consecuencia se habran terminado los procesos corriendo en la sesión del usuario (es lo que mas ocupa), lo reservaremos para la maquina virtual, por lo que añadimos el parametro `memoryBacking` en xml:

```XML
  <memoryBacking>
    <hugepages/>
    <nosharepages/>
  </memoryBacking>
```

![](<img/Pasted image 20251222183020.png>)

Ahora vamos a crear el archivo de configuración para definir el comportamiento de la memoria para la maquina virtual win11 KVM (al kernel). 

```bash
sudo nano /etc/sysctl.d/win11-kvm.conf
```

```bash
# No reservar páginas enormes al inicio (ahorra RAM para el host)
vm.nr_hugepages = 0

# Permitir asignar dinámicamente hasta 6500 páginas (13000 MiB)
# Se recomienda un pequeño margen extra para overhead de QEMU, ej: 6600
vm.nr_overcommit_hugepages = 6600
```

![](<img/Pasted image 20251211193144.png>)

Ahora forzamos que recarguen los parametros del kernel sin reiniciar la maquina virtual:

![](<img/Pasted image 20251211193218.png>)

Por lo que ya hemos acabado de configurar nuestra maquina virtual de windows 11. De nuevo aqui dejo algunos benchmarks sobre el rendimiento:

Barebones:

![](<img/Captura de pantalla 2025-12-22 182145.png>)


VM
![](<img/Captura de pantalla 2025-12-22 211200.png>)
