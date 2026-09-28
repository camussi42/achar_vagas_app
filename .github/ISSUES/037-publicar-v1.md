titulo: publicar a v1 (hosting, regras/indices e semente no projeto real)

historia: como quem vai avaliar o trabalho, quero abrir o app por uma URL e ver
o mapa com as ruas de verdade, sem precisar rodar docker.

o que muda:

- `firebase.json`: secao `hosting` nova apontando para `build/web` (o site do
	`flutter build web --release`); `firestore` e `emulators` nao mudam
- `tools/pipeline/semear_firestore.py`: flag `--credenciais` (json de service
	account) + funcao `cliente_producao` — com a flag o seeder grava no firestore
	real e ignora `FIRESTORE_EMULATOR_HOST`; sem a flag o comportamento e o de
	sempre (emulador). O import do Admin SDK virou `importar_admin_sdk` (usado
	pelos dois caminhos)
- `.gitignore`: a chave de service account (`*-firebase-adminsdk*.json`,
	`service-account*.json`) nunca vai para o git
- `README.md`: secao "publicar a v1", do zero ate a URL (login,
	`flutterfire configure`, build, deploy, semente com `--credenciais` e o TTL
	com gcloud)
- `tools/pipeline/test_pipeline.py`: a CLI aceita `--credenciais` e a chave
	precisa existir no disco

notas:

- o deploy em si (criar o projeto, `firebase login`, `firebase deploy`, semear
	e ligar o TTL) e feito na maquina de quem tem acesso ao Firebase: os
	comandos estao na secao "publicar a v1" do README, e a URL publicada deve ser
	preenchida la depois do primeiro deploy
- o TTL de `expiraEm` segue sendo o `gcloud firestore fields ttls update` ja
	citado na secao da issue #28 (so ganha o passo explicito no fluxo de
	publicacao); nao roda no emulador de nenhuma forma
- `firestore.indexes.json` vira obrigatorio no projeto real: sem o indice
	`geo.geohashConsulta` + `criadoEm` a consulta de relatos quebra no deploy
	(no emulador ele era aplicado junto com o `firebase emulators:start`)

como testar:

1. `python -m unittest discover -s tools/pipeline -v` (testes da CLI do seeder)
2. seguir a secao "publicar a v1" do README ate a URL e abrir o site: o mapa
	pinta os trechos semeados (linhas da via, nao circulos)
3. criar um relato pelo app publicado e conferir no console que ele some da
	consulta em ~20 min
