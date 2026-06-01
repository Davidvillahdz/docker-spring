#  Guía de Contenerización Multiservicio: Spring Boot + Nginx + SQLite

Este repositorio es una plantilla base para empaquetar, centralizar y desplegar una arquitectura distribuida "Todo en Uno" (Servidor Web Proxy, Backend Java y Base de Datos Embebida) en un único contenedor Docker.

---

## 1. Códigos de Configuración del Proyecto

Todos estos archivos deben residir estrictamente en la raíz del proyecto (al mismo nivel que el `pom.xml`).

###  1.1 `nginx.conf`
Actúa como el punto de entrada único (Puerto 80), redirigiendo el tráfico de forma inversa hacia el puerto interno del backend (Puerto 5000).
```nginx
events { worker_connections 1024; }

http {
    server {
        listen 80;

        location / {
            proxy_pass http://localhost:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
```
### 1.2 supervisord.conf
Gestor de procesos (PID 1) encargado de iniciar, monitorear y mantener vivos a Nginx y Spring Boot simultáneamente dentro del mismo contenedor efímero.
```
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid

[program:springboot]
command=java -jar /app/app.jar
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```
### 1.3 Dockerfile (Estrategia Multietapa)
```
# ETAPA 1: COMPILACIÓN (Maven)
FROM maven:3.9.6-eclipse-temurin-17 AS build
WORKDIR /build

# Aprovechamiento de la caché de dependencias de Maven
COPY pom.xml .
RUN mvn dependency:go-offline

# Copia de código fuente y empaquetado del binario (.jar)
COPY src ./src
RUN mvn clean package -DskipTests

# ETAPA 2: RUNTIME PRODUCTIVO MULTISERVICIO
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Instalación de herramientas del Sistema Operativo (Servidor Web y Gestor de Procesos)
RUN apt-get update && apt-get install -y \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Crear directorio dedicado a la persistencia de la base de datos SQLite
RUN mkdir -p /app/data

# Copiar configuraciones de los servicios hacia las rutas del contenedor
COPY nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Transferencia del artefacto .jar generado en la Etapa 1
COPY --from=build /build/target/*.jar /app/app.jar

# El puerto de entrada público hacia el host será el de Nginx (Puerto 80)
EXPOSE 80

# Comando de arranque inmutable controlado por Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```
### 1.4 .dockerignore
```
.git/
.gitignore
target/
.mvn/
mvnw
mvnw.cmd
*.log
.vscode/
.idea/
```
# 2. Flujo Secuencial de Terminal (PowerShell de Windows)
### Paso 1: Preparar la persistencia local en Windows
Antes de correr el contenedor, crea la carpeta en la raíz del disco C:\ para almacenar el archivo de la base de datos:
```
mkdir C:\data_examen
```
### Paso 2: Ejecutar el proceso de Build de la imagen
```
docker build -t davidvilla7/inventario:1.0.0 .
```
### Paso 3: Publicación en Docker Hub (Push)
```
# Iniciar sesión en el registro (Ingresa tus credenciales de la UPS si lo solicita)
docker login

# Subir la imagen etiquetada al repositorio público
docker push davidvilla7/inventario:1.0.0
```
### Paso 4: Limpieza local para Verificación Funcional
```
# Detener y eliminar el contenedor de prueba si existiera
docker stop test_app
docker rm test_app

# Eliminar la imagen local del disco duro para forzar el pull desde la nube
docker rmi davidvilla7/inventario:1.0.0
```
### Paso 5: Despliegue Funcional Externo (Pull automático)
```
docker run -d --name test_app -p 80:80 -v C:\data_examen:/app/data davidvilla7/inventario:1.0.0
```
### Paso 6: Comandos de Monitoreo y Administración de Ciclo de Vida
```
# Monitorear la inicialización en paralelo de Nginx y la JVM de Spring Boot
docker logs test_app

# Detener el contenedor conservando los datos del inventario en el host
docker stop test_app

# Volver a encender el contenedor recuperando el estado de la base de datos
docker start test_app

# Reiniciar los servicios en un solo paso
docker restart test_app
```
###### Banco de Respuestas Escritas
Pregunta Parte 2: Ventaja del orden de copia de archivos en el Dockerfile.
Respuesta: Optimiza el uso de la caché de capas de Docker. Al copiar el archivo pom.xml y ejecutar mvn dependency:go-offline antes de transferir el código fuente, las dependencias pesadas se descargan e instalan una sola vez y quedan congeladas en la caché. Si se hiciera en orden inverso (colocando COPY . . al inicio), cualquier cambio mínimo en un archivo de texto o un controlador de Java invalidaría toda la caché posterior, obligando al contenedor a volver a descargar megabytes de librerías de internet en cada build, rompiendo la agilidad de Integración Continua (CI).

Pregunta Parte 3: ¿Qué información agregar en Docker Hub?
Respuesta: Se debe documentar en la descripción del repositorio (README público):

El comando exacto de instanciación en producción (docker run).

El mapeo de puertos requerido (especificar que el punto de entrada es el puerto 80).

El volumen mandatorio para la persistencia del inventario (-v /ruta/host:/app/data), advirtiendo que de no mapearse, los datos se perderán al destruir el contenedor.

La lista de rutas HTTP y verbos del CRUD disponibles (ej. GET /health y POST /productos) para su consumo inmediato.

Pregunta Parte 4: Retardo en el arranque (Spring Boot 15s vs Nginx 1s).
Respuesta: Provoca un error 502 Bad Gateway. Nginx arranca de forma casi instantánea e intentará redirigir el tráfico del puerto 80 hacia el backend; sin embargo, al encontrarse con que la Máquina Virtual de Java (JVM) sigue en proceso de inicialización y no ha abierto el socket en el puerto 5000, el proxy inverso fallará y retornará un error al cliente.
Solución: Implementar una instrucción de Healthcheck en el Dockerfile o utilizar utilidades de control de flujo como wait-for-it.sh en el script de Supervisor. Esto retarda el inicio de Nginx o bloquea el ruteo de peticiones externas hasta que el puerto 5000 responda exitosamente con un código de estado HTTP 200 en la ruta /health.

Conclusión: Cambios para un entorno de producción real escalable.
Respuesta: Para un entorno real masivo, se debe desacoplar la arquitectura. Mantener Nginx, Spring Boot y SQLite en la misma imagen impide el escalamiento horizontal. Si se levantan múltiples instancias, cada una tendría un archivo SQLite aislado, causando una inconsistencia de datos crítica. La solución real es migrar a una base de datos relacional externa y centralizada (como PostgreSQL en AWS RDS), y separar Nginx de la aplicación para que corran en contenedores independientes, permitiendo escalar únicamente el backend mediante un clúster u orquestador como Kubernetes según la demanda de tráfico.
