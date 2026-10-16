# Painel de Leitos — Flutter em tempo real (REST + WebSocket)

Painel de **ocupação de leitos hospitalares em tempo real** para a central de regulação e as equipes de enfermagem: internações, altas e higienização aparecem na hora via **WebSocket**, com indicadores de ocupação por setor e alerta de **UTI crítica**. Funciona com **cache local (Hive)** e se **reconecta sozinho** sem perder eventos.

> Segmento: **Saúde / Hospitalar**

## Stack
Flutter 3 / Dart 3 (sealed classes, pattern matching, records) • **Clean Architecture** • **flutter_bloc** (`emit.forEach` com múltiplos streams) • **WebSocket** (`web_socket_channel`) com reconexão e backoff exponencial • **REST** com Dio • **Hive** (cache local) • servidor simulado em `dart:io` (HTTP + WebSocket) • **testes de integração com sockets reais** • bloc_test • mocktail

## Arquitetura

```
lib/features/beds/
├── domain/
│   ├── entities.dart        Bed, Ward, BedEvent (sealed: Admitted/Discharged/Cleaned/Blocked), Board, ConnectionStatus
│   ├── board_logic.dart     applyEvent (máquina de estados pura) + occupancyByWard (KPIs, UTI crítica ≥ 90%)
│   └── bed_repository.dart  contrato
├── data/
│   ├── beds_remote.dart     BedsRestDataSource (snapshot, POST higienização)
│   │                        BedsSocketDataSource (eventos, status da conexão, reconexão com backoff)
│   ├── beds_cache.dart      Hive: último painel conhecido
│   └── bed_repository_impl  cache → snapshot REST → eventos, controlados por número de sequência
└── presentation/            BoardBloc + painel em grade por setor
tool/fake_server.dart        servidor do hospital simulado (REST + WebSocket), usado no app e nos testes
```

### Consistência em tempo real
Cada evento do servidor tem um **número de sequência** (`seq`):
- `seq` ≤ atual → evento duplicado ou já incluído no snapshot: **ignorado**.
- `seq` = atual + 1 → **aplicado**.
- `seq` > atual + 1 → **eventos foram perdidos** (queda de rede): o app busca um **novo snapshot via REST**.

A cada reconexão do WebSocket também é feito um novo snapshot, então o painel nunca fica silenciosamente desatualizado.

### Outras decisões
- **Máquina de estados do leito** no domínio: não há internação em leito aguardando higienização e a alta sempre leva à higienização. Transições inválidas são ignoradas.
- **Comando via REST, confirmação via WebSocket**: liberar um leito faz um POST, e o estado só muda quando o servidor confirma pelo canal em tempo real (fonte única da verdade). Um 409 vira mensagem amigável.
- **Abertura instantânea**: o último painel salvo no Hive aparece antes de a rede responder.
- **Indicador de conexão** sempre visível: Ao vivo, Reconectando ou Offline.
- **Privacidade**: só as iniciais do paciente trafegam e aparecem na tela.
- **Tolerância a versões**: eventos de tipo desconhecido, vindos de um servidor mais novo, são descartados sem derrubar o app.

## Como executar
```bash
dart run tool/fake_server.dart          # servidor em :8080 gerando eventos a cada 2 s
flutter run                             # emulador Android acessa o host via 10.0.2.2
flutter run --dart-define=BEDS_HOST=192.168.0.10:8080   # dispositivo físico
flutter test                            # 11 testes, incluindo integração com HTTP/WebSocket reais
```

### Testes de integração (sem mocks no transporte)
Sobem o servidor real em uma porta local e verificam:
- snapshot seguido de eventos ao vivo;
- **detecção de lacuna** de sequência e ressincronização;
- **queda da conexão** → reconexão → recuperação de eventos perdidos;
- comando REST com confirmação via WebSocket (e 409 na segunda tentativa);
- painel exibido a partir do cache com o servidor fora do ar.
