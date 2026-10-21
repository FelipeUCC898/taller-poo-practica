# FORENSIC REPORT - eco-air-backend

**Estudiante:** Felipe Narvaez Gomez  
**ID:** 908404  
**Fecha:** 20/10/2026

## 1. Tabla de Identidad

| Item | Comando | Salida |
|---|---|---|
| Hash de la imagen | `docker inspect --format="{{.Id}}" eco-air-backend:1.0.0` | `sha256:a46779ac60706c226e30433cf4f0aa38cbf510a274531036af395c140080789d` |
| Variable inyectada | `docker exec eco_air_active env \| findstr OPERATOR_ID` | `OPERATOR_ID=908404` |
| Consumo final calibrado | `docker stats --no-stream` | Ver salida completa abajo |

Salida completa de `docker stats --no-stream`:
```text
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O        BLOCK I/O       PIDS
ccbe145a9879   eco_air_crash    0.19%     136.6MiB / 256MiB   53.36%    872B / 126B    0B / 180kB      30
146a30705a03   eco_air_active   0.22%     134.3MiB / 256MiB   52.47%    1.3kB / 126B   176kB / 188kB   30
```

## 2. Reto 1 - Construccion

Comando usado:
```text
docker build --build-arg STUDENT_ID="908404" -t eco-air-backend:1.0.0 .
```

La imagen se construyo correctamente: aparece en `docker images` como `eco-air-backend:1.0.0` con ID `a46779ac6070`.

Salida (ultimas lineas del build):
```text
[PENDIENTE: pegar aqui las ultimas lineas del build si las conservas en audit_session.log]
```

## 3. Reto 2 - Auditoria forense

### 3.1 Historial de capas
```text
docker history --human --format "table {{.Size}}\t{{.CreatedBy}}" eco-air-backend:1.0.0
[PENDIENTE: pegar aqui la salida del comando]
```
Explicacion: la imagen final solo contiene el JRE, el usuario sin privilegios y el .jar. Maven y el codigo fuente quedaron en la etapa builder y no aparecen en las capas finales.

### 3.2 Aislamiento de privilegios
```text
docker top eco_air_active -o pid,user,comm
PID                 USER                COMMAND
957                 10001               java
```
Explicacion: el proceso `java` corre bajo el UID 10001, que corresponde a `sensor_user`; no corre como root. El host solo conoce el numero del UID, por eso `docker top` lo muestra como 10001.

```text
docker exec eco_air_active id
[PENDIENTE (recomendado): pegar la salida; debe mostrar uid=10001(sensor_user) gid=10001(sensorgroup)]
```

### 3.3 Inmutabilidad de runtime
```text
docker exec eco_air_active touch /etc/crontab_fake
touch: cannot touch '/etc/crontab_fake': Permission denied
```
Explicacion: sensor_user no tiene permisos de escritura sobre /etc (pertenece a root), por lo que un atacante que comprometa la aplicacion no puede dejar scripts persistentes en el sistema.

### 3.4 Artefactos de desarrollo
```text
docker exec eco_air_active which mvn
(sin salida)

docker exec eco_air_active sh -c "find / -name '*.java' 2>/dev/null"
(sin salida)
```
Explicacion: ambos comandos devolvieron salida vacia, lo que confirma que la imagen final no contiene Maven ni codigo fuente. Gracias al build multietapa, esas herramientas quedaron en la etapa builder, que se descarta. Esto reduce el tamano de la imagen y la superficie de ataque. (El redirect `2>/dev/null` se ejecuto dentro de `sh -c` porque PowerShell lo interpreta como una ruta de Windows.)

## 4. Reto 3 - cgroups

### 4.1 OOMKilled con 48 MB
```text
docker run -d --name eco_air_crash -m 48m eco-air-backend:1.0.0
docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
Status: exited | ExitCode: 137 | OOMKilled: true
```

| Campo | Valor | Significado |
|---|---|---|
| Status | exited | El contenedor ya no esta corriendo. |
| ExitCode | 137 | Es 128 + 9. El 9 es la senal SIGKILL, una orden de terminacion inmediata que el proceso no puede ignorar. |
| OOMKilled | true | Docker confirma que la causa fue Out Of Memory: el proceso supero el limite de memoria. |

Explicacion: con un limite de 48 MB, el OOM Killer del kernel de Linux termino el proceso porque Spring Boot con Hibernate necesita mas memoria que la cuota del cgroup. Observacion: una primera consulta hecha pocos segundos despues del arranque aun mostraba `running`, porque la JVM no habia terminado de agotar la memoria; al repetir la consulta el estado fue `exited` con codigo 137.

### 4.2 Calibracion

| Limite -m | Inicio OK | Tiempo de arranque (logs) | Observaciones |
|---|---|---|---|
| 48m | No | No inicio | OOMKilled, ExitCode 137 |
| 256m | Si | [PENDIENTE: segundos del log] | En ejecucion; consumo estable (ver tabla) |
| 384m | [PENDIENTE: probar] | [PENDIENTE] | [PENDIENTE] |
| 512m | [PENDIENTE: probar] | [PENDIENTE] | [PENDIENTE] |

Umbral minimo encontrado: **[PENDIENTE: confirmar tras las pruebas; con 256 MB el contenedor esta corriendo]**

Logs:
```text
docker logs --timestamps eco_air_active | findstr "Started EcoAirApplication"
[PENDIENTE: pegar aqui la salida; de ahi sale el tiempo de arranque, que debe ser menor a 15 segundos]
```

Docker stats (contenedor `eco_air_active`):

| CPU % | MEM USAGE / LIMIT | MEM % |
|---|---|---|
| 0.22% | 134.3MiB / 256MiB | 52.47% |

Salida completa:
```text
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O        BLOCK I/O       PIDS
ccbe145a9879   eco_air_crash    0.19%     136.6MiB / 256MiB   53.36%    872B / 126B    0B / 180kB      30
146a30705a03   eco_air_active   0.22%     134.3MiB / 256MiB   52.47%    1.3kB / 126B   176kB / 188kB   30
```

Analisis: con un limite de 256 MiB el contenedor se mantiene estable, usando unos 134 MiB (52.47 %) con CPU casi en reposo (0.22 %) y 30 procesos. Queda un margen de unos 120 MiB frente al limite para picos de carga.