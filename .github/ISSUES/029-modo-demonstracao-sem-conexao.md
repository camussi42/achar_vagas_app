titulo: avisar quando o app esta em modo demonstracao/sem conexao

o que muda:

- `lib/ambiente.dart`: enum `MotivoSemFirebase` (nao configurado, sem conexao, autenticacao falhou) + `AmbienteApp.motivoSemFirebase`, que a tela usa na faixa
- `lib/bootstrap.dart`: `bootstrapFirebase` deixa de engolir a falha (`catch (_)`) e registra o motivo nos construtores `FirebaseBootstrap.firebase` / `FirebaseBootstrap.demonstracao`
- `lib/ui/faixa_aviso.dart` (novo): faixa discreta no topo do mapa — modo demonstracao (com o motivo) e falha de leitura em tempo de execucao
- `lib/ui/tela_mapa.dart`: o `onError` do stream de relatos e o `catch` da consulta de trechos deixam de ser vazios; a faixa de leitura sai quando os dados voltam
- `lib/main.dart`: o motivo do bootstrap chega no `AmbienteApp`
- `test/bootstrap_test.dart` (novo), `test/tela_mapa_test.dart` e `test/widget_test.dart`
- `README.md`: o comportamento do modo demonstracao e dos avisos

como testar:

1. `flutter test test/tela_mapa_test.dart test/widget_test.dart test/bootstrap_test.dart`
2. `flutter analyze` (limpo)
3. no app: `flutter run` sem `firebase_options` preenchido -> faixa "modo demonstração: relatos locais, sem backend (Firebase não configurado)" no topo do mapa
4. com o app aberto e o emulador no ar: `docker-compose stop firebase` -> faixa de relatos desatualizados, sem tela de erro (o mapa continua util)

notas:

- a faixa e informativa: o modo demonstracao continua sendo o caminho que roda sem nenhum servico externo
	- o motivo fica no grafo de dependencias (`AmbienteApp.motivoSemFirebase`), entao qualquer tela futura pode usa-lo
