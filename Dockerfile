FROM alpine:3.9 as pom_files

# Workaround for a docker limitation: We want all pom.xml files in the
# right file system structure, but COPY/ADD doesn't support this.
# As a workaround we copy the whole source, delete anything but the pom
# files afterwards.
# Redirect to /dev/null to avoid the 'Directory not empty' messages
COPY . /tmp/src/
RUN sh -c "find /tmp/src/ ! -name 'pom.xml' -delete &> /dev/null"

FROM maven:3.6.2-jdk-8 AS mvn

WORKDIR /tmp/src/

# Cache only the project file
COPY --from=pom_files /tmp/src/ .

# Build & cache all dependencies
RUN mvn dependency:go-offline -B -Pdist

# Bring in the full project sources
COPY . .

RUN mvn -o -e -B clean package -Pdist -Dgit.shallow=true -DskipTests=true \
 && mkdir -p /oxalis/lib \
 && for f in $(ls target/oxalis-server/lib); do \
    if [ -e target/oxalis-standalone/lib/$f ]; then \
        mv target/oxalis-server/lib/$f /oxalis/lib/; \
        rm target/oxalis-standalone/lib/$f; \
    fi; \
 done \
 && mv target/oxalis-server/bin /oxalis/bin-server \
 && mv target/oxalis-server/lib /oxalis/lib-server \
 && mv target/oxalis-standalone/bin /oxalis/bin-standalone \
 && mv target/oxalis-standalone/lib /oxalis/lib-standalone \
 && sed "s|lib/\*|lib-server/*:lib/*|" /oxalis/bin-server/run.sh > /oxalis/bin-server/run-docker.sh \
 && sed "s|lib/\*|lib-standalone/*:lib/*|" /oxalis/bin-standalone/run.sh > /oxalis/bin-standalone/run-docker.sh \
 && chmod 755 /oxalis/bin-server/run-docker.sh /oxalis/bin-standalone/run-docker.sh \
 && mkdir /oxalis/bin /oxalis/conf /oxalis/ext /oxalis/inbound /oxalis/outbound /oxalis/plugin \
 && echo "#!/bin/sh\n\nexec /oxalis/bin-\$MODE/run-docker.sh \$@" > /oxalis/bin/run-docker.sh

FROM openjdk:8u212-jre-alpine3.9 as oxalis-base

COPY --from=mvn /oxalis /oxalis

ENV MODE server

FROM oxalis-base as oxalis

VOLUME /oxalis/conf /oxalis/ext /oxalis/inbound /oxalis/outbound /oxalis/plugin

EXPOSE 8080

WORKDIR /oxalis

ENTRYPOINT ["sh", "bin/run-docker.sh"]
