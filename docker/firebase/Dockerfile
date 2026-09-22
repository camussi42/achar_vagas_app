# Emulador do Firestore/Auth usado pelo docker-compose.
#
# Node 22: o firebase-tools 15 exige Node >= 20 (com node:18 o `npm install -g`
# falhava). O JRE continua necessario porque o emulador do Firestore roda em Java.
FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openjdk-17-jre-headless curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g firebase-tools@15

WORKDIR /workspace
EXPOSE 8080 9099 4000
CMD ["firebase", "emulators:start", "--only", "firestore,auth", "--host", "0.0.0.0"]
