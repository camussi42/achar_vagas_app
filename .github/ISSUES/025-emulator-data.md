titulo: reaproveitar os dados do emulador (--import/--export-on-exit)

o que muda:

- `docker/firebase/Dockerfile`: o comando passa a ser `firebase emulators:start --only firestore,auth --host 0.0.0.0 --import=./emulator-data --export-on-exit=./emulator-data`
	- o firebase-tools exporta na saída limpa dele (o SIGINT do ctrl+c), então entra `STOPSIGNAL SIGINT`: é ele que faz o `docker stop`/`docker-compose down` exportar em vez de matar o container sem gravar nada
- `docker-compose.yml`: `stop_grace_period: 30s` no serviço do firebase, para o export terminar antes do kill (o padrão de 10s pode cortar o processo)
- `emulator-data/.gitkeep` (novo) + `.gitignore`: a pasta precisa existir para o `--import`, então ela é versionada vazia e só o conteúdo (o export) fica fora do git
- `README.md`: o que persiste e como limpar de verdade

decisões:

- `--export-on-exit` só roda na saída limpa, então o sinal do container passa a ser o mesmo que o firebase-tools trata (SIGINT) em vez de confiar no SIGTERM
- a limpeza de verdade é apagar `emulator-data/` menos o `.gitkeep`: o compose usa bind mount, então nem `docker-compose down -v` remove a pasta

como testar:

1. `docker-compose up -d firebase`
2. semear trechos (`python tools/pipeline/semear_firestore.py --arquivo trechos.ndjson --limpar`) e criar um relato pelo app
3. `docker-compose down` e `docker-compose up -d firebase`
4. conferir em http://localhost:4000 (Firestore) que `trechos` e `relatos` continuam lá
5. `git status` limpo (a pasta não aparece)
