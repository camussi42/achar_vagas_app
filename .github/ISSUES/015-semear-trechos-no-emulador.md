titulo: semear trechos da overture no firestore (docker-compose)

o que mudou:

- `tools/pipeline/semear_firestore.py`: lê o NDJSON da pipeline e grava a coleção `trechos` com o Admin SDK
	- `FIRESTORE_EMULATOR_HOST` (padrão `localhost:8080`) apontando para o `firebase` do docker-compose
	- grava em lotes de 500 (`--limpar` apaga a semente antiga antes)
- `README.md`: comando para rodar export + semeadura de uma vez

como testar:

1. `docker-compose up --build`
2. `python tools/pipeline/export_trechos.py --geojson cm.geojson --out trechos.ndjson`
3. `python tools/pipeline/semear_firestore.py --arquivo trechos.ndjson --limpar`
4. conferir em http://localhost:4000 → Firestore → `trechos` (id no formato `gers:<id>` ou `gers:<id>@<lr>:<lr>`)
5. testes locais (sem rede): `python -m unittest discover -s tools/pipeline -v`
