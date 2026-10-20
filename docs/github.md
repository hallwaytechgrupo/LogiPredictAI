# Publicar e continuar no GitHub

A cópia local foi clonada de `hallwaytechgrupo/LogiPredictAI`, preservando o histórico. A branch `machineLearning` existente na origem não foi alterada. A entrega prepara `main` com documentação e `back` com implementação e documentação. Nenhuma branch Flutter é necessária agora.

## Revisar antes de enviar

```powershell
git status
git log --oneline --decorate -5
git diff origin/main main --stat
git diff origin/main back --stat
```

Os commits locais contêm a documentação e o código. Dados brutos, ambiente virtual e modelos permanecem na máquina. Revise os relatórios e as limitações antes da review.

## Enviar os commits preparados

```powershell
git push origin main
git push -u origin back
```

Exige permissão de escrita no repositório. Se `main` estiver protegida, publique a documentação em uma branch e abra um pull request para `main`:

```powershell
git push origin main:docs/sprint-1
```

Não use force push. Se outra pessoa tiver atualizado a origem, faça `git fetch origin`, revise as diferenças e integre os commits antes do envio. Não adicione `.venv`, `node_modules`, CSVs, modelos ou `.env` com `git add -f`.

## Próximas alterações

```powershell
git switch back
git switch -c feat/minha-tarefa
# editar, executar testes e revisar
git add caminho/do/arquivo
git commit -m "feat: descreve a entrega"
git push -u origin feat/minha-tarefa
```

Abra um pull request para `back`. A equipe pode atualizar a documentação em `main` em PRs separados. Evite misturar todo o código de `back` em `main` se quiser preservar a divisão por módulos.

O workflow será habilitado ao enviar `back`. A validação remota só estará confirmada após o GitHub Actions concluir; o resultado local não substitui esse registro.
