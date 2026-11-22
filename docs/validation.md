# Validação da entrega

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
