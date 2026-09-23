
# Aplicação para busca de vagas de estacionamento nos grandes centros urbanos.

**Otávio Camussi Tomaz**

**Samuel Sena Rosa**

**André Alevato Micheletti**

***

Trabalho referente à disciplina de Projeto Integrador

Prof.° Reginaldo Ré




## Proposta inicial

*"Gostaria de desenvolver um aplicativo de mobilidade urbana focado em estacionamento. O objetivo principal é ajudar motoristas a encontrarem e navegarem até vagas de carro disponíveis em tempo real, reduzindo o tempo de busca e o trânsito. Pensei em uma espécie de mapa, onde o usuário abre o app, vê sua localização atual e os pontos de estacionamento ao redor. Penso que teria que ter um Indicador de Disponibilidade: As áreas mudam de cor (ex: Verde = vagas, Vermelho = Lotado). E por último, penso que deveria apontar rotas: O usuário clica na vaga desejada e o app abre a rota usando o GPS (como Waze ou Google Maps)."*

## docker - ambiente de desenvolvimento 


- constrói e sobe os serviços (flutter web + emulador do firebase):

```bash
docker-compose up --build
```

- depois disso:
	- flutter web: http://localhost:5000
	- emulador firestore: http://localhost:8080
	- ui dos emuladores: http://localhost:4000

- notas úteis:
	- os arquivos docker estão em docker/ e o compose na raiz (docker-compose.yml)
	- dados do emulador são gravados em emulator-data/ para persistência entre execuções
	- parar: ctrl+c no terminal ou `docker-compose down`
	- se mudar dependências e quiser forçar rebuild: `docker-compose up --build --force-recreate`
	- caso o container flutter abra problemas, rode `flutter pub get` localmente ou inspecione os logs do container

## mapa, gps e relatos (issues #3, #12 e #13)

a tela inicial e o mapa (OpenStreetMap via `flutter_map`), centralizado no centro de Campo Mourao:

- zoom e pan no mapa (rotacao desligada) e atribuicao do OSM na tela
- botao de localizacao: pede a permissao, marca a sua posicao e centraliza o mapa
- botoes de relato (vaga / lotado / saindo): o app resolve o trecho pela cascata **overture (gers) -> geohash** e grava o relato (colecao `relatos` no Firestore, ou em memoria sem Firebase)
- estado por trecho: verde = tem vaga, vermelho = lotado, laranja = liberando vaga; relatos valem **20 min** e o mais recente manda
	- trecho canonico vira **linha** (polyline) com a geometria da base
	- fallback geohash vira **circulo** no centro da celula de ~150 m
	- trecho sem relato recente **nao** e pintado (a legenda na tela mostra a cor neutra)
- a permissao de localizacao e pedida ja na abertura; sem permissao o mapa continua em Campo Mourao e so o botao de localizacao avisa

## detalhe do trecho ao tocar no mapa (issue #26)

tocar num trecho pintado (linha verde/vermelha ou circulo da area aproximada) abre uma folha com o que o mapa ja calculou:

- nome da via (ou `area aproximada (~N m)` no fallback geohash) e o estado atual com a cor correspondente
- quantos relatos validos o trecho tem (com a quebra vaga / lotado / liberando) e ha quanto tempo foi o relato mais recente
- o toque usa o hit test das camadas do `flutter_map` (`hitValue`/`hitNotifier` com o id do trecho): tocar no mapa vazio nao abre nada
- nenhuma consulta nova ao firestore: os dados saem de `combinar` (`lib/ui/camadas_mapa.dart`), o mesmo calculo que pinta o mapa
- o botao de rota da folha so aparece quando a tela informa o callback (ponto de extensao da issue "abrir rota ate o trecho")

## modo demonstracao (sem firebase)

sem `firebase_options` preenchido (via `flutterfire configure`) o app sobe com os **40 trechos reais** do centro de Campo Mourao (`lib/data/trechos_demo_gerado.dart`) e relatos em memoria: da para navegar e ver as cores funcionando sem nenhum servico externo.

- `lib/ambiente.dart` monta as dependencias (firebase ou demonstracao) e `lib/config.dart` guarda centro, zoom, raios e a URL dos tiles
- a tela so conversa com as interfaces de `lib/services/`, por isso os testes rodam sem rede, sem GPS e sem Firebase

## como testar o mapa

```bash
flutter test          # geohash, trechoId, estado por trecho, camadas, detalhe e tela do mapa
flutter analyze
```

- com docker: `docker-compose up --build` e abrir http://localhost:5000
	- no web o navegador so entrega GPS em contexto seguro (`http://localhost` ou HTTPS)
	- relatar "tem vaga" no centro: o trecho fica verde por 20 min; relatar "lotado" depois muda a cor (o relato mais recente manda)
	- em rua fora da malha importada aparece um circulo na area aproximada, em vez de linha

## regras do firestore

- `firestore.rules`:
	- `trechos`: leitura liberada para o cliente, escrita negada (quem grava é a pipeline, via Admin SDK)
	- `relatos`: `uid` do próprio usuário, `tipo` conhecido, `geo.geopoint` como geopoint, `criadoEm == request.time` (servidor) e `expiraEm` a menos de 1 min de `request.time + 20 min` (o campo do TTL, ver abaixo)
	- o formato do `trechoId` é o **mesmo texto** no app (`lib/geo/trecho_id.dart`), nas regras (função `trechoIdValido`) e na pipeline (`tools/pipeline/trechos.py`); o teste de contrato falha se algum dos três mudar sozinho

## relatos antigos: janela, indice e TTL (issue #28)

- a consulta de relatos (`lib/services/relatos_repository.dart`) usa `whereIn` nas células de geohash **mais** uma janela de tempo (`criadoEm >= agora - 20 min - 1 min`, `inicioJanelaRelatos`) e `orderBy('criadoEm', descending: true)` com `limit`: sem isso o limite podia ser preenchido por relatos antigos do mesmo geohash e um relato novo do mesmo trecho ficava de fora (o mapa parava de pintar o que deveria)
	- a folga de 1 min cobre a diferença entre o relógio do aparelho e o horário do servidor gravado em `criadoEm`; o filtro fino de distância e de validade continua no cliente, que é quem decide o que pintar
	- filtro + ordem no servidor pedem o índice composto declarado em `firestore.indexes.json` (`geo.geohashConsulta` + `criadoEm`, referenciado no `firebase.json` e usado pelo emulador e pela produção); publicar com `firebase deploy --only firestore:indexes`
- cada relato grava `expiraEm` (criadoEm + 20 min) e a coleção `relatos` usa esse campo na política de **TTL** do firestore, para o servidor apagar sozinho o histórico:
	- configura uma vez por projeto: console (Databases → Time-to-live → `relatos` / `expiraEm`) ou `gcloud firestore fields ttls update expiraEm --collection-group=relatos`
	- a exclusão é assíncrona (não acontece no minuto do vencimento) e **não** roda no emulador: quem garante que o mapa só pinte relato válido é a consulta/janela no cliente
	- o SDK do cliente não lê `request.time` nem soma duração a um `serverTimestamp`, então `expiraEm` sai do relógio do aparelho; as regras aceitam só o que fica a menos de 1 min de `request.time + 20 min`, o que impede um cliente de escolher o próprio prazo (ou um "nunca expira")

### como testar (issue #28)

1. `flutter test test/relatos_repository_test.dart` — limite cheio de relatos antigos no mesmo geohash e um relato novo do mesmo trecho continua aparecendo e pintando
2. com o emulador: `docker-compose up --build`, criar um relato antigo pela UI (http://localhost:4000 → `relatos`, com `criadoEm` no passado e `geo.geohashConsulta` de uma célula do centro) e conferir que o mapa só pinta os relatos dentro da validade
3. `python -m unittest discover -s tools/pipeline -v` continua passando (o contrato do `trechoId` não mudou)


## pipeline de trechos (overture) e semeadura no emulador

- a pipeline corta cada segmento nos conectores por padrão, então cada trecho é **um lado de quadra**
  (chave `gers:<id>@<start_lr>:<end_lr>`); trecho sem esquina no meio continua com a chave simples
  `gers:<id>` e `--nao-dividir-nos-conectores` mantém sempre a rua inteira

```bash
# 1) gera o NDJSON com os trechos (baixa do Overture; precisa de `pip install overturemaps`)
python tools/pipeline/export_trechos.py --out trechos.ndjson

# ou reaproveitando um GeoJSON já baixado
python tools/pipeline/export_trechos.py --geojson cm.geojson --out trechos.ndjson
```

```bash
# 2) sobe o emulador e semeia a coleção `trechos` (Admin SDK, em lotes de 500)
docker-compose up -d firebase
python tools/pipeline/semear_firestore.py --arquivo trechos.ndjson --limpar
```

- o seeder precisa de `pip install google-cloud-firestore` e aponta para o emulador via `FIRESTORE_EMULATOR_HOST`:
	- PowerShell: `$env:FIRESTORE_EMULATOR_HOST = "localhost:8080"`
	- bash: `export FIRESTORE_EMULATOR_HOST=localhost:8080`
	- de dentro do container o host é o nome do serviço: `firebase:8080`
- conferir os documentos em http://localhost:4000 (UI do emulador) → Firestore → `trechos`
- testes da pipeline (geohash, recorte por esquina e contrato app/rules/pipeline):

```bash
python -m unittest discover -s tools/pipeline -v
```


