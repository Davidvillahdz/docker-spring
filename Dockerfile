# ETAPA 1: COMPILACIÓN (Maven)
FROM maven:3.9.6-eclipse-temurin-17 AS build
WORKDIR /build

# Aprovechamiento de la caché de dependencias
COPY pom.xml .
RUN mvn dependency:go-offline

# Copia de código fuente y empaquetado (.jar)
COPY src ./src
RUN mvn clean package -DskipTests

# ETAPA 2: RUNTIME PRODUCTIVO MULTISERVICIO
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Instalación de herramientas del sistema operativo (Servidor Web y Gestor de procesos)
RUN apt-get update && apt-get install -y \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Crear directorio exclusivo para la persistencia del archivo SQLite
RUN mkdir -p /app/data

# Copiar configuraciones de los servicios hacia sus rutas del sistema
COPY nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Transferencia del binario compilado (.jar) desde la etapa 1
COPY --from=build /build/target/*.jar /app/app.jar

# El punto de entrada público será Nginx en el puerto 80
EXPOSE 80

# Arrancar el gestor de procesos supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]