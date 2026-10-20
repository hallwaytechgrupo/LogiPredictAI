# Como contribuir

A entrega atual concentra IA e API na branch `back`. `main` mantém a visão do projeto e a documentação acadêmica. A interface Flutter será desenvolvida em uma etapa futura, em `front`.

1. Atualize sua cópia de `back` e crie uma branch de trabalho (`feat/...`, `fix/...` ou `docs/...`).
2. Faça uma alteração pequena, vinculada ao backlog em `docs/backlog.md`.
3. Rode os testes Python, Ruff e os testes Node indicados no README.
4. Abra um pull request para `back`, descrevendo problema, comportamento entregue e validação.
5. Registre a revisão da equipe; atualize a documentação em `main` em um PR próprio quando necessário.

Não adicione CSVs Olist, modelos binários, `.env`, credenciais Kaggle, ambientes virtuais ou `node_modules` ao Git. Os dados são obtidos da fonte oficial e os artefatos são gerados localmente. Relatórios agregados podem ser publicados com a devida atribuição à Olist.

Mudanças em features devem preservar o uso da mesma transformação em treino e inferência (`ml/logipredict/schema.py`). Não use avaliações de clientes, status final, entrega efetiva ou outras informações futuras como preditores. O teste temporal fica reservado; não ajuste parâmetros com base nele.

Os pontos do backlog são estimativas iniciais para refinamento. Datas, responsáveis por tarefas e aceite acadêmico devem ser definidos pela equipe, sem preencher entregas ou aprovações fictícias.
