titulo: ambiente de desenvolvimento com docker

descrição:

olá, pessoal — criei um ambiente de desenvolvimento com docker para rodar o flutter web e os emuladores do firebase (firestore + auth).

o que foi adicionado:
- `docker/flutter/Dockerfile` (imagem dev baseada em cirrusci/flutter, roda `flutter run -d web-server` na porta 5000)
- `docker/firebase/Dockerfile` (imagem com `firebase-tools` para emuladores)
- `docker-compose.yml` (orquestra `flutter` + `firebase`)
- `.dockerignore`
- atualização no `README.md` com instruções simples (seção docker)

como testar:

1. rodar `docker-compose up --build`
2. abrir http://localhost:5000 para o flutter web
3. checar emulador firestore em http://localhost:8080 e ui dos emuladores em http://localhost:4000

obs:
- o arquivo `README-docker.md` foi removido porque as instruções foram colocadas no `README.md`
- se quiserem eu crio um pr com branch `feat/dev-docker` ou ajusto as portas/serviços

checklist:
- [ ] revisar dockerfiles
- [ ] testar push de dados no emulador firestore
- [ ] documentar variáveis de ambiente necessárias

tags: dev, infra, docker
