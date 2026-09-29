titulo: testes das firestore.rules no emulador (rules engine de verdade)

historia: como equipe, quero prova automatica de que ninguem grava relato em
nome de outro nem escolhe o proprio prazo de validade.

o que muda:

- `test_emulador/` (novo, **fora de `test/`** de proposito): suite que roda as
	`firestore.rules` no emulador, com o rules engine avaliando cada gravacao
	- `regras_firestore_test.dart`: os casos das regras (lista abaixo)
	- `apoio/emulador_firestore.dart`: cliente REST minimo dos emuladores —
		login anonimo (`accounts:signUp`) e `:commit`/`GET` no firestore, que sao
		as mesmas chamadas que o SDK faz por baixo; o `criadoEm` do servidor vai
		como transformacao (`updateTransforms` + `REQUEST_TIME`), o formato do
		`FieldValue.serverTimestamp()`
	- `apoio_emulador_test.dart`: o que da para conferir sem emulador (formato
		das escritas e enderecos); roda com `flutter test`
- `.github/workflows/regras-firestore.yml` (novo): roda a suite com
	`firebase emulators:exec --only firestore,auth "flutter test test_emulador"`
	em `pull_request` e em `push` na `main`
- `README.md`: como rodar, o que a suite cobre e como conferir que ela pega uma
	regra afrouxada

o que a suite cobre:

- criacao de relato
	- aceita o que o app grava (documento montado por `Relato.novo`, os mesmos
		campos de `RelatosFirestore.criar`) e confere que o `criadoEm` gravado e o
		horario do servidor
	- aceita trecho canonico (`gers:<uuid>`) e lado de quadra (`@0.5000:1.0000`)
	- aceita `expiraEm` a 30s de `request.time + 20 min` (os dois lados da
		tolerancia de 1 min)
	- `uid` de outro usuario, `uid` inventado e relato sem `uid`
	- `tipo` fora de `vaga/lotado/saindo` e sem `tipo`
	- `trechoId` inventado (`gers:xpto`, `gers:<uuid>@0.5`, sem prefixo,
		`gh:` com 10 caracteres, com espaco na frente) e sem `trechoId`
	- `geo` sem geopoint/geohash/geohashConsulta, geopoint como texto e como
		lista, e relato sem `geo`
	- `expiraEm` uma hora depois, dois minutos depois e ja vencido
	- `expiraEm`/`criadoEm` como texto e relato sem `expiraEm`
	- `criadoEm` do relogio do aparelho (antes, igual e depois do horario do
		servidor): o relogio do cliente nunca casa com `request.time`
	- gravacao sem login
- leitura
	- `relatos` sem login toma 403; com login le o documento (inclusive o de
		outro usuario: a regra e so `request.auth != null`)
	- `trechos` e legivel sem login
- escrita em `trechos` pelo cliente: negada logado e negada anonima
- `update` e `delete` de relato do proprio usuario: negados, e o documento
	continua intacto

decisoes:

- a suite fica fora de `test/`: `flutter test` (suite completa, sem docker)
	precisa continuar passando, e uma suite que passa **sem** emulador nao prova
	nada sobre as regras. Sem emulador no ar a suite falha com a instrucao de
	como subir, e o `emulators:exec` derruba o job quando o emulador nao sobe
- REST em vez do SDK: `flutter test` roda na VM do Dart, onde os plugins do
	firebase nao tem canal de plataforma; as duas chamadas usadas sao as mesmas
	que o SDK manda na rede
- `--only firestore,auth`: as regras dependem de `request.auth.uid`, e quem
	emite o token e o emulador do auth (so o emulador do firestore nao tem login)
- negativa das regras e afirmada como 403 `PERMISSION_DENIED`, e nao so "nao
	passou": assim um payload errado (400) nao se passa por negativa
- a suite limpa o que criou no `tearDownAll` (o `emulator-data/` do compose e
	reaproveitado entre execucoes)
- o job de CI que precisa de emulador entra aqui; o CI de `flutter analyze`,
	`flutter test` e pipeline e a issue #40 (outro workflow)

notas:

- os testes complementam o teste de contrato do `trechoId`
	(`tools/pipeline/test_pipeline.py`): aquele so compara o **texto** da regex
	entre app, regras e pipeline, sem rodar o rules engine
- a `firestore.rules` nao mudou nesta issue

como testar:

1. `docker-compose up -d firebase` e `flutter test test_emulador`
	- ou tudo junto, sem docker:
		`firebase emulators:exec --only firestore,auth "flutter test test_emulador"`
2. afrouxar uma regra de proposito (por exemplo aceitar `expiraEm` em 1 hora) e
	rodar de novo: o caso `expiraEm uma hora depois (prazo escolhido pelo
	cliente)` falha com "devia ser recusado pelas regras; veio HTTP 200";
	desfazer e ver verde
3. `flutter test` (suite completa) e `flutter analyze` continuam passando sem
	emulador nenhum
