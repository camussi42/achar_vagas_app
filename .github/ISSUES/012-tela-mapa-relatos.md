titulo: tela de mapa com relatos (flutter_map + gps)

o que muda:

- `lib/ui/tela_mapa.dart`: tela inicial com o mapa OSM (`flutter_map`), zoom/pan e centralizado no centro de Campo Mourao
- marcador da posicao atual e botao de localizacao: pede a permissao e centraliza no usuario (`geolocator`)
- botoes de relato (vaga / lotado / saindo); ao tocar, o trecho e resolvido pela cascata **overture (gers) -> geohash** (`lib/ambiente.dart` monta o `TrechoResolverCascata`)
- `lib/ambiente.dart`: grafo de dependencias do app (Firebase ao vivo ou modo demonstracao com os 40 trechos reais do centro)
- `lib/config.dart`: centro/zoom/raios do mapa e URL dos tiles do OSM
- `lib/ui/botoes_relato.dart`: os tres botoes, com as cores do estado
- `android/app/src/main/AndroidManifest.xml`: `ACCESS_FINE_LOCATION` e `ACCESS_COARSE_LOCATION`
- `lib/main.dart`: o home passa a ser o mapa (sai o texto de diagnostico do Firebase)
- ref #3 (continua o que ela pedia: mapa OSM sem chave de billing, permissao na primeira abertura e marcador)

como testar:

1. no app: `flutter test test/tela_mapa_test.dart test/widget_test.dart`
2. `docker-compose up --build` e abrir http://localhost:5000
	- mapa abre no centro de campo mourao, com zoom e pan
	- botao de localizacao pede permissao e centraliza (no web o GPS so funciona em contexto seguro: `http://localhost` ou HTTPS)
	- tocar em "tem vaga": o snackbar mostra o nome da via quando ela esta na malha, ou "area aproximada" quando a rua ainda nao foi importada
3. com Firebase/emulador configurado: o relato aparece na colecao `relatos` com `criadoEm` gravado pelo servidor
