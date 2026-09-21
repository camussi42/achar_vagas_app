titulo: dividir trechos nas esquinas (lado de quadra)

o que mudou:

- `tools/pipeline/export_trechos.py`: a divisão nos conectores passou a ser o **padrão** do export
	- `--nao-dividir-nos-conectores` mantém a rua inteira (o antigo `--dividir-nos-conectores` continua aceito)
	- a chave do documento fica `gers:<id>@<start_lr>:<end_lr>` (4 casas); quem absorve conectores muito próximos é `--min-metros-trecho`
	- trecho sem esquina no meio (sem conector entre as pontas) continua com a chave simples `gers:<id>`, para a identidade não mudar com a divisão
- `tools/pipeline/trechos.py` e `README.md`: documentação do sufixo

como testar:

1. `python -m unittest discover -s tools/pipeline -v` (cobre a divisão e o recorte)
2. gerar com um GeoJSON de teste e conferir o sufixo por linha:

```bash
python tools/pipeline/export_trechos.py --geojson cm.geojson --out trechos.ndjson
head -3 trechos.ndjson   # id termina em @<lr>:<lr>
```

3. na prática: relato na quadra A não pinta a quadra do outro lado da esquina (a chave é diferente)
