# Tabletop · Pedido pela mesa (Fase 1)

Sistema de pedidos por QR code / NFC para restaurantes e cafeterias.
O cliente escaneia a placa da mesa, monta o pedido no celular e o pedido cai na tela da cozinha em tempo real.

**Stack:** Next.js 15 (App Router) · Supabase (PostgreSQL, Auth, Realtime) · TypeScript · Vercel

---

## O que já funciona

| Parte | Rota | Descrição |
|---|---|---|
| Menu do cliente | `/r/{restaurante}/t/{token-da-mesa}` | Cardápio, filtros (vegano, sem glúten, sem nozes), alérgenos, adicionais, observação, carrinho salvo no celular |
| Envio do pedido | `POST /api/orders` | O celular manda só IDs e quantidades. Preço, imposto e disponibilidade são validados no banco |
| Status do pedido | `/r/{restaurante}/order/{id}?k=...` | Recebido → Preparando → Pronto → Servido, atualiza sozinho |
| Login da equipe | `/login` | E-mail e senha (Supabase Auth) |
| Tela da cozinha | `/kitchen` | Pedidos em tempo real, cronômetro, alerta sonoro, botão "sold out" por item |

Na Fase 1 todo pedido é **"pay at counter"**. O pagamento online (Stripe) entra na Fase 3.

---

## Passo a passo para rodar

### 1. Criar o projeto no Supabase
1. Crie uma conta em https://supabase.com e um projeto novo (região **East US** se os clientes forem da Flórida).
2. Em **SQL Editor**, rode os arquivos **nesta ordem**, copiando e colando o conteúdo de cada um:
   1. as migrations de `supabase/migrations/`, de `0001` a `0009`, em ordem
   2. `supabase/seed.sql` (cardápio de demonstração "Harbor & Pine" com 12 mesas)
   3. `supabase/seed_experience.sql` (selos, notas do balcão, humores e combinações do cardápio de demonstração)
   4. opcional: `supabase/seed_blogs.sql` (segunda demo, a hamburgueria fictícia "Blogs", mesa em `/r/blogs/t/blogs-table-12`). Com dois restaurantes, a regra "primeiro usuário vira dono" (0006) deixa de valer: crie o usuário **antes** de rodar este arquivo, ou ligue-o à mão com o SQL de funcionários abaixo.

   > Com a Supabase CLI: `supabase link` e depois `supabase db push`. O seed pode ser rodado no SQL Editor.

### 2. Criar o usuário da cozinha
1. Em **Authentication → Users → Add user → Create new user**, informe e-mail e senha e marque **Auto Confirm User**.
2. Pronto: o **primeiro** usuário criado vira automaticamente dono do restaurante (migration 0006).

Para adicionar mais funcionários depois:
```sql
insert into staff (user_id, restaurant_id, role)
select u.id, r.id, 'kitchen'
from auth.users u, restaurants r
where u.email = 'funcionario@exemplo.com' and r.slug = 'harbor-pine';
```

### 3. Configurar e rodar localmente
```bash
cp .env.example .env.local     # cole a URL e a chave anon de Project Settings → API Keys
npm install
npm run dev
```
Abra:
- Menu da mesa 7: http://localhost:3000/r/harbor-pine/t/demo-table-7
- Cozinha: http://localhost:3000/kitchen (abra em outra janela ou no tablet)

Faça um pedido no menu e veja chegar na cozinha. Avance o pedido e veja o status mudar no celular.

> Para testar no celular de verdade na mesma rede, use o IP do computador (ex.: `http://192.168.0.10:3000`). Para HTTPS, use um túnel como o `ngrok`.

### 4. Publicar
1. Suba o projeto para um repositório no GitHub.
2. Em https://vercel.com, importe o repositório e cadastre as mesmas variáveis de ambiente.
3. Em Supabase → Authentication → URL Configuration, adicione o domínio da Vercel.

---

## Gerar os links (e QR codes) das mesas

```sql
select t.label as mesa,
       'https://SEU-DOMINIO.com/r/' || r.slug || '/t/' || t.qr_token as link
from tables t join restaurants r on r.id = t.restaurant_id
where r.slug = 'harbor-pine'
order by t.label::int;
```

Cada link vira um QR code (e pode ser gravado numa etiqueta NFC) para a placa de madeira daquela mesa.
Para restaurantes reais, **não use** os tokens `demo-table-N`: crie as mesas sem informar `qr_token`, que o banco gera um token aleatório.

```sql
insert into tables (restaurant_id, label)
select id, n::text from restaurants, generate_series(1, 15) n where slug = 'novo-restaurante';
```

---

## Como a segurança funciona

- **O preço nunca vem do celular.** A função `place_order` no banco busca preços, valida adicionais (mínimo e máximo por grupo), disponibilidade e calcula imposto, tudo numa única transação.
- **Pedido duplicado não acontece.** Cada envio leva uma `idempotency_key`. Se o Wi-Fi falhar e o cliente tocar de novo, o banco devolve o mesmo pedido.
- **Cliente não acessa as tabelas.** O cliente só consegue chamar três funções do banco (`get_guest_menu`, `place_order`, `get_guest_order`), e cada uma exige o token secreto da mesa ou do pedido. O sistema não usa a chave `service_role`, então não existe chave mestra guardada no servidor.
- **Equipe vê só o próprio restaurante.** Row Level Security (`0002_security.sql`) filtra por `restaurant_id`. Além disso, a equipe só pode alterar o `status` do pedido e a disponibilidade dos itens.
- **Status do pedido** só é visível com o `public_token` que o próprio celular recebeu.

---

## Estrutura

```
app/
  r/[slug]/t/[token]/        menu do cliente (page.tsx + MenuClient.tsx)
  r/[slug]/order/[id]/       status do pedido
  api/orders/route.ts        cria pedido (chama place_order)
  api/orders/[id]/route.ts   status para o cliente
  kitchen/                   tela da cozinha (tempo real)
  login/                     login da equipe
lib/
  supabase/                  clientes: public (cliente, servidor), server (SSR), browser
  menu.ts                    carrega o cardápio de uma mesa
  types.ts, format.ts
supabase/
  migrations/                schema, segurança, realtime
  seed.sql                   restaurante de demonstração
middleware.ts                protege /kitchen e renova a sessão
```

---

## Próximas fases

**Fase 2 · Painel do dono (`/admin`)**
- Cadastro de categorias, itens, adicionais e fotos (Supabase Storage)
- Gestão de mesas e geração/impressão dos QR codes
- Convite de funcionários (papéis owner, manager, kitchen)
- Relatório do dia: vendas, ticket médio, itens mais vendidos

**Fase 3 · Pagamento**
- Stripe Connect (cada restaurante recebe na própria conta)
- Payment Element com Apple Pay e Google Pay, gorjeta
- Webhook `payment_intent.succeeded` → `payment_status = 'paid'`
- Alíquota de imposto por cidade/condado (Stripe Tax)

**Fase 4 · Operação e escala**
- Impressora térmica na cozinha (Epson ePOS / Star CloudPRNT)
- Integração com Square POS
- Cobrança da mensalidade (Stripe Billing)
- Limite de requisições na API (ex.: Upstash Ratelimit) e monitoramento (Sentry)

---

## Limitações conhecidas desta versão

- O menu do cliente mostra "sold out" ao carregar a página. Se um item acabar enquanto o cliente navega, o envio é recusado com uma mensagem clara e o menu é atualizado.
- O status do cliente é atualizado por consulta a cada 4 segundos (o cliente não faz login, então não usa o canal em tempo real).
- Um usuário da equipe ligado a vários restaurantes vê apenas o primeiro na cozinha.

---

## O menu do cliente (visual e experiência)

O menu foi pensado como o balcão de um café ensolarado da Flórida: fundo cor de sálvia, tinta verde-palmeira, toques de goiaba e manga, desenhos feitos à mão e bilhetes escritos à mão pela equipe.

**O que o cliente encontra**
- **Saudação pela hora do dia** e o número da mesa sempre visível.
- **"In the mood for"**: Coffee fix, Something light, Big appetite, A little sweet. Um toque filtra o cardápio.
- **Filtros de dieta** (vegano, sem glúten, sem nozes), combináveis com o humor.
- **Destaque da casa** com selo e uma frase do balcão.
- **Adicionar em um toque** com o botão +, já com as escolhas padrão. Um aviso mostra o que entrou e oferece "Customize".
- **Ficha do prato** com escolhas em botões grandes, nota do balcão, alérgenos, observação para a cozinha e **"goes great with"** para levar a combinação junto.
- **Carrinho** com edição, sugestões ("anything else?") e total com imposto.
- **Status do pedido** com barra de progresso e textos amigáveis.
- Modo claro e escuro automáticos, conforme o celular.

**O que o dono controla (no banco, por enquanto via SQL; no painel na Fase 2)**

| Campo | Onde | Exemplo |
|---|---|---|
| `tagline` | restaurants | "Coffee, Cuban bakes and slow mornings in St. Pete" |
| `note` | menu_categories | "Pulled to order" |
| `icon` | menu_categories | `cup`, `egg`, `sandwich`, `pastry`, `leaf`, `bowl`, `fork`, `glass` |
| `badge` | menu_items | "House favorite" (vira o destaque do topo), "Staff pick", "Fresh today" |
| `story` | menu_items | "Baked at 6am. When they're gone, they're gone." |
| `moods` | menu_items | `{coffee}`, `{light,sweet}`, `{hearty}` |
| `pairs_with` | menu_items | ids dos itens que combinam |
| `photo_url` | menu_items | se tiver foto, ela substitui o desenho |

Todos são opcionais: sem eles o menu continua funcionando, só com menos personalidade.

### Identidade visual por restaurante

Cada restaurante escolhe o visual do menu no campo `restaurants.brand_style`:

| Valor | Para quem | Visual |
|---|---|---|
| `harbor` (padrão) | cafés, padarias, brunch | sálvia, verde-palmeira, goiaba e manga; títulos estreitos; anotações em caneta fina |
| `diner` | hamburguerias, lanchonetes | papel de açougue, carvão, ketchup e mostarda; títulos encorpados; anotações em marcador |

```sql
update restaurants set brand_style = 'diner' where slug = 'blogs';
```

Ícones de categoria disponíveis: `cup`, `egg`, `sandwich`, `pastry`, `leaf`, `bowl`, `fork`, `glass`, `burger`, `fries`, `shake`, `flame`. Humores: `coffee`, `light`, `hearty`, `spicy`, `sweet` (só aparecem os que existem no cardápio).

Para criar um estilo novo: um bloco de cores e fontes em `app/globals.css` (copie o do `diner`), o valor na migration (`check (brand_style in (...))`) e, se quiser, os desenhos do status em `OrderStatus.tsx`.

### Idioma, moeda e imposto por restaurante (migration 0009)

| Campo | Valores | Efeito |
|---|---|---|
| `restaurants.locale` | `en` (padrão), `pt-BR` | idioma das telas do cliente (menu, carrinho, status) |
| `restaurants.currency` | `USD` (padrão), `BRL`… | moeda dos preços |
| `restaurants.tax_rate` | ex.: `0.07` nos EUA, `0` no Brasil | com `0`, a linha de imposto some e o total é a soma dos itens |

Restaurante brasileiro:
```sql
update restaurants set locale = 'pt-BR', currency = 'BRL', tax_rate = 0, timezone = 'America/Sao_Paulo' where slug = 'meu-cafe';
```

As traduções ficam em `lib/i18n.ts`, com o texto em inglês como chave. Uma frase sem tradução aparece em inglês.
