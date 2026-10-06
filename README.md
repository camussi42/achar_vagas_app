# Aplicação para busca de vagas de estacionamento nos grandes centros urbanos.

**Otávio Camussi Tomaz**

**Samuel Sena Rosa**

**André Alevato Micheletti**

***

Trabalho referente à disciplina de Projeto Integrador

Prof.° Reginaldo Ré

**app publicado:** https://achar-vagas.web.app/

[![ci](https://github.com/camussi42/achar_vagas_app/actions/workflows/ci.yml/badge.svg)](https://github.com/camussi42/achar_vagas_app/actions/workflows/ci.yml)

## Proposta inicial

*"Gostaria de desenvolver um aplicativo de mobilidade urbana focado em estacionamento. O objetivo principal é ajudar motoristas a encontrarem e navegarem até vagas de carro disponíveis em tempo real, reduzindo o tempo de busca e o trânsito. Pensei em uma espécie de mapa, onde o usuário abre o app, vê sua localização atual e os pontos de estacionamento ao redor. Penso que teria que ter um Indicador de Disponibilidade: As áreas mudam de cor (ex: Verde = vagas, Vermelho = Lotado). E por último, penso que deveria apontar rotas: O usuário clica na vaga desejada e o app abre a rota usando o GPS (como Waze ou Google Maps)."*

## sobre o software

app em Flutter web + Firebase: um mapa do centro de Campo Mourão onde o motorista vê, em tempo real, quais trechos de rua têm vaga de estacionamento.

- a localização é pedida já na abertura: o mapa centraliza no usuário (OpenStreetMap) e o botão de localização recentraliza quando quiser
- cada trecho de rua fica com a cor do estado: **verde** = tem vaga, **vermelho** = lotado, **laranja** = liberando vaga; trecho sem relato recente não é pintado
- a cor vem dos próprios usuários: os botões "tem vaga", "lotado" e "saindo" gravam um relato que vale **20 min** — o relato mais recente manda
- tocar num trecho pintado abre o detalhe: nome da via, estado atual, quantos relatos válidos ele tem e há quanto tempo foi o último; o botão **ir até aqui** abre a rota até o ponto no app de mapas (no web, o Google Maps em outra aba)
- sem Firebase configurado o app sobe em **modo demonstração**: os 40 trechos reais do centro com relatos em memória, e uma faixa no topo avisa que está sem backend

## como testar

**pelo app publicado**

1. abrir https://achar-vagas.web.app/ e permitir a localização
2. relatar "tem vaga" num trecho: ele fica verde por 20 min; relatar "lotado" depois troca a cor (o relato mais recente manda)
3. tocar no trecho abre a folha de detalhe com a via e a idade do relato; "ir até aqui" abre a rota até o ponto

**localmente**

```bash
flutter pub get
flutter run -d chrome
```

ou subindo o app e o emulador do firebase com docker (app em http://localhost:5000, emulador em http://localhost:4000):

```bash
docker-compose up --build
```

**testes automatizados**

```bash
flutter test                                    # app: unidades e widgets
flutter test test_emulador                      # regras do firestore no emulador (docker-compose up -d firebase)
python -m unittest discover -s tools/pipeline   # pipeline de trechos e seeder
```

**CI:** `flutter analyze`, `flutter test` e os testes da pipeline (`python -m unittest discover -s tools/pipeline`) rodam sozinhas em todo PR e em todo push na `main` (`.github/workflows/ci.yml`); a branch protection da `main` exige os três checks verdes para merge.
