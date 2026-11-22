# Orquestração de agentes do Tabletop

Como o maestro (o chat principal do Claude Code) recebe pedidos de várias partes do produto numa mensagem só, divide o trabalho entre agentes especialistas, revisa tudo de forma independente e entrega no `main` com o mínimo de PRs e de minutos de CI.

Uso: no chat principal, `/orquestrar` seguido dos pedidos, um por linha. A fila de PRs é cuidada com `/guardiao-prs`.

## 1. Agentes

| Agente | Modelo | Esforço | Quando usar |
|---|---|---|---|
| `dev-cliente` | sonnet | high | cardápio, carrinho e status no celular; idiomas e estilos |
| `dev-cozinha` | sonnet | high | tela da cozinha: tempo real, sons, cronômetro |
| `dev-painel` | sonnet | high | painel do dono e do gerente: login, financeiro, estoque e custos |
| `dev-backend` | sonnet | high | Supabase (migrations, RLS, funções, seeds, testes do banco) e `app/api` |
| `revisor` | opus | high | revisão independente antes do primeiro push; não edita nada |
| `explorador` | haiku | padrão | buscas amplas no código, só leitura |
| `plataforma-ci` | opus | high | CI, Dependabot, dependências, Vercel |

Definições em `.claude/agents/*.md`. Integrações (iFood, 99Food) e pagamento ganham um agente próprio quando começarem.

## 2. Donos dos arquivos

Cada arquivo tem um dono só. Duas sessões nunca editam o mesmo arquivo ao mesmo tempo; se uma tarefa precisa de um arquivo de outra área, o maestro cria uma tarefa para o dono e marca a dependência.

| Caminho | Dono |
|---|---|
| `app/r/**`, `components/guest/**`, `lib/i18n.ts`, `lib/format.ts`, `lib/menu.ts`, `app/globals.css`, `app/layout.tsx`, `app/page.tsx` | `dev-cliente` |
| `app/kitchen/**` | `dev-cozinha` |
| `app/login/**`, `app/admin/**`, `components/painel/**`, `lib/painel/**` | `dev-painel` |
| `supabase/**`, `app/api/**`, `middleware.ts`, `lib/supabase/**`, `lib/types.ts` | `dev-backend` |
| `.github/**`, `scripts/ci/**`, `.gitignore`, `.env.example`, `package.json`, `package-lock.json`, `next.config.ts`, `tsconfig.json`, `.claude/**`, `docs/ai-agents/**`, `AGENTS.md`, `CLAUDE.md` | `plataforma-ci` |
| `docs/projeto/**`, `docs/prototipos/**`, `docs/planilhas-estoque/**`, `README.md` | maestro |

Migrations: só o `dev-backend` cria, e o maestro define o número da próxima (`NNNN_nome.sql`) antes de abrir a sessão, para duas branches nunca usarem o mesmo.

## 3. Regras de trabalho

### 3.1 Uma worktree por sessão
Cada sessão trabalha na própria worktree, sempre a partir de `origin/main`:

```bash
git fetch origin main
git worktree add .claude/worktrees/<nome> -b <branch> origin/main
```

Nunca editar o checkout principal. Nomes de branch: `<area>/<assunto>` (por exemplo `cliente/filtro-sem-lactose`). Ao terminar o trem, o maestro remove as worktrees com `git worktree remove`.

### 3.2 Revisão antes do primeiro push
1. A sessão termina com commit local e avisa o maestro (relatório com branch, commits, arquivos e verificações).
2. O maestro chama o `revisor` sobre a branch local.
3. Se vier `BLOQUEIOS`, a mesma sessão corrige e o revisor revisa de novo.
4. Só com `APROVADO` sai **um push único** e o PR (em rascunho), com o SHA aprovado no corpo. Assim cada PR roda o CI uma vez só.
5. Toda correção depois do primeiro push (inclusive por CI vermelho no trem) volta ao `revisor`, que revisa o diff desde o SHA aprovado. Nada vai ao GitHub sem `APROVADO`.

### 3.3 Trem de merge
- PRs individuais ficam em **rascunho**, onde o CI não roda.
- Quando dois ou mais estão aprovados pelo revisor, o maestro cria `trem-<AAAA-MM-DD>` a partir de `origin/main` (com sufixo `-2`, `-3` se houver mais de um no dia), faz `git merge --no-ff` de cada branch e abre **um único PR não-rascunho** listando os PRs incluídos.
- Esse PR passa pelo único check obrigatório, `ci-ok`, e entra com **merge commit** (nunca squash nem rebase), para o GitHub fechar cada PR incluído como mergeado.
- Um PR sozinho segue o caminho simples: sai do rascunho, roda o CI e entra com merge commit.

### 3.4 Pré-checagem local antes de todo push de trem
No trem montado, antes do push, o maestro roda:
- `python3 scripts/ci/politica.py --base origin/main` (política: migrations só com acréscimos, nada de `.env` ou chaves, agentes e skills válidos);
- o lint e o typecheck do app (`npm run lint`, `npm run typecheck`), quando o app mudou;
- as suítes das partes que mais de uma branch tocou: `bash scripts/ci/banco.sh` para `supabase/`, `npm test` e `npm run build` para o app.

Cada push que falha gasta o CI inteiro de novo. Se algo não puder rodar localmente (por exemplo, sem npm), o maestro avisa antes de fazer o push.

### 3.5 Nunca "re-run failed jobs"
O `ci-ok` depende do resultado dos outros jobs. Depois de corrigir, sempre a rodada completa (novo push ou "Re-run all jobs").

### 3.6 Merge automático quando verde, só com autorização escrita
O guardião só faz merge quando o dono do repositório escreveu a autorização no chat ("pode fazer o merge do trem X"). Ficam sempre de fora do merge automático:
- **migrações de banco**: PR que toca `supabase/migrations/` só entra com o label `migracao-aprovada`, colocado pelo dono do repositório (o guardião confere quem colocou o label);
- **atualizações major de dependências**.

### 3.7 Dependabot
Configurado em `.github/dependabot.yml`: mensal, poucos PRs abertos e atualizações agrupadas. Os PRs do Dependabot andam num trem próprio (`trem-deps-<data>`), separado do trem de produto. Major fica de fora do merge automático.

### 3.8 Segredos
Segredos nunca passam pelo chat. Quando for preciso guardar uma chave, o maestro entrega um comando de uma linha para o dono rodar, por exemplo:

```bash
gh secret set NOME_DA_CHAVE --repo snowraf31/2027-nosso-
```

O comando pede o valor sem mostrá-lo. `.env.local` nunca entra no repositório (o CI barra).

### 3.9 Aprovações que gastam dinheiro ou publicam
São digitadas pelo dono do repositório na sessão que executa a ação, nunca repassadas pelo maestro. Isso vale para publicar na Vercel, ligar serviço pago, aplicar migration no banco do restaurante e mudar configurações do GitHub.

### 3.10 Banco do restaurante
O banco "teste restaurante" está em uso. Nada é aplicado nele sem o ok do dono; dados de exemplo só em seeds e no ambiente de desenvolvimento.

### 3.11 Commits
Commits pequenos, mensagem em português. As linhas `Co-Authored-By` do Claude ficam nos commits (escolha do dono em 21/11/2026).

## 4. CI e minutos

- O repositório é público: os runners padrão do GitHub Actions não gastam minutos da cota. As regras acima continuam valendo, porque deixam o CI rápido e evitam fila.
- Workflow único em `.github/workflows/ci.yml`:
  - `mudancas`: descobre o que mudou no PR;
  - `politica`: sempre roda;
  - `app`: instalação, typecheck, lint, testes e build, só quando o app mudou;
  - `banco`: aplica as migrations e os seeds num Postgres 16 limpo e roda `supabase/tests/*.sql`, só quando `supabase/` mudou;
  - `ci-ok`: o único check obrigatório; passa só se os outros passaram ou foram pulados por não terem mudança. Em rascunho ele aparece como pulado, o que não conta como verde: vale a rodada da ponta atual do PR.
- Mudança no próprio workflow ou em `scripts/ci/` roda tudo.

## 5. Publicação

Hoje não há deploy: "produção" é o `main`. Quando a Vercel for ligada, o `plataforma-ci` documenta aqui como o `main` vira produção, e a ligação é feita com o ok do dono.
