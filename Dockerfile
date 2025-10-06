# =========================
# STAGE 1: BUILD (Maven)
# =========================
FROM eclipse-temurin:21-jdk-jammy AS build
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /workspace


RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      maven ca-certificates swi-prolog-java \
 && rm -rf /var/lib/apt/lists/*


RUN mkdir -p /Applications/SWI-Prolog.app/Contents/swipl/lib \
 && JPL_JAR=$(find /usr/lib -type f -name jpl.jar | head -n 1) \
 && cp "$JPL_JAR" /Applications/SWI-Prolog.app/Contents/swipl/lib/jpl.jar

# Cachear dependencias de Maven
COPY pom.xml .
RUN mvn -q -e -B -DskipTests dependency:go-offline

# Compilar el proyecto
COPY src ./src
RUN mvn -q -e -B -DskipTests clean package


# =========================
# STAGE 2: RUNTIME
# =========================
FROM eclipse-temurin:21-jre-jammy
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /opt/app

# Instalar SWI-Prolog sin GUI + JPL + tini
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      swi-prolog-nox swi-prolog-java ca-certificates tzdata tini wget \
 && rm -rf /var/lib/apt/lists/*

# Copiar jpl.jar del sistema a una ruta estable
RUN mkdir -p /opt/app/lib \
 && JPL_JAR=$(find /usr/lib -type f -name jpl.jar | head -n 1) \
 && cp "$JPL_JAR" /opt/app/lib/jpl.jar
ENV JPL_CP="/opt/app/lib/jpl.jar"

# Copiar la aplicación compilada
COPY --from=build /workspace/target/*.jar /opt/app/app.jar

# Se copia la base de conocimiento
COPY operaciones.pl /opt/app/prolog/operaciones.pl

# ===== Configuración de entorno =====

ENV SWI_HOME_DIR="/usr/lib/swi-prolog"
ENV PL_ARCH_DIR="/usr/lib/swi-prolog/lib/aarch64-linux"
ENV LD_LIBRARY_PATH="${PL_ARCH_DIR}"
ENV JAVA_LIBRARY_PATH="${PL_ARCH_DIR}"
ENV JAVA_OPTS="--enable-native-access=ALL-UNNAMED"


RUN useradd -ms /bin/bash appuser
USER appuser

EXPOSE 8080


ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["sh","-lc","java $JAVA_OPTS -Djava.library.path=$JAVA_LIBRARY_PATH -cp /opt/app/app.jar:$JPL_CP org.springframework.boot.loader.launch.JarLauncher"]