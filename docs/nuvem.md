# Aplicação na nuvem

A implantação separa o frontend, a API, a inferência e o banco. O computador
local pode ficar desligado quando o usuário escolhe o servidor da nuvem.

| Componente | Serviço | Responsabilidade |
| --- | --- | --- |
| Flutter Web | Hospedagem estática do Sites | Entrega os arquivos da interface por HTTPS |
| API Node.js | Modal | Valida requisições, administra pedidos e consulta rotas e ML |
| Inferência Python | Modal, função independente | Carrega os pesos preservados e executa previsões |
| PostgreSQL | Neon Free | Persiste hubs, pedidos e histórico de previsões |

O Docker empacota dependências para a plataforma gerenciada. Não há uma EC2
mantida pela equipe nem banco instalado junto da API. O provedor cuida da
infraestrutura, das URLs HTTPS e do escalonamento dos serviços. As funções
podem reduzir a zero quando ociosas e estão limitadas a duas instâncias cada.
O primeiro acesso após inatividade pode levar mais tempo.

## Endereços

- Frontend: <https://logipredict-ai-demo.ulysseslima.chatgpt.site>
- API: <https://igors-lima12--logipredict-cloud-api.us-east.modal.run>
- Saúde da API: <https://igors-lima12--logipredict-cloud-api.us-east.modal.run/health>
- Disponibilidade do modelo: <https://igors-lima12--logipredict-cloud-api.us-east.modal.run/ready>

O acesso ao frontend depende da configuração de compartilhamento do Site.
GitHub Pages permanece como alternativa em `.github/workflows/pages.yml`.
Sua ativação exige permissão administrativa no repositório e a variável
`CLOUD_API_URL` com o endereço da API. A credencial de desenvolvimento atual
tem permissão de push, mas não de administração do Pages.

## Custo e disponibilidade

Nenhum plano pago foi contratado. O Neon foi confirmado no plano Free. Na
conta Modal usada nesta entrega, o painel mostrou **US$ 1 de crédito/limite**,
sem forma de pagamento cadastrada. Portanto, não se deve contar com US$ 30
mensais sem conferir os créditos efetivamente concedidos à conta.

A consulta de faturamento durante a validação retornou cobrança de US$ 0.
Essa observação não garante execução gratuita ilimitada. A disponibilidade
depende das franquias e dos créditos restantes. Não cadastrar pagamento nem
aumentar limites para manter esta demonstração sem desembolso. Se a franquia
acabar, os serviços poderão ficar indisponíveis.

Para a feira, abra a aplicação e faça uma previsão antes de começar. Mantenha
a execução local disponível como alternativa para uma falha de rede ou franquia.

## Persistência separada

Na nuvem, `DATA_STORE=postgres` exige uma conexão PostgreSQL válida com TLS.
Uma falha no banco não ativa um arquivo JSON temporário como se o salvamento
tivesse funcionado. O modo local permanece com o comportamento anterior.

As tabelas do schema `logipredict` guardam cada entidade em um registro JSONB,
com identificador e índices. Isso preserva os campos já consumidos pelo Flutter.
O controle de revisão impede que duas instâncias substituam silenciosamente
alterações feitas uma pela outra. Hubs, pedidos e previsões ficam no banco,
fora dos discos temporários das funções.

A carga inicial adiciona os hubs uma única vez. Pedidos e previsões da pasta
local não são enviados automaticamente. Importe o CSV de demonstração pela
tela **Pedidos**. Uma atualização ou reinício da API não deve apagar o upload.

Os arquivos Olist utilizados pelo histórico e pela geografia são cópias de
consulta da base histórica. Eles acompanham a imagem como dados somente de
leitura, separados dos pedidos operacionais novos. Os dois modelos finais e
seus hashes permanecem preservados. O mapa utiliza o modelo 564 + filtro.

Esta implantação atende à demonstração acadêmica. A API operacional ainda não
tem autenticação de usuários; mantenha nela somente dados de demonstração.
Para uma operação empresarial, são necessários controle de acesso, limites
de uso por usuário e validação em uma base atual.

## Atualizar os serviços

Os arquivos públicos de implantação ficam em `deploy/cloud`. As credenciais
ficam em `deploy/cloud/.env`, que o Git ignora. O serviço ML exige um token
interno, compartilhado apenas com a API. A chave OpenRouteService também fica
somente no servidor. O frontend e o APK recebem somente a URL pública da API.

Na raiz do projeto, com o ambiente de publicação preparado:

```powershell
$env:PYTHONUTF8 = '1'
.\reports\local\cloud-venv\Scripts\python.exe deploy/cloud/configure_secrets.py
.\reports\local\cloud-venv\Scripts\python.exe -m modal deploy deploy/cloud/app.py
```

Em outro computador, crie um ambiente Python separado e instale
`deploy/cloud/requirements.txt`. Autorize-o com `python -m modal setup`.
Não envie `.env` ao repositório. Os identificadores e URLs sem senhas estão
registrados em `deploy/cloud/deployment.json`.

Para compilar o frontend com o backend publicado:

```powershell
cd flutter_app
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=https://igors-lima12--logipredict-cloud-api.us-east.modal.run
```

A publicação estática deve reutilizar o Site identificado em
`deploy/cloud/deployment.json`. Os arquivos compilados e o manifesto da
publicação atual estão no checkout local
`reports/local/cloud-frontend-20261124`. Novas versões exigem recompilar,
sincronizar esse checkout e publicar seus arquivos atualizados.

## Testar no navegador e no Android

1. Confira `/health` e `/ready` nos endereços acima.
2. Abra **Mapa**, use o exemplo de compra futura e calcule o risco.
3. Confira o trajeto pelas estradas e altere uma data ou prazo.
4. Em **Histórico**, confira as taxas regionais observadas.
5. Importe o CSV de demonstração em **Pedidos** e consulte o pedido importado.

No APK 1.0.1, abra **Conexão com o servidor**, informe a URL HTTPS da API,
teste e salve. A versão já instalada não precisa usar a rede Wi-Fi do
computador para consultar a nuvem. Ela precisa de conexão com a internet.
O endereço local salvo anteriormente só muda quando o usuário salva o novo.

## Validação

- Backend: 165 testes aprovados e dois ignorados na execução padrão. Os dois
  casos ignorados exigem bancos de teste explicitamente configurados.
- PostgreSQL Neon: testes de persistência, concorrência, API e CORS executados
  na branch separada `validacao-cloud-20261124`. O fluxo adicional importou um
  CSV, consultou o ML remoto e confirmou a previsão salva em outra conexão;
  os três testes dessa execução passaram.
- Python: 58 testes aprovados, incluindo proteção do serviço ML e cenários.
- Flutter Web: build de produção apontando para a API HTTPS.
- Requisições reais na nuvem: saúde, modelo 564, previsão de compra futura,
  histórico, preflight CORS e rota OpenRouteService.
- A previsão futura retornou `modelo_564_filter`, classificação e quatro
  alternativas. O trajeto SP–RJ retornou 432,25 km e 2.917 pontos.

A interface Web teve seus fluxos testados localmente na etapa das rotas. A
conferência desta publicação usa build, respostas HTTP e validação dos ativos;
não equivale a uma nova homologação visual em todos os aparelhos. O APK atual
ainda deve ser testado fisicamente com o endereço da nuvem salvo no celular.

Referências: [Modal Web Functions](https://modal.com/docs/guide/webhooks),
[limites de cobrança](https://modal.com/docs/guide/budgets),
[planos Neon](https://neon.com/docs/introduction/plans) e
[GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
