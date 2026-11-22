---
name: guardiao-prs
description: Guardião dos PRs do Tabletop. Acompanha os PRs abertos, junta os aprovados num trem de merge (um PR só, um CI só), faz a pré-checagem local e faz o merge com merge commit quando o ci-ok fica verde e o usuário autorizou por escrito. Use com /guardiao-prs ou quando o maestro tiver dois ou mais PRs aprovados.
argument-hint: "[números dos PRs, ou vazio para todos os aprovados]"
disable-model-invocation: true
---

# /guardiao-prs

Regras completas em `docs/ai-agents/orquestracao.md` (seção 3).

PRs pedidos: $ARGUMENTS

## 1. Levantar a fila
```bash
gh pr list --repo snowraf31/2027-nosso- --state open --json number,title,headRefName,isDraft,author,labels,files
```
Classifique cada PR:
- **pronto**: aprovado pelo revisor (está no corpo do PR), em rascunho, sem conflito com `main`;
- **de dependência**: autor `dependabot` (vai num trem próprio, `trem-deps-<data>`);
- **fora do merge automático**: toca `supabase/migrations/` sem o label `migracao-aprovada`, ou é atualização major de dependência.

Para o label de migration, confira quem colocou: só vale se foi o dono do repositório.
```bash
gh api repos/snowraf31/2027-nosso-/issues/<n>/events --jq '.[] | select(.event=="labeled" and .label.name=="migracao-aprovada") | .actor.login'
```

## 2. Um PR só: caminho simples
```bash
gh pr ready <n>
gh pr checks <n> --watch --required
```
Com `ci-ok` verde e autorização escrita do usuário: `gh pr merge <n> --merge --delete-branch`.

## 3. Dois ou mais: montar o trem
1. Crie o trem a partir de `origin/main`, numa worktree própria:
   ```bash
   git fetch origin main
   git worktree add .claude/worktrees/trem-<data> -b trem-<data> origin/main
   ```
2. Faça o merge de cada branch, na ordem das dependências:
   ```bash
   git -C .claude/worktrees/trem-<data> fetch origin <branch>
   git -C .claude/worktrees/trem-<data> merge --no-ff origin/<branch> -m "Trem: <branch> (#<n>)"
   ```
   Conflito: pare, tire o PR do trem e avise o maestro. Não resolva conflito de área que não é sua sem a sessão dona.
3. **Pré-checagem local** no trem montado, antes do push (cada push que falha gasta o CI inteiro de novo):
   - `python3 scripts/ci/politica.py --base origin/main`
   - `npm run lint` e `npm run typecheck`, se o app mudou
   - as suítes das partes que mais de uma branch tocou: `bash scripts/ci/banco.sh` para `supabase/`; `npm test` e `npm run build` para o app

   Se algo não puder rodar localmente, avise o usuário antes do push.
4. Push e PR único, não-rascunho:
   ```bash
   git -C .claude/worktrees/trem-<data> push -u origin trem-<data>
   gh pr create --base main --head trem-<data> --title "Trem <data>: <resumo>" --body "Inclui: #<n1>, #<n2> ..."
   ```
   No corpo, liste cada PR incluído com o título e o resultado do revisor.
5. Acompanhe o check obrigatório: `gh pr checks <trem> --watch --required`.
   - Vermelho: descubra o job e a branch culpada, tire-a do trem ou peça a correção à sessão dona, monte de novo e repita a pré-checagem. Nunca "re-run failed jobs".
6. Verde: avise o usuário e espere a autorização escrita. Com ela:
   ```bash
   gh pr merge <trem> --merge --delete-branch
   ```
   Sempre `--merge` (merge commit), nunca squash ou rebase, para o GitHub fechar cada PR incluído como mergeado.
7. Confira que os PRs incluídos aparecem como "Merged". Se algum ficou aberto, avise.
8. Limpe: `git worktree remove` do trem e das sessões incluídas.

## 4. Relatório
Uma linha por PR: número, título, estado (no trem, mergeado, fora do automático e por quê, com conflito). No fim, o que depende do usuário: autorização de merge, label de migration, revisão de major.

## Nunca
- Fazer merge sem a autorização escrita do usuário.
- Fazer merge de migration sem o label colocado pelo dono, ou de atualização major.
- Usar squash ou rebase no trem.
- Juntar Dependabot e produto no mesmo trem.
