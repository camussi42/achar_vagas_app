titulo: ambiente de desenvolvimento com docker

como testar:

1. rodar `docker-compose up --build`
2. abrir http://localhost:5000 para o flutter web
3. checar emulador firestore em http://localhost:8080 e ui dos emuladores em http://localhost:4000

o que mudou (para o fluxo voltar a subir):

- `firebase.json` + `.firebaserc`: sem eles o `firebase emulators:start` do container
	não sabia qual projeto usar e o emulador não subia. O projeto do `.firebaserc` é
	`demo-achar-vagas` (prefixo `demo-` = 100% local, sem tocar no Firebase real) e as
	portas do `firebase.json` são as mesmas do `docker-compose.yml` (firestore 8080,
	auth 9099, ui 4000)
- `docker/flutter/Dockerfile`: passa a instalar a SDK oficial do Flutter (debian +
	tar.xz fixado em `FLUTTER_VERSION`/`FLUTTER_SHA256`), porque as imagens prontas
	pararam: `cirrusci/flutter` em 2023 e `ghcr.io/cirruslabs/flutter` em 01/05/2026.
	O `pubspec.lock` exige `flutter >= 3.38.4`, então a versão fica explícita
- `docker/firebase/Dockerfile`: `node:22-bookworm-slim` + `firebase-tools@15`, porque
	o `firebase-tools` 15 exige Node >= 20 (com `node:18` o `npm install -g` falhava)

notas:

- sem `firebase_options.dart` preenchido o app sobe em **modo demonstração** (trechos
	reais do centro de Campo Mourão + relatos em memória), que não precisa de emulador
- pendências do fluxo (resolvidas depois, nas issues #24 e #25): o container do
	emulador não usava `--import`/`--export-on-exit` (o `emulator-data/` não era
	aproveitado) e o app não era apontado para os emuladores
	(`useFirestoreEmulator`/`useAuthEmulator`)
