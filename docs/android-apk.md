# Aplicativo Android

A interface Flutter também pode ser compilada como APK. O aplicativo Android
consulta a mesma API e os mesmos modelos da versão Web. Node.js, Python, banco
e pesos de ML continuam no computador ou servidor; não são executados dentro
do celular.

## Compilar

Ambiente utilizado: Flutter 3.41.9, Dart 3.11.5, JDK 21, Android SDK 36,
Gradle 8.14, Android Gradle Plugin 8.11.1 e Kotlin 2.2.20. O aplicativo requer
Android 7.0/API 24 ou superior.

Na raiz do projeto, em PowerShell:

```powershell
cd flutter_app
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=http://127.0.0.1:3001
```

O arquivo é gerado em:

```text
flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

É um APK universal para ARM de 32/64 bits e x86-64. O pacote se chama
`com.hallwaytech.logipredict`, com o nome **LogiPredict AI** no Android.
A configuração atual assina o release com a chave de desenvolvimento local,
adequada à instalação de demonstração. A publicação em loja requer uma chave
de assinatura própria e sua configuração no Gradle.

Na validação de 24/11/2026, o APK release 1.0.0 foi instalado e aberto em um
Samsung A36 com Android 16. Uma cópia local do arquivo ficou em
`reports/local/android/LogiPredictAI-1.0.0.apk`, além da saída padrão do build.
A cópia no aparelho fica em **Meus Arquivos → Downloads**, com o nome
`LogiPredictAI-20261124.apk`.

O cache incremental do Kotlin fica desativado para evitar a falha de caminhos
entre unidades no Windows quando o projeto está em D: e o Pub Cache está em C:.
O compilador Kotlin usa o processo do Gradle e o build limita o número de
workers para reduzir o consumo simultâneo de memória.

## Serviços necessários

No celular, o APK substitui o terceiro terminal que executa o Flutter Web.
Somente os serviços Python e Node.js precisam continuar ligados no computador.
As instruções dos dois serviços estão no [README](../README.md#iniciar-no-vs-code--powershell).

O endereço utilizado pelo celular é o do Node.js, na porta 3001. A comunicação
com o Python na porta 8000 acontece no servidor. Os pesos dos dois modelos
permanecem em `ML/modelos_finais`; a simulação do mapa usa `modelo_564_filter`.

## Conectar por USB

Com o Android conectado e autorizado para depuração, na raiz do projeto:

```powershell
$adb = 'D:\src\android-sdk\platform-tools\adb.exe'
& $adb devices
& $adb reverse tcp:3001 tcp:3001
& $adb install -r '.\flutter_app\build\app\outputs\flutter-apk\app-release.apk'
```

O caminho do ADB acima corresponde ao SDK deste ambiente. Em outro computador,
o comando `flutter doctor -v` informa o diretório do Android SDK.

No aplicativo, o botão **Configurar conexão** fica no cabeçalho:

1. Selecione **Conexão USB**.
2. Clique em **Testar conexão**.
3. Com o servidor e a previsão disponíveis, clique em **Salvar**.

O endereço USB é `http://127.0.0.1:3001`. O encaminhamento precisa ser refeito
após reconectar o cabo ou reiniciar a sessão de depuração. Sem esse
encaminhamento, `127.0.0.1` representa o próprio celular, não o computador.

## Conectar por Wi-Fi

O celular e o computador precisam conseguir se comunicar na mesma rede.
No terminal do backend, antes de iniciar o Node.js:

```powershell
$env:HOST = '0.0.0.0'
npm.cmd start
```

Mantenha as demais variáveis de arquivos operacionais utilizadas no README.
O Python pode continuar ouvindo apenas em `127.0.0.1:8000`.

O comando `ipconfig` mostra o IPv4 do computador. No aplicativo, selecione
**Conexão Wi-Fi** e informe esse endereço com a porta 3001, por exemplo
`http://192.168.0.31:3001`. Esse IP é um exemplo do ambiente local e pode mudar.
O firewall do computador deve permitir a conexão do celular à API na rede
utilizada. Não é necessário expor a porta 8000.

O endereço é salvo no aparelho. O mesmo APK aceita outro IP ou um servidor
HTTPS sem precisar ser recompilado. Salvar a conexão recarrega as telas e os
clientes HTTP para o servidor escolhido. No Web, os endereços continuam
definidos por `API_BASE_URL` e pela variável de compatibilidade
`LOGIPREDICT_API_URL` durante o build.

## Recursos no celular

A versão **1.0.1** acrescenta o trajeto pelas estradas em **Mapa → Simular**.
O servidor consulta o OpenRouteService e o APK desenha a geometria retornada.
A atualização mantém o endereço de conexão salvo no aparelho. Veja o
[guia de rotas](rotas-rodoviarias.md) para configurar o backend e testar.

O APK local dessa atualização está em
`reports/local/android/LogiPredictAI-1.0.1-rotas.apk`. Instale por cima da
versão anterior para manter os dados e a configuração de conexão.

- Navegação inferior para simulador, mapa, pedidos, análises e hubs.
- Importação de CSV pelo seletor de arquivos do Android.
- Simulação original, comparação de cenários e análise de sensibilidade.
- Compra futura com o modelo 564 + filtro contextual.
- Mapa nativo com origem/destino, cor por faixa de risco, ajuste da câmera,
  zoom, contornos regionais, hubs e detalhes por UF.
- Tema claro/escuro e formulários adaptados à largura disponível.

O Web continua usando Leaflet. No Android, o mapa usa `flutter_map` e o mesmo
contrato de dados. As ruas do OpenStreetMap precisam de internet no celular;
os contornos regionais acompanham o aplicativo. A classificação depende do
servidor, mesmo quando a rua do mapa não pode ser carregada.

## Testes

Os testes de interface incluem larguras de 320/360 pixels, orientação
horizontal e uma área de altura reduzida. Também verificam configuração do
servidor, persistência do endereço, câmera/cor da rota e detalhes regionais.

```powershell
cd flutter_app
flutter test --concurrency=1
```

O teste de integração usa o servidor real e não importa nem altera pedidos
operacionais. Com o aparelho autorizado, os serviços ligados e a porta 3001
encaminhada por USB:

```powershell
flutter devices
flutter drive --profile -d ID_DO_APARELHO --driver=test_driver/integration_test.dart --target=integration_test/android_smoke_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:3001
```

Esse comando instala uma versão de teste em modo profile. Depois do teste,
o APK de release pode ser reinstalado com `adb install -r`. As capturas da
execução ficam em `flutter_app/build/reports/android`.

Ao alternar do teste em profile para o release, use o comando completo de
build, sem `--no-pub`, para regenerar o registro de plugins do modo escolhido.
Mantenha a tela do celular desbloqueada durante o teste integrado.

Referências: [build Android no Flutter](https://docs.flutter.dev/deployment/android),
[rede do emulador e localhost](https://developer.android.com/studio/run/emulator-networking-address),
[encaminhamento USB com ADB](https://developer.android.com/develop/ui/views/layout/webapps/access-local-server)
e [compilação e cache do Kotlin](https://kotlinlang.org/docs/gradle-compilation-and-caches.html).
