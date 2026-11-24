# Validação da entrega

## Rotas pelas estradas — 24/11/2026

- Node.js: 165 casos, 164 aprovados e um teste de PostgreSQL ignorado.
  Incluem validação de coordenadas, autenticação no provedor, GeoJSON,
  falhas, timeout, cache, consultas simultâneas e o contrato do despacho.
- Flutter: 113 testes aprovados. Os casos do mapa verificam a geometria
  rodoviária, erro/retry independente da previsão, descarte de respostas
  antigas, troca de vistas, cor da linha e enquadramento da câmera.
- Análise estática dos cinco módulos Dart e testes alterados sem problemas;
  build Web de produção concluído.
- Integração Web no Chrome com serviços e OpenRouteService reais aprovada:
  rota em estradas, previsão com `modelo_564_filter`, histórico e retorno
  ao formulário mantendo a análise.
- A consulta direta São Paulo → Rio retornou 432,25 km, 18.145 segundos e
  2.917 pontos. A consulta inicial levou cerca de 1,44 segundo; a repetição
  em cache levou 0,008 segundo. São medições locais, não um teste de carga.
- O despacho existente também retornou sua rota real pelos hubs selecionados.
  O novo planejamento não modifica os pesos ou a distância geográfica do ML.
- APK universal 1.0.1, código 2, compilado com a mesma assinatura da versão
  anterior. Os nove arquivos do manifesto dos modelos mantiveram os hashes.
  A nova versão não foi instalada fisicamente nesta etapa: o ADB não detectou
  o aparelho. Os testes Flutter verificaram o desenho e a câmera do mapa nativo.

As capturas da integração estão em `flutter_app/build/reports/roads-web`.
Uma delas acompanha o [guia das rotas](rotas-rodoviarias.md).

## Android e compatibilidade Web — 24/11/2026

- Flutter: 110 testes aprovados. Os 10 casos adicionados verificam endereço
  persistido, clientes HTTP, saúde do servidor, telas de 320/360 pixels,
  orientação horizontal, altura reduzida, câmera e detalhes do mapa nativo.
- Análise estática dos oito arquivos novos de conexão, mapa e testes:
  sem problemas.
- Build Web de produção concluído após a adaptação Android. O mapa Web
  permanece em Leaflet e a configuração por `dart-define` foi preservada.
- APK release 1.0.0 universal compilado para ARM de 32/64 bits e x86-64,
  com Android mínimo API 24. Assinatura verificada, permissão de internet
  presente e pacote sem a flag de depuração.
- Release instalado e aberto no A36, com a porta 3001 encaminhada por USB.
- Integração física no Samsung A36, Android 16: conexão USB com a API real,
  previsão de compra futura com `modelo_564_filter`, rota, histórico regional
  e navegação por pedidos, análises e hubs. O teste registra as telas em
  `flutter_app/build/reports/android`. A integração automatizada usa profile;
  depois dela, o APK final de release foi reinstalado.
- Os nove arquivos de pesos, metadados e dados do manifesto de integridade
  mantiveram seus hashes SHA-256. O backend e os modelos não foram alterados.

A execução física usa Node.js com fallback JSON e o serviço Python local.
Não representa teste por Wi-Fi, homologação de PostgreSQL ou validação de
outros modelos de aparelho. O teste não importa nem edita pedidos operacionais
e não automatiza o seletor de documentos do Android.

O [guia Android](android-apk.md) descreve build, instalação, conexão com o
servidor e assinatura do APK de demonstração.

## Leaflet e pedido futuro — 22/11/2026

- Python: 56 testes aprovados, incluindo os pesos preservados, contrato de
  pedido futuro, vendedor opcional, validação de CEP e ausência de desfechos futuros.
- Node: 159 casos, 158 aprovados e 1 ignorado; cache invalidado após alteração
  do CSV e repasse dos novos endpoints verificados.
- Flutter: 67 testes aprovados, incluindo formulário sem pedido importado,
  conversão kg/g, erro/retry e alternância de vistas mantendo a análise.
- Build Web em produção compilado; análise dos novos módulos Dart e Ruff
  dos módulos Python alterados sem problemas.
- Verificação local no navegador: abertura das duas vistas, zoom e arraste do
  histórico e previsão de compra em 23/12; somente um iframe/mapa ativo.
- PostgreSQL, Docker e Mobile continuam fora da homologação desta etapa.

O histórico e a busca de CEP usam cache; a busca de locais não inicializa o
modelo, e a previsão de compra nova não carrega a avaliação dos 19.258 pedidos.

## Mapa integrado — 22/11/2026

- Python: 41 testes aprovados, incluindo reprodução integral das 19.258
  previsões do modelo final e a matriz TP=564, FP=4358, FN=140, TN=14196.
- Node.js: 158 casos, 157 aprovados e 1 ignorado. Os caminhos dependentes de
  PostgreSQL indisponível não foram homologados; os testes de API usam fallback JSON.
- Flutter: 67 testes aprovados. Após o ajuste de CEP de 8 dígitos, os 7 testes
  diretamente relacionados ao mapa e à integração de pedidos foram repetidos e aprovados.
- Ruff nos novos módulos Python e análise estática dos novos arquivos Dart:
  sem problemas. O código legado ainda tem avisos de análise estática.
- Dependências Python: `pip check` sem requisitos quebrados.
- Os builds Docker/Mobile e uma instalação limpa em outro computador não
  foram homologados nesta etapa. Não há alegação de CI remota aprovada.

[Guia atual, comandos e cenários](mapa-e-demonstracao.md) ·
[Pendências para a ABP e a feira](entrega-final-abp.md).

## Registro histórico da primeira entrega

Ambiente local de 20/10/2026: Windows, Python 3.13.4, Node.js 22.14.0 e npm 11.2.0. Dependências diretas em `pyproject.toml`, ambiente Python em `requirements.lock` e resolução Node em `api/package-lock.json`.

## Dados reais

- Olist versão 2 baixada do endpoint oficial; proveniência em `reports/olist/data_source.json`.
- 99.441 pedidos de entrada; 96.281 elegíveis; 3.160 excluídos.
- 54.761 pedidos no treino, 17.445 na validação e 19.258 no teste; 4.817 removidos nos cortes pela maturação dos resultados.
- Artefato local em `models/olist/model.joblib`, com origem real (`synthetic: false`). O binário e os CSVs não são versionados.
- Resultados de avaliação, parâmetros, hash da base e gráficos em `reports/olist/`.

## Verificações executadas

| Verificação | Comando | Resultado |
| --- | --- | --- |
| Testes Python | `python -m pytest -q` | 18 testes aprovados |
| Análise estática Python | `python -m ruff check ml scripts` | Aprovada |
| Consistência de dependências | `python -m pip check` | Sem requisitos quebrados |
| Testes Node.js | `npm test --prefix api` | 6 testes aprovados |
| Sintaxe Node.js | `npm run check --prefix api` | Aprovada |
| Integração real | `python scripts/run_local.py --smoke` | API → Python → Random Forest real, aprovada |

Os testes cobrem a agregação por pedido sem multiplicação de linhas, entrega no dia prometido, dimensões ausentes, chaves conflitantes, distância conhecida, isolamento temporal, rejeição de informações futuras e entradas inválidas, persistência/carregamento do modelo e previsões. No Node, cobrem repasse de dados, validação, ausência do serviço, timeout, respostas inesperadas, JSON inválido e limite de payload.

O teste integrado consulta saúde, disponibilidade, metadados e histórico por UF; envia uma previsão válida ao modelo real e verifica que uma UF inválida recebe HTTP 422. O modelo identifica a origem dos dados em todas as previsões.

Os testes Python também treinam uma floresta pequena com dados sintéticos para validar a serialização e o serviço sem baixar dados externos. Isso não substitui o experimento Olist real.

## Limites desta validação

O GitHub Actions está configurado; o resultado remoto depende do envio dos commits e da execução do workflow. Não há alegação de CI remota aprovada antes disso. A instalação foi validada no Windows; o workflow Linux foi preparado para o GitHub, sem execução local em Linux.

Há um aviso de depreciação entre Starlette e AnyIO no cliente de testes, sem falha funcional. Não foram executados testes de carga nem validação em uma operação logística atual. Não há autenticação ou persistência de pedidos na primeira entrega.
