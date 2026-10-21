# ============ ETAPA 1: builder ============
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

# ID del estudiante inyectado en tiempo de construccion
ARG STUDENT_ID

WORKDIR /build

# 1) Solo el pom.xml: las dependencias se descargan una vez y quedan en cache
COPY pom.xml .
RUN mvn dependency:go-offline -B

# 2) Ahora el codigo fuente (si cambia src/, NO se repite el paso anterior)
COPY src ./src
RUN mvn package -DskipTests -B

# ============ ETAPA 2: runtime ============
FROM eclipse-temurin:17-jre-alpine

# Los ARG no se heredan entre etapas: se vuelve a declarar
ARG STUDENT_ID

# Usuario sin privilegios: sensor_user (UID 10001) en el grupo sensorgroup
RUN addgroup -g 10001 sensorgroup && \
    adduser -D -u 10001 -G sensorgroup sensor_user

WORKDIR /app

# Titularidad del directorio /app para sensor_user
RUN chown sensor_user:sensorgroup /app

# Copiar unicamente el .jar resultante, ya con el dueño correcto
COPY --from=builder --chown=sensor_user:sensorgroup /build/target/*.jar /app/app.jar

# Variables de entorno
ENV OPERATOR_ID=${STUDENT_ID}
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0 -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

EXPOSE 8080

# Cambiar a usuario no privilegiado ANTES del ENTRYPOINT
USER sensor_user

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
