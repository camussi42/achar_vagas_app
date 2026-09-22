titulo: estado por trecho no mapa (cor por relatos recentes)

o que muda:

- `lib/models/estado_trecho.dart`: `validadeRelatoPadrao` (20 min), usada no calculo das cores
- `lib/ui/camadas_mapa.dart`: regra pura do que pintar (`combinar`, `pontosMaisRecentes`) — trecho canonico com geometria vira linha; canonico sem geometria vira circulo de 30 m no ponto relatado; fallback geohash vira circulo no centro da celula
- `lib/ui/paleta_estado.dart`: verde (vaga), vermelho (lotado), laranja (saindo) e neutro
- `lib/ui/legenda_estado.dart`: legenda na tela, inclusive do neutro (que nao e pintado no mapa)
- `lib/ui/tela_mapa.dart`: `PolylineLayer` e `CircleLayer` recalculados a cada evento de relato, a cada minuto (relato que vence) e a cada troca de area
- decisao registrada: trecho **sem** relato valido nao e desenhado; o estado neutro fica apenas na legenda

como testar:

1. `flutter test test/estado_trecho_test.dart test/camadas_mapa_test.dart test/tela_mapa_test.dart`
2. `docker-compose up --build` e abrir http://localhost:5000
	- relatar "tem vaga" no centro de campo mourao: o trecho fica verde
	- relatar "lotado" no mesmo trecho depois: a cor passa a vermelho (o relato mais recente manda)
	- esperar a validade de 20 min (ou reduzir `validadeRelatoPadrao` num teste): a cor volta ao neutro
	- em rua fora da malha importada: aparece circulo colorido na area aproximada, nao uma linha
