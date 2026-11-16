titulo: app apontado para os emuladores (auth + firestore)

o que muda:

- `lib/bootstrap.dart`:
	- `configuracaoEmulador()` lê as dart-defines do build: `USAR_EMULADOR` (sem a flag nada muda) e `HOST_EMULADOR` (padrão `localhost`; host em branco volta para o padrão)
	- com a flag ligada, o `bootstrapFirebase` chama `FirebaseAuth.instance.useAuthEmulator(host, 9099)` e `FirebaseFirestore.instance.useFirestoreEmulator(host, 8080)` antes do `signInAnonymously` — sem isso o app lia/escrevia no firebase de verdade mesmo com o emulador de pé
	- `opcoesEmuladorLocal`: com a flag ligada o `firebase_options.dart` é ignorado e o app usa o projeto `demo-achar-vagas` (o do `.firebaserc` e do `semear_firestore.py`), porque o emulador não valida chave e é nesse projectId que a semente de `trechos` fica; `PROJETO_EMULADOR` troca o projeto
	- portas fixadas em `portaEmuladorAuth` (9099) e `portaEmuladorFirestore` (8080), iguais às do `firebase.json`/`docker-compose.yml`
- `docker/flutter/Dockerfile`: o `flutter run` do container sobe com `--dart-define=USAR_EMULADOR=true --dart-define=HOST_EMULADOR=localhost`
- `test/emulador_test.dart` (novo): flag/host padrão, host em branco e o contrato com `firebase.json`, `docker-compose.yml`, `.firebaserc` e os dois Dockerfiles
- `README.md`: seção do modo emulador

decisões:

- de dentro do navegador o host é `localhost` e não `firebase` (o nome do serviço só existe na rede do compose)
- no emulador do android o `localhost` vira `10.0.2.2` pelo host mapping do próprio SDK (`automaticHostMapping`), então não precisa de host diferente por plataforma
- sem a flag o `bootstrapFirebase` continua idêntico (demonstração sem `firebase_options`, firebase real em release)

como testar:

1. `flutter test test/emulador_test.dart`
2. `docker-compose up --build` e abrir http://localhost:5000
3. relatar "tem vaga": o documento aparece em `relatos` na UI do emulador (http://localhost:4000) com `criadoEm` do servidor, e **não** no firebase real
4. `flutter test` continua passando (nenhum teste sobe emulador)
