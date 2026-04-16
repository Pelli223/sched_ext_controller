# Ejemplos para el uso de la clase del kernel de Linux de sched_ext

## Notas importantes sobre los schedulers

Se requiere para la versión del kernel que estemos utilizando, descargar los ejemplos del kernel para sched_ext y extraer de estos la carpeta de scx. Esto para poder hacer uso de sus declaraciones de las funciones helper de sched_ext y así poder compilar nuestros schedulers. 
Además de esto se requiere de la creación de un fichero vmlinux.h para las declaracionesas definiciones de tipos y estructuras del kernel (como struct task_struct, struct sched_ext_ops, etc.).

### Como obtener scx para nuestro kernel
Para obtener el direcorio de scx con las funciones helpers basta con ejecutar el script get_scx.sh. Este descargara la última versión del repositorio oficial, además ofrece compatibilidad con diversos kernels debido a que el sistema de compatibilidad está diseñado para manejar estos casos sin que tú tengas que hacer nada. Por ejemplo, en kernels recientes (como la serie 6.19+), algunas funciones cambiaron su forma de recibir parámetros para cumplir con los límites de BPF. Las cabeceras del proyecto scx detectan esto automáticamente.
