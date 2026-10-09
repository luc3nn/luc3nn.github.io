---
title: "MacOS en KVM con Single GPU Passthrough"
featureimage: "img/portada.jpg"
showHero: true
heroStyle: "basic"   #
date: 2026-10-09T01:00:00+02:00
draft: false
description: "Guía completa para configurar una máquina virtual de MacOS en KVM/QEMU con Single GPU Passthrough, CPU Pinning y Hugepages en Arch Linux."
tags: [
  "kvm",
  "qemu",
  "gpu-passthrough",
  "vfio",
  "arch-linux",
  "MacOS",
  "virtualizacion",
  "cpu-pinning",
  "hugepages"
]
categories: ["Virtualización", "Linux", "MacOS"]
showTableOfContents: true
---
A diferencia de el anterior post de la virtualización de Windows11 para gaming... Para este no tengo excusa, he tenido anteriormente un **hackintosh** y realmente, quería aprovechar la ventaja que permite KVM de poder virtualizar el tipo de procesador y como tengo un procesador AMD no tener que instalar los parches de kernel, y de esta manera no tener problemas al virtualizar o al abrir cierta aplicación, pero al final lo he tenido que hacer igual. Y realmente MacOS no ofrece una ventaja real que se me ocurra sobre porque virtualizar. Para este punto esto de virtualizar ya parece una obsesión.

<img src="https://tenor.com/view/gülmek-komik-gif-12950352696137374051.gif" height="420" width="420">

Una vez expuestos mis fetiches, comparto una imágen del resultado final y seguidamente toca explicar de nuevo terminos que utlizaremos durante el post.

![](<img/Pasted image 20261009222436.png>)

Para esto empezamos usando un hipervisor de tipo 1, en este caso existen 2 tipos de hipervisores: Tipo 1 y Tipo 2. La cualidad que define cual es cada tipo de hipervisor es el nivel de detalle sobre el control que tenemos sobre la máquina virtual invitada, esto se traduce en poder controlar cosas como por ejemplo la habilidad de poder dar hardware de nuestro ordenador a la máquina virtual como **Discos duros**, **GPUs**, **Antena Bluetooth**. La idea con esto es poder exprimir más el rendimiento de nuestra máquina virtual, ya que en vez de tener que virtualizar todo de nuevo, simplemente le pasamos el hardware directamente. 

![](<img/Pasted image 20260930234311.png>)

Como podemos observar en la imagen y como decia anteriormente en este caso nos saltamos una capa entera que es la virtualización de hardware despues de la capa del sistema operativo, haciendo que nuestro sistema operativo sea el propio virtualizador. A este tipo de virtualización (Tipo 1) se le llama coloquialmente "Bare Metal". Una vez lo hemos definido, nos da algo de pistas de cual es cual, pero para acabar de definir, encontramos dentro del **Hipervisor de Tipo 2** a programas como **VMWare Workstation/Fusion**, **Virtualbox**, etc. Dentro del **Hipervisor de Tipo 1** encontramos tanto sitemas operativos completos donde el unico objetivo es virtualizar: **Proxmox**, **VMWare Esxi**, **Citrix**, etc. Como "herramientas" que nos permiten transformar nuestro sistema operativo en un **Hipervisor de Tipo 1**: **KVM**, **Hyper-V**, **Docker** (Postman, aunque entran dentro de LXC en Linux y Hyper-V en Windows).

# Requsitos
En este post asumimos que tenemos el entorno de virtualización creado, en el caso de que no lo tengas, te recomiendo ir al post anterior de Windows11 para preparar el entorno, una vez todo instalado, vuelve aqui.

# Creando el USB de booteo
## Creación de disco virtual

Para comenzar primero debemos crear nuestro "USB" de booteo, para ello primero instalamos las dependencias necesarias.

```bash
sudo pacman -S qemu dosfstools --needed
```
![](<img/Pasted image 20261001000627.png>)
Una vez nos hemos asegurado que lo tenemos instaladas las dependencias para crear el disco virtual, creamos este.

```bash
qemu-img create -f raw OpenCore.img 2G #Con 2G tenemos más que suficiente sobretodo para logs
```
![](<img/Pasted image 20261001001327.png>)
En este caso una vez que lo tenemos creado, lo conectamos.

```
➜  sudo modprobe nbd max_part=8
➜  sudo qemu-nbd --connect=/dev/nbd0 -f raw OpenCore.img
➜  lsblk -o NAME | grep "^nbd[0-9]\+$"
```

![](<img/Pasted image 20261001001443.png>)
Una vez conectado lo vamos a formatear a `FAT32`.

```bash
sudo mkfs.fat -F 32 -n "OPENCORE" -I /dev/nbd0
```

![](<img/Pasted image 20261001001554.png>)
Hecho, simplemente lo montamos en nuestro entorno de trabajo en el directorio que queramos, en este caso he creado una carpeta llamada `mnt` dentro de el directorio de trabajo.

```
sudo mount -o uid=$(id -u),gid=$(id -g) /dev/nbd0 mnt
```

![](<img/Pasted image 20261001001658.png>)
Sencillo. Ahora viene la parte mas "Divertida", crear la EFI.

## Creación de EFI

Para crear nuestra EFI utilizaremos el archivo de **[OpenCorePKG](https://github.com/acidanthera/OpenCorePkg/releases/)**, para ello primero lo descargamos, en este caso la versión `DEBUG`, este nos permitirá depurar todos los errores y asi poder arreglarlo, una vez tengamos una `EFI` funcional, podemos pasarlo al **RELEASE**.
![](<img/Pasted image 20261001192613.png>)
Una vez abierto, lo descomprimimos, y entendemos que el directorio desde donde tenemos que empezar a trabar es `X64` ya que esta es la arquitectura de nuestro procesador.

### Estructura de una Carpeta EFI

Antes de describir como se estructura una carpeta EFI, debemos entender que es **OpenCorePKG**. Este es un bootloader, el cual se encarga de interceptar las peticiones durante el arranque y emular/traducir estas para que **MacOS** crea que se esta ejecutando en un MAC real y adicionalmente pueda funcionar bien.

Dentro de la carpeta `X64` encontramos la carpeta `EFI`, esta se compone de las siguientes subcarpetas:
![](<img/Pasted image 20261009180900.png>)
En este caso tenemos un archivo que aun no tenemos en el archivo que acabamos de descargar, este es un ejemplo de EFI acabada. Como podemos ver, se compone de la siguiente estructura:

```nose
EFI/
├── BOOT/
│   └── BOOTx64.efi
└── OC/
    ├── ACPI/
    ├── Drivers/
    ├── Kexts/
    ├── Tools/
    ├── Resources/
    ├── config.plist
    └── OpenCore.efi
```

Para entender el proceso de arranque primero debemos de entender que cuando un ordenador arranca, la especificación `UEFI` universal dice que cualquier dispositivo de almacenamiento para la arquitectura x86_64 debe tener un booteable en `EFI/BOOT/BOOTx64.efi`.

#### BOOT

En este caso simplemente `BOOTx64.efi` lo único que hace es cargar `EFI/OC/OpenCore.efi`, nada más.

#### OC

De nuevo `OpenCore.efi` lo único que hace es llamar a `config.plist` y leer sus instrucciones, en este caso `config.plist` simplemente actua como un archivo de configuración sobre que cargar y como hacerlo (podriamos decir coloquialmente que es como un mapa).

##### OC/ACPI
Como hemos indicado anteriormente el objetivo de la carpeta `EFI` es "emular"/"traducir" las llamadas que hace en este contexto MacOS durante el arranque. En este caso **ACPI** contiene archivos compilados en `.aml` de las tablas **DSDT** y **SSDT**. En este caso en terminos sencillos le estamos pasando a **MacOS** que componentes existen dentro de la placa base, donde estan conectados, como interactuar con ellos y como gestionar su energía. 

En este caso gestiona cosas como:
- Topología PCI
- Permite configurar soporte como brillo, trackpad o teclas FN.
- mapear USBs, audio y gestionar el reloj.
- Inyectar propiedades o nombres en la GPU para que Apple lo pueda reconocer.

##### OC/Drivers

En este caso en vez de traducir, el proposito de esta carpeta es "**enseñar**" a MacOS a hacer cosas que de fábrica no sabe hacer antes de que este empiece a cargar. Este nos permite hacer cosas como:
- Leer dispositivos de almacenamiento en un sistema de archivos que no comprende (de base el ordenador es incapaz de leer e interpretar un disco formateado por Apple, APFS)
- Enseñarle a MacOS a asignar la memoria RAM para no cargar el kernel en regiones "protegidas" de la placa base.
- Funciones Visuales

##### OC/Kexts

En este caso, cumple la misma función que [[#OC/Drivers]] pero la diferencia es que este lo hace durante el arranque del kernel, antes de darle el "control" a MacOS, de hecho `Kext`viene de Kernel Extension. Básicamente cuando `OpenCore.efi` carga el archivo `boot.efi` (archivo de arranque de MacOS), antes de dejar control, este lee la carpeta de `Kexts` y añade/adjunta, todos estos "parches" directamente al kernel de la memoria ram. Nos permite hacer cosas como:
- Emular componentes que no existen (como SMC)
- Parchear el sistema en caliente
- Traducir hardware de PC a Macos
Algo interesante es que aqui el orden importa, como veremos más adelante, el orden que se ponen los kexts en `config.plist` hace que funcione, primero debe cargar `Lilu.kext` seguidamente `VirtualSMC` y de ahi ya puede cargar audio, red, graficos, etc.

##### OC/Tools y OC/Resources

En este caso queda lo mas sencillo, simplemente en `Tools` tenemos utilidades para utilizar durante el menú de `opencore`, estas nos puden servir para cosas como diagnostico, etc. Y finalmente tenemos `Resources` que es el que nos permite dar junto al driver `OpenCanopy.efi` un tema visual al menú.

### Creación de la carpeta EFI

Una vez entendemos de como se compone una carpeta `EFI` y sus funciones, vamos a comenzar a montar la nuestra, en este caso si mientras leías la explicación estuviste viendo los contendios de la carpeta `X64` te habrás dado cuenta que no teines el archivo de configuración `config.plist`, no pasa nada, esto es normal, por lo que el primer paso será pasar el nuestro a el dir `OC`.

Para ello nos ponemos en el directorio `X64/EFI/OC` y ejecutamos el siguiente comando

```bash
cp ../../../Docs/Sample.plist config.plist
```

![](<img/Pasted image 20261001193745.png>)
Os comparto mi config.plist en el caso de que tengais AMD para que solo tengais que hacer un `OC Clean Snapshot`. En el caso de que quieras montartela tú, una vez hecho, ya tenemos el archivo de config (más tarde lo configuramos). Ahora comencemos con la carpeta `ACPI`

#### ACPI

Para el primero, necesitamos `SSDT-EC-USBX.aml`, este lo que hará será inyectar las propiedades de alimentación eléctrica de los USB y crea un dispositivo **dummy** que finje ser un **Embeded Controller** (lo necesita MacOS para arrancar) para ello:

```bash
wget https://github.com/royalgraphx/DarwinOCPkg/raw/refs/heads/main/Docs/AcpiSamples/SSDT-EC-USBX.aml
```

Ahora necesitamos crear nuestro propio ACPI, en este caso primero necesitamos instalar las herramientas necesarias para compilarlo y crearlo.

```bash
sudo pacman -S acpica                                                        
```

Creamos el archivo `SSDT-MCHC.dsl` con el siguiente contenido

```dsl
DefinitionBlock ("", "SSDT", 2, "ACDT", "MCHC", 0x00000000)
{
	// Hacemos referencia al bus PCI raíz existente en QEMU
	External (_SB_.PCI0, DeviceObj)

	Scope (\_SB.PCI0)
	{
		// Declaramos el dispositivo MCHC en la dirección 0x00 (Host Bridge)
		Device (MCHC)
		{
			Name (_ADR, Zero)

			// El método _STA devuelve 0x0F (Presente, Habilitado, Decodificando) solo si el SO es Darwin (macOS)
			Method (_STA, 0, NotSerialized)
			{
				If (_OSI ("Darwin"))
				{
					Return (0x0F)
				}
				Else
				{
			Return (Zero)
				}
			}
		}
	}
}
```

Ahora simplemente lo compilamos con el siguiente comando

```bash
iasl SSDT-MCHC.dsl
```

A diferencia de las guías convencionales de OSX-KVM basadas en overlays de Intel (que requieren SSDT-PLUG para el X86PlatformPlugin de Intel), un despliegue con CPU passthrough en AMD Ryzen requiere parches AMD Vanilla. En este entorno, SSDT-PLUG es innecesario y contraproducente (apunta a objetos inexistentes en el DSDT de Q35).

Quedando de la siguiente manera:

![](<img/Pasted image 20261009193535.png>)
#### Drivers

Una vez instalado los `SSDT`, vamos a instalar los drivers, para ello, eliminamos todos menos:
- OpenRunetime.efi
- OpenPartitionDxe.efi
- ResetNvramEntry.efi

Una vez tenemos eso, instalamos el driver `HfsPlus.efi`, este nos permitirá leer los discos particionados en `APFS` de apple, para ello lo descargamos con `wget`.

```bash
wget https://github.com/acidanthera/OcBinaryData/raw/master/Drivers/HfsPlus.efi
```

Una vez lo tenemos la carpeta nos debería quedar asi:

![](<img/Pasted image 20261009194606.png>)
#### Kexts

Ahora pasamos a la parte más divertida, los kexts. En este caso necesitamos los siguientes si o si:
- [Lilu](https://github.com/acidanthera/Lilu)
- [VMHide](https://github.com/Carnations-Botanica/VMHide)
- [AppleMCEReporterDisabler](https://github.com/acidanthera/bugtracker/files/3703498/AppleMCEReporterDisabler.kext.zip)

Una vez los tenemos, tenemos otros opcionales, pero que necesitaremos para no estar cambiando la EFI todo el rato.

| Kext                                                                                           | Description                                                                                                    |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| [WhateverGreen](https://github.com/Carnations-Botanica/WhateverGreen/actions/runs/17772496735) | Used for graphic patching, DRM fixes, etc.                                                                     |
| [VirtualSMC](https://github.com/acidanthera/virtualsmc/releases)                               | Emulador de Apple SMC, necesita Lilu para funcionar.                                                           |
| [RestrictEvents](https://github.com/acidanthera/RestrictEvents)                                | Permite cambios esteticos y bloquear procesos que puedan provocar problemas de compatibilidad (requiere lilu). |

El resultado final se debería ver así.
![](<img/Pasted image 20261009195438.png>)
#### Resources

En este caso ya estamos apunto de acabar de descargar archivos para la EFI, en este caso esto es puramente éstetico, por lo que es opcional.

| Antes                                     | Después                                   |
| ----------------------------------------- | ----------------------------------------- |
| ![](<img/Pasted image 20261009195758.png\>) | ![](<img/Pasted image 20261002104810.png\>) |
Para conseguir esto, necesitamos clonar el repositorio [OcBinaryData](https://github.com/acidanthera/OcBinaryData).

```bash
mkdir temp && cd temp && git clone https://github.com/acidanthera/OcBinaryData.git
rm -rf ../Resources && mv OcBinaryData/Resources ../
```

![](<img/Pasted image 20261001215007.png>)
En este caso simplemente creamos un directorio temporal dentro de `OC`y despues lo eliminamos.
![](<img/Pasted image 20261009200216.png>)
### Configuración de config.plist

Ahora ya tenemos todo lo que necesitamos, necesitamos generar el archivo de configuración el cual mapeara todos estos archivos y le añadiremos "opciones" cuando lo necesite.

Comenzamos clonando esta herramienta fuera de la carpeta de `EFI`

```bash
git clone https://github.com/corpnewt/ProperTree
python3 ProperTree/ProperTree.py
```

![](<img/Pasted image 20261001194001.png>)
Una vez ejecutado, importamos nuestro `config.plist`

![](<img/Pasted image 20261001195241.png>)
![](<img/Pasted image 20261001195315.png>)

Una vez añadido, le eliminamos los comentarios.
![](<img/Pasted image 20261001195530.png>)

Una vez lo tenemos, ya podemos empezar a trabajar, para hacerlo de manera más ordenada vamos a cerrar todas las opciones.

![](<img/Pasted image 20261001200141.png>)
Vamos a abrir con otra instancia de `ProperTree` el archivo `patch.plist` para parchear el kernel para AMD de el siguiente [repo](https://github.com/AMD-OSX/AMD_Vanilla/)

```bash
wget https://github.com/AMD-OSX/AMD_Vanilla/raw/refs/heads/master/patches.plist
python3 ProperTree/ProperTree.py
```

Una vez abierto hacemos click en `Collapse All` de nuevo y hacemos click derecho y `Copy Children` a `Kernel/Patch`. Seguidamente lo pegamos en nuestro `config.plist`
![](<img/Pasted image 20261001200346.png>)
Una vez lo tenemos vamos a pegar el siguiente texto en `Kernel/Patch` de nuevo.

```plist
<plist version="1.0">
<array>
	<dict>
		<key>Arch</key>
		<string>x86_64</string>
		<key>Base</key>
		<string>__ZN17IOPCIConfigurator18IOPCIIsHotplugPortEP16IOPCIConfigEntry</string>
		<key>Comment</key>
		<string>CaseySJ | IOPCIIsHotplugPort | Fix PCI bus enumeration on KVM | 13.0+</string>
		<key>Count</key>
		<integer>1</integer>
		<key>Enabled</key>
		<true/>
		<key>Find</key>
		<data>hAB1Sw==</data>
		<key>Identifier</key>
		<string>com.apple.iokit.IOPCIFamily</string>
		<key>Limit</key>
		<integer>0</integer>
		<key>Mask</key>
		<data>/wD//w==</data>
		<key>MaxKernel</key>
		<string>24.99.99</string>
		<key>MinKernel</key>
		<string>22.0.0</string>
		<key>Replace</key>
		<data>AADrAA==</data>
		<key>ReplaceMask</key>
		<data>AAD/AA==</data>
		<key>Skip</key>
		<integer>0</integer>
	</dict>
</array>
</plist>
```

![](<img/Pasted image 20261001200346.png>)
Este es un fix para que el kernel sea capaz de poder mapear el pasthrough de PCI que haremos más tarde. El resultado es el siguiente:

![](<img/Pasted image 20261009203654.png>)

Seguidamente en `NVRAM/Add/7C43...` le pegamos lo siguiente para poder tenerlo en inglés.

```
	<key>prev-lang:kbd</key>
	<data>ZW46MjUy</data>
```

![](<img/Pasted image 20261001200719.png>)
Quedará así.
![](<img/Pasted image 20261001200659.png>)
Eliminamos el que habia antes
![](<img/Pasted image 20261001200857.png>)
Y modificamos el nuevo quitandole el 2
![](<img/Pasted image 20261001200918.png>)
Seguidamente en `PlatformInfo/Generic/SystemProductName` debemos cambiar el valor a `MacPro7,1`. Esto lo hacemos ya que es el Mac más "parecido" con un ordenador normal por lo que es más facil de parchear.
![](<img/Pasted image 20261001201152.png>)

![](<img/Pasted image 20261001201212.png>)
Seguidamente podemos quitar la restricción de que solo permite drivers APFS de `Big Sur` o superior cambiando el valor de `0` a `-1`
![](<img/Pasted image 20261001201311.png>)
Quedará así
![](<img/Pasted image 20261009203751.png>)
Seguidamente podémos cambiar info sobre 

```plist
<key>SMBIOS</key>
<dict>
	<key>BIOSVendor</key>
	<string>Luc3nn</string>
	<key>BoardManufacturer</key>
	<string>Luc3nn</string>
	<key>ChasisManufacturer</key>
	<string>Luc3nn</string>
	<key>SystemManufacturer</key>
	<string>Luc3nn</string>
</dict>
```

Esto es en caso de que queramos pero el apartado de PlataformInfo si esta en generic normalmente pone los datos del modelo que hayamos puesto.

Seguidamente cambiamos el tema de booteo, para ello cambiamos el valor de:
- PickerMode = External
- PickerVariant = Acidanthera\GoldenGate
![](<img/Pasted image 20261001215343.png>)
Quedando así
![](<img/Pasted image 20261001215431.png>)
Una vez ya tenemos todo configurado hacemos un `OC Clean Snapshot` para que añada todos los archivos descargados automaticamente
![](<img/Pasted image 20261001222424.png>)
Seleccionamos el directorio de OC
![](<img/Pasted image 20261001222450.png>)
Hecho, ahora vamos a seguir parcheando por secciones.
![](<img/Pasted image 20261001222503.png>)
#### Booter

Seguidamente cambiamos los siguientes valores
- EnableWriteUnprotector = False
- RebuildAppleMemoryMap = True
- SetupVirtualMap = False
- SyncRuntimePermissions = True
![](<img/Pasted image 20261001222735.png>)
#### Kernel

Ahora cambiamos en `Kernel/Patch/MaxKernel` el valor a `29.99.99`
![](<img/Pasted image 20261001223049.png>)
Adicionalmente en `Kernel/Quirks` cambiamos los siguientes valores:
- ForceSecureBootScheme = True
- PanicNoKextDump = True
- PowerTimeoutKernelPanic = ProvideCurrentCpuInfo
![](<img/Pasted image 20261001223212.png>)
En `Kernel/Scheme` dejamos los siguientes valores.
- FuzzyMatch = False
- KernelArch = x86_64
![](<img/Pasted image 20261001223315.png>)
#### Misc
Seguidamente nos aseguramos que en `Misc/Boot` la **Key** `PollAppleHotkeys` esté en `True`.
![](<img/Pasted image 20261001223345.png>)
Después en `Misc/Debug`los siguientes valores.
- AppleDebug = True
- ApplePanic = True
- DisableWatchDog = True
- Target = 67
![](<img/Pasted image 20261001223428.png>)
En `Misc/Security` cambiamos los valores:
- AllowSetDefault = True
- ExponseSensitiveData = 15
- ScanPolicy = 0
- Vault = Optional
![](<img/Pasted image 20261001223541.png>)
#### NVRAM

Aqui simplemente le ponemos dentro de la key `boot-args` el valor `debug=0x100 debug=0x12a serial=5 agdpmod=pikera -cdfon tlbto_us=0` (degug es para depuración y el resto para la grafica y parche de el procesador), debe quedar de la siguiente manera

![](<img/Pasted image 20261009211853.png>)
#### PlataformInfo

Ahora debemos descargar la siguiente [herramienta](https://github.com/corpnewt/GenSMBIOS) y ejecutarla.

```bash
git clone https://github.com/corpnewt/GenSMBIOS
cd GenSMBIOS
python3 GenSMBIOS.py
```

Escogemos la 3ra opción
![](<img/Pasted image 20261001223803.png>)

Seguidamente ponemos `MacPro7,1`
![](<img/Pasted image 20261001223841.png>)
Automaticamente nos genera la SMBIOS
![](<img/Pasted image 20261001223939.png>)
Lo ponemos en nuestro `config.plist` siguiendo la siguiente tabla.

| GenSMBIOS    | config.plist       |
| ------------ | ------------------ |
| Board Serial | MLB                |
| Apple ROM    | ROM                |
| Type         | SystemProductName  |
| Serial       | SystemSerialNumber |
| SmUUID       | SystemUUID         |
![](<img/Pasted image 20261001224210.png>)
Y ya hemos acabado de configurar nuestro `config.plist` ahora lo guardamos y podemos cerrar `ProperTree`.
## Descargando MacOS

Una vez ya tenemos nuestros archivos de la `EFI`, ahora necesitamos el instalador, asi que para ello utilizaremos la herramienta de [royalgraphx](https://github.com/royalgraphx/DarwinFetch), ya que asumo que no tienes MacOS. Vamos a instalarla

```bash
cd $(mktemp -d)
git clone https://github.com/royalgraphx/DarwinFetch.git
python3 -m venv env
source env/bin/activate
pip3 install -r requirements.txt
```
![](<img/Pasted image 20261001230300.png>)
Ahora lo ejecutamos

```bash
./DarwinFetch.sh
```

En este caso escogemos `RecoveryOS Installer` (2)
![](<img/Pasted image 20261001230408.png>) 
Escogemos la versión que queramos.
![](<img/Pasted image 20261001230505.png>)
Una vez que se decargue salimos.
![](<img/Pasted image 20261001230454.png>)
Si revisamos lo que se ha descargado, en este caso nos aparece una carpeta que pone `com.apple.recovery.boot`
![](<img/Pasted image 20261001230529.png>)
Copiamos la carpeta `com.apple.recovery.boot` junto a la carpeta `EFI` que está dentro de `X64` dentro de la carpeta `mnt`.
![](<img/Pasted image 20261001230800.png>)
una vez tenemos eso, podemos desmontar mnt.

```bash
sudo umount mnt && sudo qemu-nbd --disconnect /dev/nbd0
```
![](<img/Pasted image 20261001230918.png>)
Hecho, ya hemos acabado nuestro USB.
# Creando la máquina virtual

Comenzamos abriendo `virt-manager`, le damos al icono para crear una nueva máquina virtual.
![](<img/Pasted image 20261001231733.png>)
Le ponemos `Manual install` porque añadiremos nuestro USB como disco virtual.
![](<img/Pasted image 20261001231746.png>)
En cuanto a la versión del sistema operativo lo ponemos como `Generic...`.
![](<img/Pasted image 20261001231820.png>)
En la ram ponemos icialmente 8gb o lo que podamos para el primer booteo e instalación (no hagais como la foto). En los hilos ponemos solo 1, al final todo lo modificaremos desde el XML.
![](<img/Pasted image 20261001231841.png>)
Creamos un nuevo disco duro donde instalaremos MacOS.
![](<img/Pasted image 20261001231913.png>)
le damos a la opción de `Customize configuration before install` para poder modificar parametros del XML.
![](<img/Pasted image 20261001231957.png>)
Una vez entramos módificamos el chipset a `Q35`.
![](<img/Pasted image 20261001232132.png>)
Seguidamente pegamos este XML dentro del apartado de XML después de apartado de `<uuid>` (cambiar donde pone `<!--CAMBIAR DIR-->`)


```xml
  <memory unit="KiB">8192000</memory>
  <currentMemory unit="KiB">8192000</currentMemory>
  <vcpu placement="static">4</vcpu>
  <cputune>
    <vcpupin vcpu="0" cpuset="0"/>
    <vcpupin vcpu="1" cpuset="1"/>
    <vcpupin vcpu="2" cpuset="2"/>
    <vcpupin vcpu="3" cpuset="3"/>
  </cputune>
  <os firmware="efi">
    <type arch="x86_64" machine="pc-q35-11.1">hvm</type>
    <firmware>
      <feature enabled="no" name="enrolled-keys"/>
      <feature enabled="no" name="secure-boot"/>
    </firmware>
    <loader readonly="yes" type="pflash" format="raw">/usr/share/edk2/x64/OVMF_CODE.4m.fd</loader>
    <nvram template="/usr/share/edk2/x64/OVMF_VARS.4m.fd" templateFormat="raw" format="raw">/var/lib/libvirt/qemu/nvram/Machintosh_VARS.fd</nvram>
    <bootmenu enable="yes"/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <kvm>
      <hidden state="on"/>
    </kvm>
    <vmport state="off"/>
    <smm state="on"/>
    <ps2 state="off"/>
  </features>
  <cpu mode="host-passthrough" check="none" migratable="on">
    <topology sockets="1" dies="1" clusters="1" cores="4" threads="1"/>
    <feature policy="require" name="invtsc"/>
    <feature policy="disable" name="hypervisor"/>
  </cpu>
  <clock offset="utc">
    <timer name="rtc" tickpolicy="delay"/>
    <timer name="pit" tickpolicy="delay"/>
    <timer name="hpet" present="no"/>
    <timer name="tsc" present="yes" mode="native"/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <pm>
    <suspend-to-mem enabled="no"/>
    <suspend-to-disk enabled="no"/>
  </pm>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type="file" device="disk">
      <driver name="qemu" type="raw" cache="none" io="native"/>
      <source file="/var/lib/libvirt/images/Machintosh.img"/> <!--CAMBIAR DIR-->
      <target dev="sda" bus="sata"/>
      <boot order="2"/>
      <address type="drive" controller="0" bus="0" target="0" unit="0"/>
    </disk>
    <disk type="file" device="disk">
      <driver name="qemu" type="raw"/>
      <source file="/home/isma/Desktop/isma/macos2/OpenCore.img"/> <!--CAMBIAR DIR-->
      <target dev="sdb" bus="sata"/>
      <boot order="1"/>
      <address type="drive" controller="0" bus="0" target="0" unit="1"/>
    </disk>
    <controller type="usb" index="0" model="qemu-xhci">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x1d" function="0x0"/>
    </controller>
    <controller type="sata" index="0">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x1f" function="0x2"/>
    </controller>
    <controller type="pci" index="0" model="pcie-root"/>
    <controller type="pci" index="1" model="pcie-root-port">
      <model name="pcie-root-port"/>
      <target chassis="1" port="0x10"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x02" function="0x0" multifunction="on"/>
    </controller>
    <controller type="pci" index="2" model="pcie-root-port">
      <model name="pcie-root-port"/>
      <target chassis="2" port="0x11"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x02" function="0x1"/>
    </controller>
    <interface type="network">
      <mac address="52:54:00:55:8d:da"/>
      <source network="default"/>
      <model type="vmxnet3"/>
      <address type="pci" domain="0x0000" bus="0x01" slot="0x00" function="0x0"/>
    </interface>
    <input type="tablet" bus="usb">
      <address type="usb" bus="0" port="1"/>
    </input>
    <input type="keyboard" bus="usb">
      <address type="usb" bus="0" port="2"/>
    </input>
    <graphics type="spice">
      <listen type="none"/>
      <image compression="off"/>
    </graphics>
    <audio id="1" type="spice"/>
    <video>
      <model type="virtio" heads="1" primary="yes" device="virtio-vga"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x01" function="0x0"/>
    </video>
    <watchdog model="itco" action="none"/>
    <memballoon model="none"/>
  </devices>
  <qemu:commandline>
    <qemu:arg value="-global"/>
    <qemu:arg value="ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off"/>
  </qemu:commandline>
</domain>
```

Seguidamente lo podemos dar a `Begin Installation`.
![](<img/Pasted image 20261001234047.png>)
PORFIN, ya carga Opencore, entramos en `RECOVERY.dmg`
![](<img/Pasted image 20261002104810.png>)
# Instalando MacOS

Esperamos a que cargue (puede tardar un poco)
![](<img/Pasted image 20261006144955.png>)
Una vez en el recovery entramos en `Disk Utility`
![](<img/Pasted image 20261006144218.png>)
Una vez dentro, en el `Sidebar` seleccionamos `Show All Devices`
![](<img/Pasted image 20261006144238.png>)
Hacemos click a nuestro disco duro y le damos a `Erase`.
![](<img/Pasted image 20261006144326.png>)
Le ponemos el nombre que queramos y le damos a `Erase`
![](<img/Pasted image 20261006144517.png>)
Tardará poco y de ahi le damos a `Done`
![](<img/Pasted image 20261006144928.png>)
Una vez formateado podemos salir y darle a `Reinstall macOS Seoquia`
![](<img/Pasted image 20261006145004.png>)
Una vez dentro le damos a `Siguiente` hasta que nos deje instalar.
![](<img/Pasted image 20261006145046.png>)
Una vez instalado nos aparecerá la siguiente pantalla.
![](<img/Pasted image 20261006173557.png>)
Le vamos dando a siguiente y podemos iniciar sesión con la cuenta de Apple (le he dado a más tarde).
![](<img/Pasted image 20261006173916.png>)
Al final de la instalación ya tendremos macOS pero sin acceleración gráfica ni nada, por lo que en este caso vamos a apagar la máquina virtual.
![](<img/Pasted image 20261006174550.png>)
Siguiendo la guía [anterior](https://luc3nn.github.io/posts/windowskvm-singlegpu/#gpu-passthrough) sobre `GPU Pasthrough` sacamos la vbios, añadimos el pci de la gráfica.
![](<img/Pasted image 20261006193824.png>)
 Finalmente añadimos las siguientes líneas en el `prepare/begin/start.sh`
```prepare/begin/start.sh
## Unbind and Resize GPU BAR0 to 256MB for macOS ##
if [ -d "/sys/bus/pci/devices/0000:0c:00.0/driver" ]; then
    echo "0000:0c:00.0" > "/sys/bus/pci/devices/0000:0c:00.0/driver/unbind"
fi
if [ -f "/sys/bus/pci/devices/0000:0c:00.0/resource0_resize" ]; then
    echo " Resizing GPU BAR0 to 256MB"
    echo 8 > "/sys/bus/pci/devices/0000:0c:00.0/resource0_resize" || true
fi
if [ -d "/sys/bus/pci/drivers/vfio-pci" ]; then
    echo "vfio-pci" > "/sys/bus/pci/devices/0000:0c:00.0/driver_override" 2>/dev/null || true
    echo "0000:0c:00.0" > "/sys/bus/pci/drivers/vfio-pci/bind" 2>/dev/null || true
fi
```

y las siguientes en `release/end/stop.sh`
```release/end/stop.sh
## 1. Desvincular GPU y Audio de vfio-pci si aún están vinculados ##
if [ -d "/sys/bus/pci/devices/$GPU_VGA/driver" ]; then
    echo "$DATE Desvinculando GPU de $(basename $(readlink /sys/bus/pci/devices/$GPU_VGA/driver))"
    echo "$GPU_VGA" > "/sys/bus/pci/devices/$GPU_VGA/driver/unbind" 2>/dev/null || true
fi

if [ -d "/sys/bus/pci/devices/$GPU_AUDIO/driver" ]; then
    echo "$DATE Desvinculando Audio de $(basename $(readlink /sys/bus/pci/devices/$GPU_AUDIO/driver))"
    echo "$GPU_AUDIO" > "/sys/bus/pci/devices/$GPU_AUDIO/driver/unbind" 2>/dev/null || true
fi

## 2. Limpiar driver_override (elimina 'vfio-pci' para permitir que amdgpu tome el control) ##
echo "$DATE Limpiando driver_override..."
echo "" > "/sys/bus/pci/devices/$GPU_VGA/driver_override" 2>/dev/null || true
echo "" > "/sys/bus/pci/devices/$GPU_AUDIO/driver_override" 2>/dev/null || true

## 3. Restaurar BAR0 de la GPU al tamaño nativo de 16GB (índice 14) para Arch Linux ##
if [ -f "/sys/bus/pci/devices/$GPU_VGA/resource0_resize" ]; then
    echo "$DATE Restaurando BAR0 a 16GB (SAM) para Linux..."
    echo 14 > "/sys/bus/pci/devices/$GPU_VGA/resource0_resize" 2>/dev/null || true
fi
```

Una vez tenemos eso, podemos iniciar la VM y deberíamos tener video por HDMi.

# Resultado Final
![](<img/Pasted image 20261009222451.png>)
# Optimizaciones
Aqui os dejo un ejemplo de el `xml` con mapeo de CPU.

```diff
---template_macintosh.xml
+++macintosh_passthrough_optimized.xml
@@ -1,15 +1,30 @@
 <domain type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0">
-  <name>Machintosh</name>
+  <name>macintosh</name>
   <uuid>bf8ec364-c3e5-46a2-9dea-aac261521c3c</uuid>
-  <memory unit="KiB">8192000</memory>
-  <currentMemory unit="KiB">8192000</currentMemory>
-  <vcpu placement="static">4</vcpu>
+  <memory unit="KiB">20971520</memory>
+  <currentMemory unit="KiB">20971520</currentMemory>
+  <vcpu placement="static">16</vcpu>
   <cputune>
-    <vcpupin vcpu="0" cpuset="0"/>
-    <vcpupin vcpu="1" cpuset="1"/>
-    <vcpupin vcpu="2" cpuset="2"/>
-    <vcpupin vcpu="3" cpuset="3"/>
+    <vcpupin vcpu="0" cpuset="6"/>
+    <vcpupin vcpu="1" cpuset="18"/>
+    <vcpupin vcpu="2" cpuset="7"/>
+    <vcpupin vcpu="3" cpuset="19"/>
+    <vcpupin vcpu="4" cpuset="8"/>
+    <vcpupin vcpu="5" cpuset="20"/>
+    <vcpupin vcpu="6" cpuset="9"/>
+    <vcpupin vcpu="7" cpuset="21"/>
+    <vcpupin vcpu="8" cpuset="10"/>
+    <vcpupin vcpu="9" cpuset="22"/>
+    <vcpupin vcpu="10" cpuset="11"/>
+    <vcpupin vcpu="11" cpuset="23"/>
+    <vcpupin vcpu="12" cpuset="4"/>
+    <vcpupin vcpu="13" cpuset="16"/>
+    <vcpupin vcpu="14" cpuset="5"/>
+    <vcpupin vcpu="15" cpuset="17"/>
   </cputune>
+  <resource>
+    <partition>/machine</partition>
+  </resource>
   <os firmware="efi">
	 <type arch="x86_64" machine="pc-q35-11.1">hvm</type>
	 <firmware>
@@ -17,7 +32,7 @@
	   <feature enabled="no" name="secure-boot"/>
	 </firmware>
	 <loader readonly="yes" type="pflash" format="raw">/usr/share/edk2/x64/OVMF_CODE.4m.fd</loader>               
     <nvram template="/usr/share/edk2/x64/OVMF_VARS.4m.fd" templateFormat="raw" format="raw">/var/lib/libvirt/qemu/nvram/macintosh_VARS.fd</nvram>                 
	 <bootmenu enable="yes"/>
   </os>
   <features>
@@ -31,7 +46,8 @@
	 <ps2 state="off"/>
   </features>
   <cpu mode="host-passthrough" check="none" migratable="on">
-    <topology sockets="1" dies="1" clusters="1" cores="4" threads="1"/>
+    <topology sockets="1" dies="1" clusters="1" cores="16" threads="1"/>
+    <maxphysaddr mode="passthrough" limit="39"/>
	 <feature policy="require" name="invtsc"/>
	 <feature policy="disable" name="hypervisor"/>
   </cpu>
@@ -81,32 +97,76 @@
	   <target chassis="2" port="0x11"/>
	   <address type="pci" domain="0x0000" bus="0x00" slot="0x02" function="0x1"/>
	 </controller>
+    <controller type="pci" index="3" model="pcie-root-port">
+      <model name="pcie-root-port"/>
+      <target chassis="3" port="0x8"/>
+      <address type="pci" domain="0x0000" bus="0x00" slot="0x01" function="0x0"/>
+    </controller>
	 <interface type="network">
	   <mac address="52:54:00:55:8d:da"/>
	   <source network="default"/>
-      <model type="vmxnet3"/>
+      <model type="virtio"/>
	   <address type="pci" domain="0x0000" bus="0x01" slot="0x00" function="0x0"/>
	 </interface>
-    <input type="tablet" bus="usb">
+    <serial type="tcp">
+      <source mode="bind" host="127.0.0.1" service="4555"/>
+      <protocol type="raw"/>
+      <target type="isa-serial" port="0">
+        <model name="isa-serial"/>
+      </target>
+    </serial>
+    <console type="tcp">
+      <source mode="bind" host="127.0.0.1" service="4555"/>
+      <protocol type="raw"/>
+      <target type="serial" port="0"/>
+    </console>
+    <audio id="1" type="none"/>
+    <hostdev mode="subsystem" type="usb" managed="yes">
+      <source startupPolicy="mandatory">
+        <vendor id="0x413c"/>
+        <product id="0x2106"/>
+        <address bus="7" device="2"/>
+      </source>
+      <address type="usb" bus="0" port="3"/>
+    </hostdev>
+    <hostdev mode="subsystem" type="usb" managed="yes">
+      <source startupPolicy="mandatory">
+        <vendor id="0x1532"/>
+        <product id="0x007b"/>
+        <address bus="3" device="3"/>
+      </source>
+      <address type="usb" bus="0" port="4"/>
+    </hostdev>
+    <hostdev mode="subsystem" type="pci" managed="yes">
+      <driver name="vfio"/>
+      <source>
+        <address domain="0x0000" bus="0x0c" slot="0x00" function="0x0"/>
+      </source>
+      <rom file="/home/isma/Desktop/isma/macos2/GPU.rom"/>
+      <address type="pci" domain="0x0000" bus="0x02" slot="0x00" function="0x0" multifunction="on"/>
+    </hostdev>
+    <hostdev mode="subsystem" type="pci" managed="yes">
+      <driver name="vfio"/>
+      <source>
+        <address domain="0x0000" bus="0x0c" slot="0x00" function="0x1"/>
+      </source>
+      <address type="pci" domain="0x0000" bus="0x02" slot="0x00" function="0x1"/>
+    </hostdev>
+    <hostdev mode="subsystem" type="usb" managed="yes">
+      <source>
+        <vendor id="0x046d"/>
+        <product id="0x0acb"/>
+      </source>
	   <address type="usb" bus="0" port="1"/>
-    </input>
-    <input type="keyboard" bus="usb">
-      <address type="usb" bus="0" port="2"/>
-    </input>
-    <graphics type="spice">
-      <listen type="none"/>
-      <image compression="off"/>
-    </graphics>
-    <audio id="1" type="spice"/>
-    <video>
-      <model type="virtio" heads="1" primary="yes" device="virtio-vga"/>
-      <address type="pci" domain="0x0000" bus="0x00" slot="0x01" function="0x0"/>
-    </video>
+    </hostdev>
	 <watchdog model="itco" action="none"/>
	 <memballoon model="none"/>
   </devices>
   <qemu:commandline>
	 <qemu:arg value="-global"/>
	 <qemu:arg value="ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off"/>
+    <qemu:arg value="-global"/>
+    <qemu:arg value="pcie-root-port.pref64-reserve=32G"/>
   </qemu:commandline>
 </domain>
```

Para CPU pining y Hugepages ir a [aquí](https://luc3nn.github.io/posts/windowskvm-singlegpu/#cpu-pining)
