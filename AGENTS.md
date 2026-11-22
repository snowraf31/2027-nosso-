# Tabletop: instruções para agentes

Pedido pela mesa via QR code ou NFC: o cliente pede pelo celular, o pedido chega na cozinha em tempo real e o dono acompanha as vendas. Next.js 15 (App Router) + TypeScript + Supabase (PostgreSQL, Auth, Realtime); publicação prevista na Vercel. Detalhes em `README.md`.

## Mapa
- Cliente (celular): `app/r/**`, `components/guest/**`
- Cozinha: `app/kitchen/**`
- Painel do dono e do gerente: `app/login/**`, `app/admin/**` (a construir)
- Backend: `supabase/**` (migrations, seeds, testes), `app/api/**`, `middleware.ts`, `lib/supabase/**`
- Pedidos e protótipos: `docs/projeto/`, `docs/prototipos/`, `docs/planilhas-estoque/`

## Regras do produto
- Vários restaurantes no mesmo banco, separados por `restaurant_id` com RLS. Ninguém vê dados de outro restaurante.
- O cliente não lê tabelas: só chama funções que exigem o token da mesa ou do pedido. O preço nunca vem do celular.
- Dinheiro em centavos inteiros. Todo envio de pedido é idempotente.
- A cozinha está em uso: comportamento, sons, tempos e aparência só mudam com pedido explícito.
- Banco: migrations só com acréscimos; nada é aplicado no banco do restaurante sem o ok do dono.
- Segredos nunca no repositório nem no chat.

## Orquestração (resumo)
Regras completas: `docs/ai-agents/orquestracao.md`.
- Pedidos de várias partes: `/orquestrar`. Fila de PRs e trem de merge: `/guardiao-prs`.
- Agentes em `.claude/agents/`: `dev-cliente`, `dev-cozinha`, `dev-painel`, `dev-backend` (sonnet, high), `revisor` (opus, high), `explorador` (haiku), `plataforma-ci` (opus, high). Cada arquivo tem um dono só.
- Uma worktree por sessão, sempre a partir de `origin/main` em `.claude/worktrees/<nome>`. Nunca editar o checkout principal.
- O revisor revisa a branch local antes do primeiro push; depois sai um push único.
- PRs individuais em rascunho (sem CI); dois ou mais aprovados viram um trem `trem-<data>` com um PR só, um check obrigatório (`ci-ok`) e merge commit.
- Pré-checagem local antes de todo push de trem. Nunca "re-run failed jobs".
- Merge só com autorização escrita do dono. Migrations (label `migracao-aprovada`, só o dono coloca) e atualizações major ficam fora do merge automático.
- Aprovações que gastam dinheiro ou publicam são digitadas pelo dono na sessão que executa.

## Verificações
- Política: `python3 scripts/ci/politica.py --base origin/main`
- Banco: `bash scripts/ci/banco.sh` (precisa de um Postgres 17 limpo, igual ao Supabase real e ao CI; o 16 também serve para rodar local; variáveis `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`)
- App: `npm run typecheck`, `npm run lint`, `npm test`, `npm run build` (os que existirem)
