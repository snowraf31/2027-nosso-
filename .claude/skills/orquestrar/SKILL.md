---
name: orquestrar
description: Maestro do Tabletop. Recebe numa mensagem só pedidos de várias partes do produto (cliente, cozinha, painel, backend, CI), monta o plano com área, agente, modelo, esforço e dependências, abre uma sessão por tarefa independente, manda revisar e acompanha até o main. Use quando o usuário mandar /orquestrar com uma lista de pedidos.
argument-hint: "<pedidos, um por linha: Área: o que fazer (aceite: ...)>"
disable-model-invocation: true
---

# /orquestrar

Você é o maestro. Você não escreve código de produto: você planeja, delega, confere e entrega. As regras completas estão em `docs/ai-agents/orquestracao.md`; leia antes de começar se ainda não leu nesta sessão.

Pedidos recebidos:

$ARGUMENTS

## 1. Entender
- Separe os pedidos. Para cada um, anote o critério de aceite. Se faltar e o pedido for ambíguo, pergunte antes de abrir sessões (uma pergunta só, com todas as dúvidas).
- Se precisar mapear o código, use o `explorador` (só leitura) em vez de ler tudo você mesmo.

## 2. Planejar
Responda com uma tabela e espere o ok do usuário antes de abrir as sessões:

| # | Tarefa | Área | Agente | Modelo / esforço | Branch | Depende de | Arquivos principais |
|---|---|---|---|---|---|---|---|

Regras do plano:
- Um agente por área, conforme a tabela de donos (seção 2 do documento de regras). Cada arquivo tem um dono só: se duas tarefas precisam do mesmo arquivo, uma delas vira dependência da outra ou as duas viram uma tarefa só.
- Migration nova: só no `dev-backend`, e você define o número (`NNNN`) olhando `supabase/migrations/` no `origin/main` e as branches abertas.
- Tarefa que muda a cozinha (comportamento, som, tempo, aparência) ou os números que o gerente já vê: marque como "precisa de ok" e não abra a sessão sem o ok explícito.
- Tarefas independentes rodam em paralelo; dependentes esperam a anterior chegar ao `main` (ou, se combinado, partem da branch da anterior e entram no mesmo trem).

## 3. Abrir as sessões
Para cada tarefa liberada:
1. Crie a worktree a partir de `origin/main`:
   ```bash
   git fetch origin main
   git worktree add .claude/worktrees/<nome> -b <area>/<assunto> origin/main
   ```
2. Abra a sessão com o agente da área (ferramenta Agent, `subagent_type` = nome do agente, em segundo plano). No pedido ao agente inclua: o caminho absoluto da worktree, a branch, o pedido e o critério de aceite, os arquivos que ele pode tocar, o número da migration (se houver) e a instrução de terminar com commit local e relatório, sem push.
3. Avise o usuário em uma linha por sessão aberta.

## 4. Revisar antes do primeiro push
Quando uma sessão terminar:
1. Confira o relatório: os commits existem (`git -C <worktree> log origin/main..HEAD`), só arquivos da área foram tocados.
2. Chame o `revisor` com a worktree, a branch e a base `origin/main`.
3. `BLOQUEIOS`: devolva os achados para a mesma sessão (SendMessage para o agente) corrigir; depois revise de novo.
4. `APROVADO`: faça um push único e abra o PR em rascunho:
   ```bash
   git -C <worktree> push -u origin <branch>
   gh pr create --draft --base main --head <branch> --title "<título>" --body "<o que muda, aceite, verificações, aprovado pelo revisor>"
   ```
5. Avise o usuário: PR aberto, resultado da revisão.
6. Qualquer correção depois do primeiro push volta ao `revisor` (diff desde o SHA aprovado) antes de ser enviada.

## 5. Entregar
- Dois ou mais PRs aprovados: use a skill `guardiao-prs` para montar o trem.
- Um PR sozinho: siga o caminho simples do guardião (tirar do rascunho, CI, merge com autorização).
- Merge só com a autorização escrita do usuário. Migrations e atualizações major ficam de fora do merge automático.

## 6. Avisar a cada etapa
Uma linha por evento: plano pronto, sessão aberta, revisão (aprovado ou bloqueios), PR aberto, trem montado, CI (verde ou vermelho, com o job), merge, publicação.

## 7. Fechar
No fim, responda com:
- os links dos PRs (individuais e do trem) e o estado de cada um;
- o que ficou pendente com o usuário (ok de merge, label de migration, ok de mudança na cozinha, segredos a cadastrar com o comando de uma linha);
- as worktrees removidas (`git worktree remove`) depois do merge.

## Nunca
- Editar o checkout principal ou fazer push sem revisão.
- Pedir ou receber segredos pelo chat.
- Repassar aprovação de gasto ou publicação: o usuário digita na sessão que executa.
- Usar "re-run failed jobs".
