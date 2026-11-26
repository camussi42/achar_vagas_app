titulo: CI: analyze + testes (flutter e pipeline) em todo PR

historia: como equipe, quero que PR quebrado nao entre na main, porque foi assim
que a #27 fechou sem o codigo estar na main. Hoje `flutter analyze`,
`flutter test` e `python -m unittest discover -s tools/pipeline` sao manuais,
na maquina de cada um: nada confere que "mergeado" e "rodando" sao a mesma
coisa.

o que muda:

- `.github/workflows/ci.yml` (novo): roda em `pull_request` e em `push` na
	`main`, com tres jobs independentes
	- `analyze`: `flutter analyze`
	- `testes flutter`: `flutter test` (a suite de `test/`; `test_emulador/`
		fica de fora de proposito e roda no workflow da #39)
	- `testes pipeline`: `python -m unittest discover -s tools/pipeline -v`
- `README.md`: badge do workflow ao lado do link do app publicado e a nota de
	que a CI roda as tres checagens em todo PR
- branch protection da `main`: exige os tres checks verdes para merge
	(configuracao no GitHub, nao no repositorio)

decisoes:

- tres jobs em vez de um: um teste quebrado nao esconde os outros (o analyze
	roda mesmo quando a suite falha, e o contrario tambem), e o check que a
	branch protection vira o nome do job
- `concurrency` com `cancel-in-progress`: push novo no mesmo PR cancela a
	rodada anterior, para o check que vale ser sempre o do ultimo commit
- `permissions: contents: read`: o workflow so le o repositorio
- `--enforce-lockfile` no `flutter pub get`: usa o `pubspec.lock` versionado e
	falha se ele precisaria mudar (mesmo achado do SonarCloud da #39)
- `subosito/flutter-action` pinada por SHA com a tag no comentario
	(`githubactions:S7637`), `actions/*` por tag (sao oficiais do GitHub)
- python `3.13` (a mesma dos `.pyc` da pipeline) via `actions/setup-python`;
	a suite e so stdlib, nao ha requirements para instalar
- o workflow das `firestore.rules` continua separado (#39): ele precisa de
	java e node por causa do emulador, este aqui so de flutter e python

como testar:

1. abrir um PR com um teste quebrado de proposito e ver o check vermelho
2. desfazer a quebra e ver o check verde
3. so depois merge: com a branch protection da `main` pedindo os tres checks,
	o botao de merge fica travado enquanto houver check vermelho
4. a badge no README acompanha o estado do workflow `ci` na `main`
