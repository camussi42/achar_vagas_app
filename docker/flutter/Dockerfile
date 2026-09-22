# Ambiente Flutter (web) usado pelo docker-compose.
#
# A SDK vem do zip oficial, fixada por versao + sha256, porque as imagens
# prontas nao acompanham mais o projeto: `cirrusci/flutter` parou de ser
# atualizada em 2023 (Dart antigo) e `ghcr.io/cirruslabs/flutter` parou de
# receber imagens em 01/05/2026. O `pubspec.lock` exige `flutter >= 3.38.4`,
# entao a versao usada aqui fica explicita (e o hash e conferido no build).
FROM debian:bookworm-slim

ARG FLUTTER_VERSION=3.47.5
ARG FLUTTER_SHA256=2132e990f236f8d22e7c6314b29a191a95b10d7cbcfec9b4e2e303d996652cbb

ENV FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/app/.pub-cache

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Baixa o tar.xz oficial, confere o sha256, extrai em /opt/flutter e ja roda
# `flutter --version` (baixa o Dart/engine no build e valida a instalacao).
RUN curl -fsSL -o /tmp/flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
 && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --global --add safe.directory /opt/flutter \
 && flutter --version

# `bash -l` (entrypoint) reseta o PATH a partir do /etc/profile: os links em
# /usr/local/bin garantem que `flutter` e `dart` continuem sendo encontrados.
RUN ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter \
 && ln -sf /opt/flutter/bin/dart /usr/local/bin/dart

WORKDIR /app
EXPOSE 5000
ENTRYPOINT ["bash", "-lc", "flutter pub get && flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5000"]
