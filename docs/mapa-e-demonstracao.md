# Mapa: pesquisa real e comparação de cenários

O caminho na aplicação é **Mapa de Calor Logístico → Pesquisa e simulação**.
**Histórico por região** mantém a visualização anterior. O simulador original,
os pedidos, os hubs e os indicadores continuam disponíveis nas abas existentes.

## O que consultar

1. Mantenha inicialmente o período apresentado: são datas reais da Olist de 2018.
2. Filtre pela **data da compra**, UF de origem, UF/região de destino, prefixos
   de CEP ou parte do ID. Combine filtros e clique em **Aplicar filtros**.
3. Use **Exemplos: Baixo/Médio/Alto** para acrescentar um filtro de faixa.
   Esses botões respeitam os outros filtros; **Limpar filtros** remove todos.
4. Selecione um destino no mapa ou um pedido na lista. A lista tem páginas de
   30 pedidos. As contagens por faixa cobrem todos os resultados filtrados;
   os pontos representam somente a página exibida e coordenadas disponíveis.
5. Confira as datas, peso, volume, preço e frete. Altere os campos desejados e
   clique em **Simular e comparar cenários**. O formulário usa kg; a API recebe g.
6. Para mudar a origem, escolha **outro vendedor real**. A busca aceita cidade,
   UF, prefixo ou identificador. O destino aceita 5 ou 8 dígitos e usa os cinco primeiros dígitos do CEP.
   Um prefixo desconhecido é rejeitado; o sistema não inventa coordenadas.
7. Confira o risco do cenário e as alternativas. Os pontos e a ligação entre
   origem e destino acompanham o cenário. A linha é uma ligação geográfica,
   não uma rota rodoviária. As coordenadas são medianas por prefixo de CEP.

O ponto de partida é um dos **19.258 pedidos reais da avaliação preservada**.
O mapa não mistura essa amostra com pedidos operacionais importados na aba
Pedidos. Os cenários modificam entradas hipotéticas desse pedido real, sem
criar novos exemplos rotulados, reensinar o modelo ou alterar os pedidos salvos.
Não há precisão/recall medidos para esses cenários hipotéticos.

Pedidos com vários vendedores mantêm a rota agregada: para mudar origem ou
destino, escolha um pedido com um vendedor. Campos numéricos deixados em
branco mantêm o valor original. Datas são locais, sem conversão para UTC.

## Qual modelo é executado

**Modelo 564 + filtro**, versão `modelo_564_filter`, na pasta
`ML/modelos_finais`. Os dois notebooks e os dois modelos finais continuam
preservados. O de 613 não é utilizado pelo novo mapa.

Fluxo: Flutter → Node `/api/v1/map/*` → Python `/map/*` → Random Forest
original → filtro CatBoost com histórico causal do vendedor e da rota.
Hashes dos pesos e dos dados são conferidos antes do carregamento.

A pesquisa reutiliza as previsões históricas preservadas nos arquivos finais.
O botão de simulação calcula uma nova previsão com os pesos reais, sem usar
`atraso_real`, data de entrega efetiva ou outro desfecho como entrada.

O mapa tem três faixas **operacionais**, derivadas das duas etapas do modelo:

| Faixa | Critério |
| --- | --- |
| Baixo | O score da Random Forest não atingiu seu corte, aproximadamente 0,37 |
| Médio | A Random Forest alertou, mas o filtro contextual retirou o alerta |
| Alto | A previsão final atingiu o corte preservado de 0,03386708589440988 |

O aprendizado continua sendo binário: atraso ou ausência de alerta. As faixas
não resultam de um novo treinamento de três classes nem de cortes arbitrários
de 33%/66%. Um score de 0,05 **não significa 5% de chance de atraso**.
Baixo e médio também podem conter atrasos que o classificador não encontrou.

Na amostra completa há 14.330 baixos, 6 médios e 4.922 altos. Médio é raro
porque o filtro preservado retirou somente seis falsos alertas da primeira etapa.
Um prazo já vencido é destacado separadamente, mesmo que o modelo não alerte.

## Comparações e sugestões

São testadas alternativas válidas de despacho um dia antes/depois, o próximo
dia de semana sem feriado fixo nacional quando aplicável, e prazo +2 dias.
Uma alternativa de despacho mantém compra e prazo prometido. A alternativa
de prazo aparece explicitamente como **renegociação com o cliente**: mudar a
promessa não acelera o transporte e não deve ser apresentado como ganho logístico.

O histórico das alternativas fica limitado ao despacho do cenário informado.
Uma alternativa futura não recebe entregas que só seriam conhecidas depois.
Não se altera o histórico compartilhado do modelo entre requisições.

A sugestão de menor risco só aparece quando a faixa efetivamente diminui.
Sem melhora, a tela informa isso. A comparação é uma estimativa do modelo,
não uma demonstração de que mudar uma data causaria uma entrega melhor.

O calendário usa somente feriados nacionais de data fixa: 01/01, 21/04, 01/05,
07/09, 12/10, 02/11, 15/11, 25/12 e 20/11 a partir de 2024. Fontes:
[Lei 662, texto atualizado](https://www2.camara.leg.br/legin/fed/lei/1940-1949/lei-662-6-abril-1949-347136-normaatualizada-pl.html),
[Lei 6.802](https://www.planalto.gov.br/ccivil_03/leis/l6802.htm) e
[Lei 14.759](https://www2.camara.leg.br/legin/fed/lei/2023/lei-14759-21-dezembro-2023-795091-publicacaooriginal-170522-pl.html).
Feriados móveis, locais e pontos facultativos não estão cadastrados.
O modelo preservado **não tem feriado como atributo explícito**.

## Exemplos reais para demonstrar

Limpe os filtros, cole o ID completo ou uma parte no campo de pesquisa e aplique.
O resultado real posterior fica em uma seção separada, apenas para conferência.

| Uso na demonstração | ID real | Resultado preservado |
| --- | --- | --- |
| Baixo | `1422a4b4a2aa8b66fd49ff5557200b42` | Sem alerta; entregue no prazo |
| Médio | `64ff87188034c4f3dcd52e63db7d045f` | Alerta retirado pelo filtro; entregue no prazo |
| Alto | `d1594d3b636b86cf4ce22e2ca650a55c` | Alerta mantido; atraso real, ainda não vencido no despacho |

No exemplo médio, antecipar o despacho de **12/06/2018** para **11/06/2018**
reduz a faixa para baixo na comparação. Isso é um cenário estimado, não um
resultado de entrega observado para aquela nova data.

Para demonstrar calendário, use compra `2018-09-06T10:00:00`, despacho
`2018-09-07T10:00:00` e prazo `2018-09-20T00:00:00`. A tela identifica
Independência do Brasil e compara também o despacho de segunda, 10/09.
Não é garantido que essa alternativa reduza o risco.

## Rodar no PowerShell do VS Code

Preparação, **na raiz do repositório**, uma vez por ambiente Python 3.12:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r back\ml\requirements-docker.txt
npm.cmd ci --prefix back
cd flutter_app
flutter pub get
```

Se a `.venv` já existe e funciona, mantenha-a e execute apenas a instalação
das dependências. Não precisa treinar novamente nem baixar a Olist para abrir
o novo mapa: a amostra, os modelos e o catálogo compacto estão no repositório.

**Terminal 1 — Python**, partindo da raiz:

```powershell
cd back\ml
..\..\.venv\Scripts\python.exe -m uvicorn logipredict.service:app --host 127.0.0.1 --port 8000
```

**Terminal 2 — Node**, partindo da raiz:

```powershell
cd back
$env:HUBS_FILE = 'data/hubs/hubs.json'
$env:ORDERS_FILE = 'data/hubs/orders.json'
$env:PREDICTIONS_FILE = 'data/hubs/predictions.json'
$env:PREDICTIONS_JOURNAL_FILE = 'data/hubs/predictions.jsonl'
npm.cmd start
```

As variáveis acima apontam para os cadastros já incluídos no repositório,
nos mesmos arquivos usados pelo volume Docker. Se você utiliza outros arquivos
de dados, mantenha seus caminhos habituais nessas variáveis.

**Terminal 3 — Flutter**, partindo da raiz:

```powershell
cd flutter_app
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://127.0.0.1:3001
```

Abra `http://localhost:8080`. Para reiniciar, primeiro encerre a instância
anterior com `q`/Ctrl+C no seu terminal; uma segunda instância não consegue
ocupar a mesma porta. O mapa novo não precisa de PostgreSQL. Os avisos de
conexão recusada do banco referem-se à persistência existente e seu fallback JSON.

O desenho das regiões e os pontos do novo mapa funcionam sem internet.
**Mostrar ruas** usa OpenStreetMap e requer internet. A vista histórica anterior
e funcionalidades externas de CEP/rota podem continuar dependendo de rede.

## API e testes

| Node | Função |
| --- | --- |
| `GET /api/v1/map/catalog` | Versão, métricas, período, UFs, regiões, definições e limites |
| `GET /api/v1/map/orders` | Pesquisa filtrada e paginada da amostra histórica |
| `GET /api/v1/map/order?order_id=...` | Entrada completa e resultado posterior separado |
| `GET /api/v1/map/sellers?q=...` | Identificadores reais para escolher a origem |
| `POST /api/v1/map/simulate` | Nova previsão, alternativas, calendário e avisos |

Filtros: `start_date`, `end_date` (compra, inclusivos), `origin_state`,
`destination_state`, `region` (destino), `risk`, `origin_prefix`,
`destination_prefix`, `order_id`, `offset`, `limit` (1–100). O período pesquisável
é o da amostra, não o de pedidos operacionais atuais.

O corpo de simulação exige `order_id`. Campos opcionais: `purchase_at`,
`dispatched_at`, `estimated_delivery_at`, `seller_id`, `destination_prefix5`,
`total_weight_g`, `total_volume_cm3`, `price`, `freight_value`.
Campos extras, valores negativos/não finitos, identidades inventadas,
cronologia inválida e informação futura retornam 422. Um pedido inexistente
retorna 404; serviço ou artefatos indisponíveis retornam 503; timeout retorna 504.
Datas de cenário: 2016–2035, despacho após o treinamento e até 365 dias entre
compra e prazo. Datas posteriores à base recebem aviso de ausência de histórico recente.

Na raiz:

```powershell
$env:PYTHONPATH = 'back/ml'
.\.venv\Scripts\python.exe -m pytest back/ml/tests -q
npm.cmd test --prefix back
cd flutter_app
flutter test
```

O teste Python reproduz todas as 19.258 previsões com os pesos preservados e
confere a matriz 564/4358/140/14196. Também testa filtros combinados, datas,
faixas, mudança real de rota, isolamento temporal e distinção entre calendário
e aprendizado. O Flutter testa envio dos campos, conversão de peso, resultado,
comparação e recuperação de erro. Os testes antigos verificam as outras telas.

O catálogo vem dos CSVs originais Olist, com hashes em
`back/ml/map_data/manifest.json`. Para reproduzir sua geração:

```powershell
$env:PYTHONPATH = 'back/ml'
.\.venv\Scripts\python.exe -m logipredict.build_map_catalog
```

## Limites do resultado de ML

O modelo encontrou **564 dos 704 atrasos**: recall 80,11%, precisão dos
alertas 11,46%, **4.358 falsos alertas**, 140 atrasos não detectados e
14.196 entregas no prazo sem alerta. Dos 564, **434 foram antecipações** e
130 já tinham prazo vencido no despacho.

O benchmark é retrospectivo e exploratório: o período final já foi consultado
nas pesquisas anteriores. Ele demonstra o funcionamento e o compromisso entre
recall e falsos alertas; não comprova generalização para uma operação nova.
O histórico só contém a coorte elegível de pedidos posteriormente entregues.
Não inclui um histórico completo de cancelamentos ou pedidos ainda abertos.
Não se identifica transportadora, trânsito, clima ou causa de atraso.
