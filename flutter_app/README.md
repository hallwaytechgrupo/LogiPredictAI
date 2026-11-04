# LogiPredict AI — Aplicativo Flutter

Aplicativo desenvolvido em Flutter para simulação e análise de riscos logísticos, com interface multiplataforma.

## Funcionalidades

- **Simulador logístico:** preenchimento de informações para simular o risco de uma entrega.
- **Mapa:** visualização de informações geográficas utilizando OpenStreetMap.
- **Pedidos:** importação em lote, seleção manual do hub responsável e análise de risco.
- **Análises:** gráficos para auxiliar na interpretação dos dados logísticos.

> **Previsões:** no fluxo em lote, o resultado individual vem do serviço de ML e é registrado no histórico da API junto ao `order_id` e ao `hub_id` vigente. Importar um pedido não atribui hub automaticamente. A simulação individual sem pedido registrado continua sem persistência.

## Histórico de previsões por hub

A API Node encaminha a previsão ao serviço Python sem acrescentar o vínculo do hub ao payload de inferência. A tela de lote envia o ID do pedido como parâmetro da API Node; o serviço captura o hub associado, salva a resposta real do modelo e retorna `prediction_id` e `persisted`.

- `POST /api/v1/predictions?order_id=<id>` persiste a previsão de um pedido já importado. Sem `order_id`, mantém a simulação avulsa sem histórico.
- `GET /api/v1/analytics/hubs` agrega previsões reais persistidas. Pode filtrar por `start_date`, `end_date` (datas UTC inclusivas, `YYYY-MM-DD`) e `hub_id`.
- O agregado usa a decisão `predicted_late` retornada pelo modelo. Apresenta contagem e percentual de decisões de risco, thresholds e versões observados, com indicadores quando variam.
- Registros sem hub, incompletos, de modelo sintético ou ligados a hubs não cadastrados não entram na agregação. Hubs sem previsões elegíveis são omitidos.
- O mapa consulta esse endpoint ao abrir e ao atualizar. Associa os resultados exclusivamente por `hub_id`; hubs sem agregado continuam azuis e são identificados como "Sem previsões associadas". A camada pode ser ligada/desligada e suas cores representam faixas descritivas do percentual agregado (0%, >0–<50%, 50–<100%, 100%), não thresholds de classificação do modelo.

O arquivo `predictions.json` é persistido no volume de dados da API. A escrita serializada e por arquivo temporário protege contra gravações concorrentes dentro de uma instância Node, mas JSON não oferece transações nem coordenação entre múltiplas instâncias. Os agregados são previsões individuais agrupadas pela associação manual ao hub; não representam um modelo de risco geográfico do hub. Consulte `back/README.md` para o contrato completo e as limitações.

## Simulação Olist em lote

Na aba **Simulação em Lote**, **Executar simulação Olist** carrega `GET /api/v1/datasets/olist` pela URL de API já configurada e executa o CSV preparado `back/data/pedidos_logipredict.csv`. O local do arquivo pode ser configurado na API: localmente por `OLIST_DATASET_FILE`; no Compose por `OLIST_DATASET_HOST_FILE` (padrão `./back/data/pedidos_logipredict.csv`). Consulte `back/README.md` para detalhes.

Antes da execução, selecione um hub aprovado. Esse vínculo é apenas uma configuração de demonstração e não comprova a expedição histórica dos pedidos Olist. O hub escolhido é aplicado somente a pedidos sem vínculo; hubs já associados são preservados. A importação usa blocos de até 2.000 pedidos, deduplica linhas por `order_id`, e envia previsões uma por vez à API. O progresso mostra importação e análise, falhas e ignorados; Cancelar impede novas chamadas e conserva o que já foi persistido. Como cada previsão é individual, executar a base completa pode levar tempo. Reexecutar não cria pedidos duplicados, mas gera novas previsões históricas.

## Tecnologias utilizadas

- Flutter
- Dart
- `flutter_map`
- `latlong2`
- `fl_chart`

## Pré-requisitos

Antes de executar o projeto, instale:

- [Git](https://git-scm.com/)
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Android Studio](https://developer.android.com/studio), para desenvolvimento Android
- Um navegador compatível, caso queira executar a versão web
- Ferramentas de compilação do Linux, caso queira executar a versão desktop no Ubuntu

Verifique a instalação:

```bash
git --version
flutter --version
flutter doctor
```

Para Android, configure o Android SDK e aceite as licenças:

```bash
flutter doctor --android-licenses
```

## Como baixar o projeto

Clone o repositório na branch `front`:

```bash
git clone --branch front https://github.com/hallwaytechgrupo/LogiPredictAI.git
```

Entre na pasta do aplicativo Flutter:

```bash
cd LogiPredictAI/flutter_app
```

## Instalar as dependências

Execute na pasta que contém o arquivo `pubspec.yaml`:

```bash
flutter pub get
```

Esse comando instala as dependências declaradas no projeto.

## Executar o aplicativo

### Android

Conecte um smartphone Android com a depuração USB ativada ou inicie um emulador.

Verifique os dispositivos disponíveis:

```bash
flutter devices
```

Execute:

```bash
flutter run
```

Para selecionar um dispositivo específico:

```bash
flutter run -d ID_DO_DISPOSITIVO
```

Substitua `ID_DO_DISPOSITIVO` pelo identificador exibido pelo comando `flutter devices`.

### Linux (Ubuntu)

Verifique se o Linux está disponível como destino:

```bash
flutter doctor -v
flutter devices
```

Instale as dependências de compilação desktop Linux indicadas pela documentação oficial do Flutter e execute:

```bash
flutter run -d linux
```

### Web (Chrome)

Com o Chrome instalado e o suporte web configurado:

```bash
flutter run -d chrome
```

## Gerar APK para Android

Para compilar uma versão de lançamento:

```bash
flutter build apk --release
```

O arquivo APK será gerado normalmente em:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Transfira o APK para um dispositivo Android compatível e instale-o. O Android poderá solicitar autorização para instalar aplicativos provenientes daquela origem.

## Estrutura do projeto

```text
flutter_app/
├── android/       # Configuração da plataforma Android
├── ios/           # Configuração da plataforma iOS
├── lib/
│   └── main.dart  # Código principal do aplicativo
├── linux/         # Configuração desktop Linux
├── macos/         # Configuração desktop macOS
├── test/          # Testes automatizados
├── web/           # Arquivos da versão web
├── windows/       # Configuração desktop Windows
├── pubspec.yaml   # Dependências e configuração Flutter
├── pubspec.lock   # Versões resolvidas das dependências
└── README.md
```

## Solução de problemas

### Dependências não reconhecidas

Execute:

```bash
flutter pub get
flutter analyze
```

### Dispositivo Android não aparece

Confira a conexão USB, ative a depuração USB e execute:

```bash
flutter doctor -v
flutter devices
```

### Erro de compilação Android relacionado ao Java

Confira a versão do Java utilizada pelo Flutter:

```bash
flutter doctor -v
```

Se houver incompatibilidade entre Java, Gradle e Android Gradle Plugin, verifique as versões exigidas pelo projeto antes de alterar o JDK.

### Licenças Android pendentes

Execute:

```bash
flutter doctor --android-licenses
```

Aceite as licenças solicitadas e verifique novamente:

```bash
flutter doctor
```

## Desenvolvimento

Antes de enviar alterações ao repositório, verifique o código:

```bash
flutter analyze
```

Execute os testes automatizados disponíveis:

```bash
flutter test
```

## Repositório

GitHub: https://github.com/hallwaytechgrupo/LogiPredictAI/tree/front

## Licença

Consulte a licença definida no repositório principal antes de redistribuir ou reutilizar o projeto.
