titulo: abrir rota até o trecho (geo: / google maps)

historia: como motorista, quero tocar um trecho e mandar a rota pro meu app de
mapas, pra chegar na vaga sem ficar rodando o quarteirão.

o que muda:

- `pubspec.yaml`: dependência nova `url_launcher` (as versões de `cloud_firestore`/`firebase_*` não mudam)
- `lib/services/rota.dart` (novo):
	- `uriRota(destino, rotulo, android)`: pura e testável — android usa `geo:lat,lng?q=lat,lng(rotulo)` (RFC 5870, quem atende é o app de mapas instalado) e web/desktop usam `https://www.google.com/maps/dir/?api=1&destination=lat,lng`
	- `RotaService` (interface) + `RotaUrlLauncher`: `canLaunchUrl`/`launchUrl` com `LaunchMode.externalApplication`; nenhuma falha vira exceção (`false` = sem app de mapas)
- `lib/ambiente.dart`: `AmbienteApp.rota` (padrão `RotaUrlLauncher`, então os testes existentes não mudam)
- `lib/ui/tela_mapa.dart`: `onIrAteAqui` ligado no detalhe e `_irAteOTrecho(camada)` — o destino é o ponto que a camada já tem (centroide da linha ou centro do círculo do fallback) e o rótulo é o nome da via; falha vira aviso na tela
- `lib/ui/detalhe_trecho.dart`: pedir a rota fecha a folha (o usuário sai para o app de mapas e o aviso aparece sobre o mapa)
- `android/app/src/main/AndroidManifest.xml`: `<queries>` com `VIEW` + `scheme=geo` (obrigatório no Android 11+ para consultar o esquema)
- `README.md`: comportamento por plataforma
- `test/rota_test.dart` (novo) e `test/tela_mapa_test.dart`

notas:

- esta issue (#36) é o código da #27 voltando para a `main`: o PR #32 (`feature/issue-27-abrir-rota`) foi mergeado em `feature/issue-26-detalhe-do-trecho` 17s depois da #26 entrar, então `lib/services/rota.dart`, o `url_launcher`, o wiring do botão e o `AndroidManifest` ficaram de fora (a base recuperada foi o merge `39433c6`)

como testar:

1. `flutter test test/rota_test.dart test/detalhe_trecho_test.dart test/tela_mapa_test.dart`
	- teste unitário: a URI/intent de um ponto conhecido (android e web/desktop), sem abrir nada
	- teste de widget: o duble de `RotaService` recebe o centroide e o nome da via; com `false` a tela mostra "Nenhum app de mapas disponível para abrir a rota."
2. `flutter analyze` (limpo)
3. no app: `docker-compose up --build`, abrir http://localhost:5000, tocar num trecho e usar "ir até aqui" (no web abre a rota no Google Maps em outra aba)
