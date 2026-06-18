# ============================================================
# Stage 1: Build — Compilar con Maven
# ============================================================
FROM maven:3.9-eclipse-temurin-17 AS build

WORKDIR /app
COPY Springboot-API-REST ./Springboot-API-REST
WORKDIR /app/Springboot-API-REST
RUN mvn clean package -DskipTests -B

# ============================================================
# Stage 2: Production — Solo JRE Alpine (imagen liviana)
# ============================================================
FROM eclipse-temurin:17-jre-alpine

# Crear usuario no-root (mínimo privilegio)
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

COPY --from=build /app/Springboot-API-REST/target/*.jar app.jar

RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/v1/ventas || exit 1

ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]
