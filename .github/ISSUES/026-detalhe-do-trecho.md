titulo: detalhe do trecho ao tocar no mapa

o que muda:

- `lib/ui/camadas_mapa.dart`: `trechoTocado(camadas, valoresTocados)` — regra pura que escolhe o trecho a partir dos ids que voltam do hit test do toque (id desconhecido é ignorado, sem derrubar a tela)
- `lib/ui/detalhe_trecho.dart` (novo): `DetalheTrecho` e `mostrarDetalheTrecho` — folha com a via (ou "Área aproximada (~N m)" no fallback), o estado com a cor, quantos relatos válidos o trecho tem (com a quebra por tipo) e a idade do relato mais recente (`idadeLegivel`)
	- o botão de rota só aparece quando a tela passa `onIrAteAqui`: é o ponto de extensão da issue "abrir rota até o trecho"
- `lib/ui/tela_mapa.dart`: `hitValue` = id do trecho nas polylines e nos círculos, um `LayerHitNotifier` por camada e cada camada embrulhada em um `GestureDetector` (a camada só se declara acertada quando um trecho é tocado, então tocar no mapa vazio não abre nada)
- decisão registrada: o detalhe sai de `combinar`/`TrechoEstado`, o mesmo cálculo que pinta o mapa — nenhuma consulta nova ao firestore

como testar:

1. `flutter test test/camadas_mapa_test.dart test/detalhe_trecho_test.dart test/tela_mapa_test.dart`
2. com docker: `docker-compose up --build` e abrir http://localhost:5000
	- relatar "tem vaga" e tocar na linha verde: abre o detalhe com a via, o estado, a contagem e a idade do relato
	- relatar numa rua fora da malha e tocar no círculo: o rótulo é "Área aproximada (~N m)"
	- tocar (ou arrastar) no mapa vazio: nada abre
