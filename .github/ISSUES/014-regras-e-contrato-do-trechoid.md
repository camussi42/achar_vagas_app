titulo: firestore.rules novas + teste de contrato do trechoid

o que mudou:

- `firestore.rules`: função `trechoIdValido` com o mesmo texto da regex do app
- `trechos`: leitura liberada para o cliente, escrita negada (a pipeline grava com o Admin SDK)
- `relatos`: valida `uid`, `tipo`, `geo.geopoint` (geopoint) e `criadoEm == request.time`
- `test/trecho_id_test.dart`: id do app (parse, faixa linear do lado de quadra, rejeições)
- `tools/pipeline/test_pipeline.py`: teste de contrato que lê os três arquivos e exige a mesma regex

como testar:

1. contrato (app x regras x pipeline): `python -m unittest discover -s tools/pipeline -v`
2. id no app: `flutter test test/trecho_id_test.dart`
3. regras no emulador:
	- `docker-compose up --build`
	- criar um relato com `trechoId` inválido (`gers:xpto`) e conferir que é rejeitado
	- criar um relato válido (login anônimo) e conferir `criadoEm` gravado pelo servidor
	- tentar escrever em `trechos` pelo cliente e conferir que é negado
