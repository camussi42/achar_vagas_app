titulo: relatos antigos: janela de consulta + orderBy e limpeza com TTL

o que muda:

- `lib/models/relato.dart`: `validadeRelatoPadrao` passa a morar junto do relato e o getter `expiraEm` (`criadoEm + validade`) é o valor gravado no firestore; `lib/models/estado_trecho.dart` só recebe o prazo por parâmetro
- `lib/services/relatos_repository.dart`:
	- `criar` grava `expiraEm` (alvo da política de TTL)
	- `_consulta` passa a cortar pela janela (`inicioJanelaRelatos` = agora - validade - 1 min de folga) e a ordenar por `criadoEm desc`, mantendo o `whereIn` nas células de geohash e o `limit`; sem isso o limite podia ser todo consumido por relatos antigos do mesmo geohash e um relato novo do mesmo trecho ficava de fora
	- o filtro fino de distância/validade continua no cliente
- `firestore.rules`: no `create`, `expiraEm` é obrigatório e precisa ficar a menos de 1 min de `request.time + 20 min`
	- decisão registrada: a igualdade exata com `request.time + duration.value(20, 'm')` **não** é satisfazível por um cliente (o SDK não lê `request.time` nem soma duração a um `serverTimestamp`, e o projeto não usa Cloud Functions), então a regra usa a janela de tolerância — que é o que impede o cliente de escolher o próprio prazo
- `firestore.indexes.json` (novo) + `firebase.json`: índice composto `geo.geohashConsulta` + `criadoEm`, referenciado pelo `firebase.json` (emulador e produção) e publicado com `firebase deploy --only firestore:indexes`
- `test/relatos_repository_test.dart` (novo): consulta real no `FakeFirebaseFirestore` (dev dependency `fake_cloud_firestore`, sem rede e sem emulador)
- `README.md`: janela, índice e TTL

como testar:

1. `flutter test test/relatos_repository_test.dart`
	- limite cheio de relatos antigos no mesmo geohash e um relato novo do mesmo trecho continua aparecendo e pintando
	- relato fora da janela não volta; a ordem é do mais recente para o mais antigo; o filtro de distância continua no cliente
	- `criar` grava `expiraEm` = `criadoEm` (servidor) + 20 min
2. `flutter test` (suíte completa) e `flutter analyze`
3. `python -m unittest discover -s tools/pipeline -v` continua passando (contrato do `trechoId` intocado)
4. no emulador: criar um relato antigo pela UI (http://localhost:4000) e conferir que o mapa só pinta os relatos válidos; a política de TTL é configurada no projeto (console/gcloud), não no emulador
