# Ejemplos para el uso de la clase del kernel de Linux de sched_ext

## Notas importantes sobre los schedulers

Se requiere para la versión del kernel que estemos utilizando, descargar los ejemplos del kernel para sched_ext y extraer de estos la carpeta de scx. Esto para poder hacer uso de sus declaraciones de las funciones helper de sched_ext y así poder compilar nuestros schedulers. 
Además de esto se requiere de la creación de un fichero vmlinux.h para las declaracionesas definiciones de tipos y estructuras del kernel (como struct task_struct, struct sched_ext_ops, etc.).

### Como obtener scx para nuestro kernel
Para obtener el direcorio de scx con las funciones helpers basta con ejecutar el script get_scx.sh. Este descargara la última versión del repositorio oficial, además ofrece compatibilidad con diversos kernels debido a que el sistema de compatibilidad está diseñado para manejar estos casos sin que tú tengas que hacer nada. Por ejemplo, en kernels recientes (como la serie 6.19+), algunas funciones cambiaron su forma de recibir parámetros para cumplir con los límites de BPF. Las cabeceras del proyecto scx detectan esto automáticamente.
Por tanto para obtener nuestros headers para scx, basta con hacer uso del script get_scx.sh que se facilita. De todas maneras, se comprueba al ejecutar el build y por tanto el start, que este exista y en caso contrario se descarga.

## Comprobaciones y requerimientos de nuestro Linux
Para poder hacer uso de las funcionalidades de sched_ext necesitamos de un kernel superior o igual al 6.12. Para comprobar el kernel en el que estamos, podemos ejecutar el siguiente comando:
```bash
uname -r
```

Tras esto debemos de comprobar que tenemos instalado bpftool de la siguiente forma:
```bash
which bpftool
```
Si no nos devuelve la ruta de instalación de bpftool, podemos instalarlo de la siguiente manera dependiendo de nuestra distro:
- ArchLinux: ```bash sudo pacman -S bpftool ```
- Fedora: ```bash sudo dnf install bpftool ```
- Debian: ```bash sudo apt install linux-tools-common bpftool ```

Para comprobar que tenemos el soporte por parte del kernel para el subsistema de sched_ext y de BPF disponible en nuestro equipo lo podemos comprobar con el siguiente comando:
```bash
grep -E 'CONFIG_SCHED_CLASS_EXT|CONFIG_BPF|CONFIG_DEBUG_INFO_BTF' /boot/config-$(uname -r)
 ```
 Debemos fijarnos en la salida y encontrar ```bash CONFIG_SCHED_CLASS_EXT=y ``` lo que nos indica que está habilidado sched_ext.

 Por último nos queda comprobar que esté activo el subsistema de sched_ext para terminar de confirmar que está todo listo para hacer uso de los distintos schedulers:
 ```bash
 cat /sys/kernel/sched_ext/state
 ```
 Si nos muestra **disabled** es que está activo pero ningún scheduler cargado, si nos muestra **enabled** disponemos de un scheduler cargado y si muestra **error** el scheduler falló.

 También para poder compilar nuestros schedulers requerimos de clangd en concreto de la versió 19 para Ubuntu o Debian.
 ``` bash
 sudo apt install clangd-19 
 ```

 Debemos luego de esto instalar la librería para que Debian/Ubuntu encuentre las cabeceras de libbpf:
 ``` bash
 sudo apt install libbpf-dev
 ```


 ## Como usar el repositorio y sus ejemplos

 ### Pasos para lanzar para y observar nuestros schedulers

 - Para poder lanzar los scheduler debemos hacer uso del script start.sh ```bash sh start.sh {scheduler.c} ```
 - Para ver si tenemos algún scheduler registrado y cual, debemos de usar el script scheduler.sh ```bash sh scheduler.sh ```
 - Para parar el scheduler activo, usaremos stop.sh ``` bash sh stop.sh ```
 - Para poder ver las salidas del scheduler activo, tenemos log.sh ``` bash sh log.sh ``` 
