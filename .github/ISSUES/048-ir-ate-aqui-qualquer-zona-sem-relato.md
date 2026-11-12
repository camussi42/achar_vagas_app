titulo: "Ir até aqui" em qualquer zona/setor, mesmo sem relato

historia: como motorista, quero tocar em qualquer zona/setor do mapa (mesmo em
ruas sem relato recente) e usar o botão "Ir até aqui" para abrir a rota até
aquele ponto no app de mapas.

o que muda:

- `lib/ui/camadas_mapa.dart`: `combinar` agora inclui todos os trechos
  resolvidos da consulta (com ou sem relato), não apenas os que têm relato
  válido. Zonas sem relato ficam com estado `desconhecido` e são toque-áveis,
  mas não são pintadas com cor de relato (mantém o neutro na legenda). Cada
  zona ganha `mostrarBotaoIrAteAqui => true` para o botão de rota aparecer.
- `lib/ui/camadas_mapa.dart`: `TrechoEstado.mostrarBotaoIrAteAqui` novo getter
  que retorna sempre `true` — o botão "Ir até aqui" aparece em toda zona
  tocada, inclusive sem relato (issue #48).
- `lib/ui/tela_mapa.dart`: `_polylines` e `_circles` deixam de filtrar por
  `resumo.temRelato`, de modo que zonas sem relato são pintadas em neutro e
  continuam toque-áveis (hit target) para abrir o detalhe.
- `lib/ui/tela_mapa.dart`: `_abrirDetalheDe` abre o detalhe para qualquer zona
  tocada (com ou sem relato); o botão de rota fecha a folha antes de enviar o
  destino para o app de mapas.
- `lib/ui/detalhe_trecho.dart`: `mostrarDetalheTrecho` recebe `AmbienteApp`;
  `DetalheTrecho` mostra "Sem relato" quando `resumo.temRelato` é falso e o
  botão de rota fecha a folha antes de chamar `ambiente.rota.abrir`.
- `lib/ui/detalhe_trecho.dart`: `_abrirRota` abre a rota até o centro da zona
  tocada; se não houver app de mapas, mostra aviso na tela.
- `lib/ui/detalhe_trecho.dart`: `DetalheTrecho` recebe `AmbienteApp` para
  acessar `rota` sem depender de callback passado pela tela.
- `README.md`: tocar em qualquer zona (pintada ou não) abre o detalhe; o botão
  "Ir até aqui" aparece em qualquer zona/setor, até sem relato.
- `test/camadas_mapa_test.dart`: `combinar` agora devolve camada neutra para
  trecho sem relato (toque-ável, não pintada).
- `test/detalhe_trecho_test.dart`: novo teste de zona sem relato com botão de
  rota.
- `test/tela_mapa_test.dart`: novo teste "toque em uma zona sem relato mostra
  o detalhe com o botão de rota".

como testar:

1. `flutter test test/camadas_mapa_test.dart test/detalhe_trecho_test.dart test/tela_mapa_test.dart`
2. `flutter analyze` (limpo)
3. no app: `docker-compose up --build`, abrir http://localhost:5000, tocar em
   uma zona sem relato (círculo/linha neutra) e confirmar que o detalhe abre
   com "Sem relato" e o botão "Ir até aqui" abre a rota no app de mapas.
