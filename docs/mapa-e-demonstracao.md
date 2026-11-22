# Leaflet e simulação de uma entrega futura

Abra **Mapa de Calor Logístico**. Há duas vistas:

- **Simular nova entrega:** formulário à esquerda para uma compra planejada.
- **Histórico por região:** taxas reais observadas na Olist e detalhes por UF.

As duas vistas usam **Leaflet 1.9.4 no Flutter Web**, com ruas e cidades do
OpenStreetMap. Apenas um mapa permanece ativo. Alternar as vistas mantém os
campos e a última análise, mas libera o mapa anterior.

## Como simular

1. Digite um CEP de 5/8 dígitos ou cidade em **De onde?** e **Para onde?**.
   Selecione uma sugestão real do catálogo; locais desconhecidos não recebem
   coordenadas inventadas.
2. Informe compra, despacho e prazo em `DD/MM/AAAA HH:mm`.
3. Informe peso em kg, itens, valor dos produtos e frete. Volume é opcional;
   quando ausente, usa a imputação do treinamento.
4. O ID do vendedor é opcional. Só informe um ID Olist real correspondente à
   origem. Sem ID, o contexto usa a rota/região, sem atribuir histórico de outro vendedor.
5. Clique em **Calcular risco**. Veja a rota geográfica, classificação,
   calendário e alternativas no painel de resultado.

Não é necessário importar ou selecionar um pedido antigo. A requisição contém
as entradas completas de um pedido hipotético e não grava nem treina um pedido novo.
A unidade é um pedido com uma origem. A distância é em linha reta entre áreas
aproximadas de CEP; a linha não representa uma rodovia.

**Exemplo: compra em 23/12** preenche um cenário hipotético São Paulo–Rio:
compra no próximo 23/12, despacho 24/12, prazo 04/01, 0,5 kg, 1 item,
1.200 cm³, R$ 100 em produtos e R$ 20 de frete. Ajuste os valores desejados.
Não se trata de um registro de compra real.

## Modelo e limites

Executa os pesos preservados de **564 + filtro CatBoost**, versão
`modelo_564_filter`, em `ML/modelos_finais`. Os dois notebooks e modelos finais
continuam preservados; o modelo 613 não é usado por essa vista.

| Faixa | Decisão |
| --- | --- |
| Baixo | A Random Forest não gerou alerta inicial |
| Médio | O filtro contextual retirou o alerta inicial |
| Alto | O modelo final manteve o alerta |

O aprendizado é binário. As três faixas organizam as duas etapas, não são um
novo modelo de três classes. Score não é uma porcentagem calibrada e baixo
risco não garante entrega. Datas futuras extrapolam uma base de 2016–2018,
sem histórico operacional recente; essa limitação aparece no resultado.

O benchmark exploratório preservado tem 19.258 pedidos e 704 atrasos:
564 encontrados, 4.358 falsos alertas, 140 não detectados e 14.196 entregas no
prazo sem alerta. Dos 564, 434 foram antecipados e 130 já estavam vencidos no
despacho. O teste final foi consultado durante as pesquisas anteriores.
Esses números não medem desempenho em novos cenários hipotéticos.

## Calendário e alternativas

São comparados despachos antes/depois da data informada, após feriado/fim de
semana quando aplicável e prazo +2 dias. Renegociar o prazo exige acordo com
o cliente e não acelera o transporte. As alternativas de despacho mantêm
compra/prazo e não recebem eventos posteriores ao cenário base.

Uma sugestão de faixa menor só aparece quando a nova previsão a reduz.
Feriados fixos nacionais são contexto do calendário, não um atributo explícito
do modelo nem uma causa comprovada da classificação. Feriados móveis, locais
e pontos facultativos não estão cadastrados. Fontes:
[Lei 662](https://www2.camara.leg.br/legin/fed/lei/1940-1949/lei-662-6-abril-1949-347136-normaatualizada-pl.html),
[Lei 6.802](https://www.planalto.gov.br/ccivil_03/leis/l6802.htm) e
[Lei 14.759](https://www2.camara.leg.br/legin/fed/lei/2023/lei-14759-21-dezembro-2023-795091-publicacaooriginal-170522-pl.html).

## Histórico e desempenho

O histórico mostra entregas observadas, não previsões para novos pedidos.
Clique na região da lista para aproximar; clique no nome no mapa para consultar
as UFs. Os pontos azuis são hubs cadastrados.

- Leaflet controla zoom/arraste fora do canvas Flutter. Polígonos não recebem
  testes de colisão a cada movimento do mouse; cinco rótulos abrem os detalhes.
- Somente o mapa visível fica montado, sem animação entre dois mapas.
- O dashboard deixou de consultar o journal completo de previsões de hubs
  para uma tela que só usa o cadastro dos hubs.
- CSVs e agregados são reutilizados; mudanças nos arquivos invalidam o cache.
- Buscar CEPs não inicializa o modelo. Prever um pedido futuro não carrega
  nem recalcula as previsões dos 19.258 pedidos da avaliação.

A biblioteca e a geometria são locais. As ruas exigem internet; sem elas,
o contorno e os pontos continuam disponíveis. No Web é recomendado usar
produção, evitando o custo adicional do debug.

## Executar e testar

Os comandos dos três terminais estão no [README atual](../README.md#iniciar-no-vs-code--powershell).
O terminal Flutter pode usar:

```powershell
cd flutter_app
flutter run -d chrome --release --web-port 8080 --dart-define=API_BASE_URL=http://127.0.0.1:3001
```

Para desenvolver com hot reload, retire `--release`. Reinicie os serviços
anteriores antes de ocupar as mesmas portas. Se já estão rodando, abra
`http://localhost:8080`; use Ctrl+Shift+R se a aba mostrar uma versão antiga.

```powershell
$env:PYTHONPATH = 'back/ml'
.\.venv\Scripts\python.exe -m pytest back/ml/tests -q
npm.cmd test --prefix back
cd flutter_app
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:3001
```

## API

- `GET /api/v1/map/locations?q=...`: busca real por CEP, cidade ou UF.
- `POST /api/v1/map/forecast`: pedido planejado completo, sem `order_id`.
- Rotas retrospectivas `catalog`, `orders`, `order`, `sellers` e `simulate`
  continuam disponíveis para compatibilidade com pesquisas anteriores.

O novo corpo exige `purchase_at`, `dispatched_at`, `estimated_delivery_at`,
`origin_prefix5`, `destination_prefix5`, `total_weight_g`, `price`, `freight_value`.
Opcionais: `items_count` (padrão 1), `total_volume_cm3`, `seller_id`.
Datas ISO locais sem fuso, prefixos de cinco dígitos e peso em gramas.
Campos extras/rótulos futuros, CEP desconhecido, vendedor incompatível,
valores inválidos ou cronologia inconsistente retornam 422.
