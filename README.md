
# Aplicação para busca de vagas de estacionamento nos grandes centros urbanos.

**Otávio Camussi Tomaz**

**Samuel Sena Rosa**

**André Alevato Micheletti**

***

Trabalho referente à disciplina de Projeto Integrador

Prof.° Reginaldo Ré




## Proposta inicial

*"Gostaria de desenvolver um aplicativo de mobilidade urbana focado em estacionamento. O objetivo principal é ajudar motoristas a encontrarem e navegarem até vagas de carro disponíveis em tempo real, reduzindo o tempo de busca e o trânsito. Pensei em uma espécie de mapa, onde o usuário abre o app, vê sua localização atual e os pontos de estacionamento ao redor. Penso que teria que ter um Indicador de Disponibilidade: As áreas mudam de cor (ex: Verde = vagas, Vermelho = Lotado). E por último, penso que deveria apontar rotas: O usuário clica na vaga desejada e o app abre a rota usando o GPS (como Waze ou Google Maps)."*

## docker - ambiente de desenvolvimento (informal)

quer rodar o projeto rápido em dev usando docker? segue o passo a passo bem direto, tudo em minúsculas e sem frescura:

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

se quiser, eu removo o README-docker.md e deixo só essa seção ou adiciono instruções específicas pra android/ios. fala o que prefere.

