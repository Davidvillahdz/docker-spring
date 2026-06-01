PARTE 1: Archivos de Configuración Esenciales
Para meter tres procesos en un solo contenedor, no podemos usar un CMD simple de Java, ya que Docker por defecto solo monitorea un proceso principal. Necesitamos un gestor de procesos ligero. La opción estándar en la industria para esto es supervisord (un gestor de procesos basado en Python) o un script en Bash. Usaremos supervisord porque es el más robusto para la rúbrica.

Debes crear tres archivos en la raíz del proyecto (al lado de pom.xml):

1. supervisord.conf (Gestor de Procesos)
Este archivo le dice a Docker cómo arrancar y monitorear Nginx y Spring Boot en paralelo.

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

2. nginx.conf (Servidor Web como Punto de Entrada)
Nginx recibirá las peticiones externas en el puerto 80 y las redirigirá internamente al puerto 5000 donde escucha Spring Boot.

````
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
`````
3. Dockerfile (Multietapa / Multi-stage)
Para compilar Java y preparar la imagen ligera con Nginx y la base de datos embebida, usamos construcción multietapa.
```
# ETAPA 1: COMPILACIÓN (Maven)
FROM maven:3.9.6-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

# ETAPA 2: RUNTIME PRODUCTIVO MULTISERVICIO
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Instalación de Nginx y Supervisor
RUN apt-get update && apt-get install -y \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Configuración de base de datos embebida SQLite y persistencia
RUN mkdir -p /app/data

# Copiar configuraciones de servicios
COPY nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copiar el artefacto JAR desde la etapa de compilación
COPY --from=build /build/target/*.jar /app/app.jar

# Exponer el punto de entrada de Nginx (Puerto 80)
EXPOSE 80

# Arrancar el gestor de procesos
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```
 Justificaciones Técnicas Relevantes (Parte 1 — 2.5 puntos)
¿Por qué esa imagen base? Se seleccionó eclipse-temurin:17-jre-jammy para la etapa final. Ofrece un entorno de ejecución de Java (JRE) oficial y optimizado, omitiendo las herramientas de compilación del JDK completo. Esto disminuye drásticamente el peso de la imagen y reduce la superficie de ataque en producción.

¿Por qué esa estrategia de build? Se implementó una construcción multietapa (Multi-stage build). La primera etapa (maven:3.9.6) se encarga exclusivamente de compilar el código fuente y generar el .jar. La segunda etapa descarga un entorno limpio y copia únicamente el binario resultante. Esto evita dejar el código fuente y las herramientas de compilación dentro de la imagen final, optimizando el espacio en el sistema distribuido.

¿Qué gestor de procesos usa y por qué? Se eligió supervisord. Debido a que el principio de diseño nativo de Docker es "un proceso por contenedor", la ejecución simultánea de Nginx y Spring Boot requiere un inicializador que actúe como proceso principal (PID 1). Supervisor se encarga de lanzar ambos servicios en paralelo, redirigir sus logs a la salida estándar y reiniciarlos automáticamente si alguno llega a fallar.

¿Qué motor de base de datos eligió y qué implicaciones tiene esa elección? Se eligió SQLite (o una base de datos embebida basada en archivos como H2). Al requerir una arquitectura autocontenida en una imagen única, un motor basado en archivos evita la complejidad de instalar y configurar un servidor relacional pesado (como PostgreSQL) dentro del mismo contenedor, manteniendo la ligereza del sistema.

¿Cómo persisten los datos si el contenedor se reinicia? Los datos persisten mediante el uso de Volúmenes de Docker (-v) o Bind Mounts. Al configurar la aplicación para que guarde el archivo de la base de datos en una ruta específica (ej. /app/data/inventario.db), esa carpeta se monta hacia el disco duro de la máquina anfitriona en tiempo de ejecución. Si el contenedor efímero se destruye o se detiene, el archivo físico permanece intacto en el host.

📸 Guía Estricta de Capturas de Pantalla (1 al 9)
Captura 1: El panel lateral izquierdo de VS Code donde se vea la carpeta app/ expandida, mostrando que los archivos Dockerfile, nginx.conf y supervisord.conf están en la raíz, junto al pom.xml.

Captura 2: Captura de pantalla en VS Code de los tres archivos de configuración abiertos (puedes usar la vista dividida).

Captura 3: Ejecución del comando de construcción en PowerShell:
```
docker build -t davidvilla7/inventario:1.0.0 .
```
Asegúrate de capturar el final de la pantalla donde se lea claramente EXPORTING TO IMAGE y NAMING TO... SUCCESS.

Captura 4: Ejecución del push a la nube:

```
docker push davidvilla7/inventario:1.0.0
```
Debe verse el listado de capas diciendo Pushed.

Captura 5: Tu navegador web abierto en hub.docker.com logueado con tu cuenta, mostrando el repositorio davidvilla7/inventario configurado como Public.

Captura 6 a 9 (Verificación Funcional):

Comando de arranque desde la nube: ```powershell
docker run -d --name test_inventario -p 80:80 -v C:\inventario_data:/app/data davidvilla7/inventario:1.0.0

Captura 6 (Nginx redirige): Petición de prueba con un navegador o Postman a http://localhost/health. Debe responder el JSON del backend de inmediato a través del puerto 80 (puerto de Nginx).

Captura 7 (Operación BD - POST): Hacer una petición de creación de producto (POST a http://localhost/productos) y mostrar que devuelve el producto guardado con un ID generado.

Captura 8 (Operación BD - GET): Hacer un GET a http://localhost/productos y verificar que el producto existe en la base de datos.

Captura 9 (Persistencia real): Ejecutar docker stop test_inventario, luego docker rm test_inventario. Volver a lanzar el docker run con el mismo volumen del host, hacer un GET a los productos y demostrar que el producto creado en la Captura 7 sigue apareciendo ahí.

❓ Respuestas a las Preguntas Escritas del Examen
Pregunta Parte 2: ¿Qué ventaja concreta ofrece el orden en que copió los archivos dentro del Dockerfile? ¿Qué pasaría si lo hiciera en orden inverso?
Respuesta: Ofrece la ventaja de optimizar el uso de la caché de capas de Docker. Al copiar primero el archivo pom.xml y ejecutar mvn dependency:go-offline, Docker descarga e instala todas las dependencias del framework y las congela en una capa de caché. Si los archivos se copiaran en orden inverso (es decir, haciendo COPY . . al inicio), cualquier modificación mínima en una línea de código de un controlador invalidaría toda la caché posterior, obligando al contenedor a descargar megabytes de dependencias de Maven desde internet en cada compilación, arruinando la agilidad del build.

Pregunta Parte 3: ¿Qué información debería agregar en Docker Hub para que otro desarrollador pueda usar su imagen sin necesitar acceso al código fuente?
Respuesta: Se debe incluir una documentación clara en el README del repositorio público que especifique:

El comando exacto de descarga e instanciación (docker run).

El mapeo de puertos requerido (ej. indicar que el punto de entrada es el puerto 80).

La variable de entorno o la ruta exacta del volumen necesaria para la persistencia de datos (ej. -v /ruta/host:/app/data), advirtiendo que de no mapearse, el inventario se perderá al destruir el contenedor.

La lista de endpoints principales disponibles para interactuar con el CRUD (ej. GET /health y POST /productos).

Pregunta Parte 4 (La de tu consulta - Pregunta 2 del prompt): Si al ejecutar el contenedor la aplicación Spring Boot tarda 15 segundos en arrancar pero Nginx arranca en 1 segundo, ¿qué problema podría ocurrir y cómo lo resolvería?
Respuesta: El problema principal es un fallo de sincronización y disponibilidad de servicio distribuido (Error 502 Bad Gateway). Como Nginx arranca de forma casi instantánea, empezará a recibir peticiones en el puerto 80 de inmediato; sin embargo, al intentar redirigir el tráfico hacia el puerto interno 5000 via proxy inverso, se encontrará con que el socket de Spring Boot aún no está activo debido al retardo de inicialización de la Máquina Virtual de Java (JVM).

Solución técnica:

A nivel de Dockerfile/Configuración: Implementar una instrucción de verificación de salud (Healthcheck) en el Dockerfile o utilizar utilidades como wait-for-it.sh o dockerize dentro del script de arranque del gestor de procesos. Esto fuerza a que Nginx retarde su inicialización o no empiece a rutear tráfico hacia el backend hasta que el puerto 5000 responda de forma exitosa a un código de estado HTTP 200 en el endpoint /health.

A nivel de Nginx: Configurar parámetros de reintentos y tiempos de espera tolerantes en el bloque de proxy (como proxy_connect_timeout y proxy_next_upstream) para que Nginx retenga la petición del cliente de forma síncrona en lugar de retornar un error inmediato de pasarela caída.

🏁 Conclusión para el Informe: Entorno de Producción Real con Múltiples Instancias
Si esta imagen fuera a un entorno de producción real escalable (como un clúster de Kubernetes), la arquitectura actual de "imagen todo en uno" debería desacoplarse por completo debido a las siguientes razones técnicas de sistemas distribuidos:

Desacoplamiento de la Base de Datos: Mantener SQLite embebido impide el escalamiento horizontal. Si levantas 3 instancias del contenedor, cada una tendrá su propio archivo de base de datos aislado, provocando una inconsistencia de datos crítica en el inventario. La solución es migrar a una base de datos relacional externa y centralizada (como PostgreSQL en AWS RDS).

Separación de Responsabilidades (Microservicios): Nginx y Spring Boot deberían correr en contenedores e infraestructuras independientes. Esto permite escalar únicamente las instancias de la aplicación backend ante picos de tráfico concurrente, delegando el enrutamiento y balanceo de carga a un Ingress Controller o un balanceador de carga nativo de la nube, optimizando costos y recursos de computación.
