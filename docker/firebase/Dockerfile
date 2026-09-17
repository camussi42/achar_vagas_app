FROM node:18-bullseye-slim
RUN apt-get update && apt-get install -y openjdk-11-jre-headless curl ca-certificates && rm -rf /var/lib/apt/lists/*
RUN npm install -g firebase-tools
WORKDIR /workspace
EXPOSE 8080 9099 4000
CMD ["firebase", "emulators:start", "--only", "firestore,auth", "--host", "0.0.0.0"]
