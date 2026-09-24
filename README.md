
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

## modo demonstracao (sem firebase)

sem `firebase_options` preenchido (via `flutterfire configure`) o app sobe com os **40 trechos reais** do centro de Campo Mourao (`lib/data/trechos_demo_gerado.dart`) e relatos em memoria: da para navegar e ver as cores funcionando sem nenhum servico externo.

- avisos na tela (issue #29): sempre que o app esta sem backend aparece uma **faixa** no topo do mapa — `modo demonstração: relatos locais, sem backend` + o motivo que o `bootstrapFirebase` registrou (`MotivoSemFirebase`, em `lib/ambiente.dart`): `firebase_options` vazio, `initializeApp` sem conexão ou auth anônimo recusado
- falha de leitura em tempo de execução (stream de relatos ou consulta de trechos) também vira faixa: o mapa continua útil, só avisa que os relatos podem estar desatualizados; a faixa sai quando os dados voltam
- `lib/ui/faixa_aviso.dart` concentra as faixas: e aviso, nao tela de erro
- `lib/ambiente.dart` monta as dependencias (firebase ou demonstracao) e `lib/config.dart` guarda centro, zoom, raios e a URL dos tiles
- a tela so conversa com as interfaces de `lib/services/`, por isso os testes rodam sem rede, sem GPS e sem Firebase

## como testar o mapa

```bash
flutter test          # geohash, trechoId, estado por trecho, camadas, tela do mapa, bootstrap e faixas
flutter analyze
```

- com docker: `docker-compose up --build` e abrir http://localhost:5000
	- no web o navegador so entrega GPS em contexto seguro (`http://localhost` ou HTTPS)
	- relatar "tem vaga" no centro: o trecho fica verde por 20 min; relatar "lotado" depois muda a cor (o relato mais recente manda)
	- em rua fora da malha importada aparece um circulo na area aproximada, em vez de linha
	- modo demonstracao: rode sem `firebase_options` preenchido e confira a faixa "modo demonstração" no topo do mapa
	- sem conexao em tempo de execucao: com o app aberto e o emulador no ar, pare o backend (`docker-compose stop firebase`) e confira a faixa de relatos desatualizados

## regras do firestore

- `firestore.rules`:
	- `trechos`: leitura liberada para o cliente, escrita negada (quem grava é a pipeline, via Admin SDK)
	- `relatos`: `uid` do próprio usuário, `tipo` conhecido, `geo.geopoint` como geopoint e `criadoEm == request.time` (servidor)
	- o formato do `trechoId` é o **mesmo texto** no app (`lib/geo/trecho_id.dart`), nas regras (função `trechoIdValido`) e na pipeline (`tools/pipeline/trechos.py`); o teste de contrato falha se algum dos três mudar sozinho

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


