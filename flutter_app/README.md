# LogiPredict AI — Aplicativo Flutter

Aplicativo desenvolvido em Flutter para simulação e análise de riscos logísticos, com interface multiplataforma.

## Funcionalidades

- **Simulador logístico:** preenchimento de informações para simular o risco de uma entrega.
- **Mapa:** visualização de informações geográficas utilizando OpenStreetMap.
- **Pedidos:** visualização de pedidos em formato de tabela.
- **Análises:** gráficos para auxiliar na interpretação dos dados logísticos.

> **Observação:** os dados podem ser demonstrativos. A integração com uma API ou banco de dados real depende da implementação correspondente no projeto.

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
