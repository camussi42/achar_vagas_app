# escopo delimitado e criterios de pronto (v1)

este documento amarra o **fim** da primeira entrega do achar vagas. qualquer ideia que surgir a partir daqui entra com o label `pos-entrega` e **nao** entra no milestone `entrega-1`.

quando todas as issues do milestone fecharem e o checklist abaixo estiver verde, o app esta pronto pra apresentar no projeto integrador.

---

## 1. a historia principal (o caminho feliz)

o app esta "pronto" quando esse fluxo roda de ponta a ponta sem gambiarra:

1. o usuario abre o app (no navegador ou no celular)
2. o mapa abre centralizado na regiao atendida, mostrando a malha de quarteiroes (ruas canonicas do overture, nao linhas tortas)
3. trechos com relatos recentes (< 20 min) aparecem coloridos (verde = muitas vagas, amarelo = poucas, vermelho = sem vagas)
4. o usuario toca em um trecho verde e vê o detalhe ("visto ha X min")
5. o usuario clica em **"Ir ate aqui"** e o app abre a rota no seu app de navegacao (ou no google maps)
6. ao chegar ou sair da vaga, o usuario toca num dos 3 botoes ("muitas", "poucas", "sem vaga") e o trecho onde ele esta atualiza a cor para todo mundo em tempo real

se isso funciona na versao publicada, o objetivo do projeto integrador esta cumprido.

---

## 2. criterios de pronto do app (checklist)

- [ ] **malha real no ar**: a colecao `trechos` esta populada na base real do firestore com a pipeline do overture (nao depende de emulador)
- [ ] **abrir rota funcionando**: tocar em "Ir ate aqui" no detalhe do trecho abre o app de mapas (#36)
- [ ] **sem spam**: um usuario nao consegue floodar o mesmo trecho com relatos conflitantes dentro da janela (#38)
- [ ] **feedback de conexao**: o usuario sabe quando o app esta sem rede ou em modo offline/demo (#29)
- [ ] **regras seguras e testadas**: suite automatizada no emulador garantindo que escrita sem login, com data falsa ou fora da tolerancia e negada (#39)
- [ ] **CI verde**: todo PR roda `flutter analyze`, `flutter test` e testes da pipeline antes do merge (#40)
- [ ] **v1 publicada**: hosting no ar com build web funcional, firestore.rules publicadas e TTL de 20 min ativo (#37)

---

## 3. o que esta FORA desta entrega (vai pra `pos-entrega`)

para nao esticar o escopo infinitamente, os seguintes itens **nao** impedem a entrega:

- autenticacao com email/senha ou login social (o anonymous auth ja atende o requisito de ter `uid`)
- historico pessoal de relatos do usuario
- navegacao curva-a-curva dentro do proprio app (delegamos pro maps/waze)
- notificacoes push de vagas abrindo
- algoritmo estatistico/preditivo de vagas por horario
- suporte a outras cidades alem da regiao piloto
- cadastro manual de novos trechos pela interface

---

## 4. issues do milestone `entrega-1`

| # | titulo | papel no encerramento |
|---|---|---|
| #29 | avisar quando o app esta em modo demonstracao/sem conexao | robustez da UI |
| #36 | abrir rota: trazer o ir ate aqui de volta para a main (#27) | fecha o fluxo do motorista |
| #37 | publicar a v1: hosting, regras/indices e semente de trechos | entrega do software no ar |
| #38 | um relato por usuario por trecho (anti-spam no mapa) | integridade dos dados |
| #39 | testes das firestore.rules no emulador | seguranca comprovada |
| #40 | CI: analyze + testes (flutter e pipeline) em todo PR | garantia de integridade |
