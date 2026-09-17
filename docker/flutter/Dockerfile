FROM cirrusci/flutter:stable
WORKDIR /app
EXPOSE 5000
ENTRYPOINT ["bash", "-lc", "flutter pub get && flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5000"]
