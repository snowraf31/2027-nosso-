/**
 * Tiny i18n for the guest screens. English text is the key, so an English
 * restaurant needs no dictionary and a missing translation falls back to English.
 * Variables use {name}: t("Table {n}", { n: 7 }).
 */

export type Locale = "en" | "pt-BR";

const PT: Record<string, string> = {
  // hero & navigation
  "Good morning": "Bom dia",
  "Good afternoon": "Boa tarde",
  "Good evening": "Boa noite",
  "Up late": "Boa noite",
  "Welcome in.": "Que bom te ver.",
  "What sounds good?": "O que vai ser hoje?",
  "order here, we'll bring it to you ↓": "peça por aqui, a gente leva até você ↓",
  "Table {n}": "Mesa {n}",
  "Order #{n} is with the kitchen": "Pedido nº {n} está na cozinha",
  "Track →": "Acompanhar →",
  "What are you in the mood for?": "Do que você está com vontade?",
  "In the mood for": "Com vontade de",
  "Dietary needs": "Restrições alimentares",
  "Menu sections": "Seções do cardápio",
  "Suggestions": "Sugestões",
  // moods
  "Coffee fix": "Um cafezinho",
  "Something light": "Algo leve",
  "Big appetite": "Fome de verdade",
  "Bring the heat": "Apimentado",
  "A little sweet": "Um docinho",
  // diet & allergens
  Vegan: "Vegano",
  "Gluten-free": "Sem glúten",
  "Nut-free": "Sem nozes",
  "Lactose-free": "Sem lactose",
  "Contains nuts": "Contém castanhas",
  "Tree nuts": "Castanhas",
  Peanuts: "Amendoim",
  Dairy: "Leite",
  Gluten: "Glúten",
  Egg: "Ovo",
  Soy: "Soja",
  Sesame: "Gergelim",
  Shellfish: "Frutos do mar",
  Fish: "Peixe",
  // featured & list
  "House favorite": "Favorito da casa",
  "See details": "Ver detalhes",
  "Add to order": "Adicionar",
  "{n} dish": "{n} item",
  "{n} dishes": "{n} itens",
  for: "para",
  Clear: "Limpar",
  "Nothing fits that combination.": "Nada combina com esses filtros.",
  "Show everything": "Mostrar tudo",
  "Nothing here right now.": "Nada por aqui agora.",
  "sold out": "esgotado",
  "Add {name}": "Adicionar {name}",
  "Add another {name} ({n} in your order)": "Adicionar mais um {name} ({n} no pedido)",
  "thanks for stopping by ♥": "obrigado pela visita ♥",
  "Review order": "Ver pedido",
  // toast
  "{name} added": "{name} adicionado",
  "{a} + {b} added": "{a} + {b} adicionados",
  Customize: "Personalizar",
  // cart
  "Back to the menu": "Voltar ao cardápio",
  "Your order": "Seu pedido",
  "Nothing here yet.": "Nada por aqui ainda.",
  "Browse the menu": "Ver o cardápio",
  Edit: "Editar",
  "anything else?": "mais alguma coisa?",
  Subtotal: "Subtotal",
  "Sales tax": "Impostos",
  Total: "Total",
  "You'll pay at the counter when you're done. No rush.": "Você paga no caixa quando terminar. Sem pressa.",
  "Sending to the kitchen…": "Enviando para a cozinha…",
  "Send to the kitchen": "Enviar para a cozinha",
  "We couldn't send your order. Please try again.": "Não conseguimos enviar seu pedido. Tente de novo.",
  "No connection. Check your Wi-Fi and tap Send again. You won't be charged twice.":
    "Sem conexão. Confira o Wi-Fi e toque em Enviar de novo. O pedido não vai duplicar.",
  // stepper
  "Remove {name}": "Remover {name}",
  "One less {name}": "Um {name} a menos",
  "One more {name}": "Mais um {name}",
  // sheet
  Close: "Fechar",
  "from the counter": "do balcão",
  Contains: "Contém",
  "Tell your server about any allergy.": "Avise a equipe sobre qualquer alergia.",
  "Pick one": "Escolha 1",
  "Pick {a}–{b}": "Escolha de {a} a {b}",
  Optional: "Opcional",
  "Up to {n}": "Até {n}",
  "Note for the kitchen": "Observação para a cozinha",
  "No onions, extra hot, allergy…": "Sem cebola, bem quente, alergia…",
  "+ Add a note for the kitchen": "+ Adicionar observação para a cozinha",
  "goes great with": "combina com",
  Added: "Adicionado",
  Add: "Adicionar",
  "Pick a {group}": "Escolha: {group}",
  "Update · {price}": "Atualizar · {price}",
  "Add to order · {price}": "Adicionar · {price}",
  // order status
  Received: "Recebido",
  "Making it": "Preparando",
  "On its way": "A caminho",
  "Got it!": "Recebido!",
  "Your order is with the kitchen.": "Seu pedido já está na cozinha.",
  "Making it now.": "Preparando agora.",
  "Sit back. We'll bring everything to your table.": "Pode relaxar. A gente leva tudo até a sua mesa.",
  "Ready!": "Prontinho!",
  "A server is bringing it over right now.": "Já está saindo para a sua mesa.",
  "Enjoy.": "Bom apetite.",
  "Need anything else? Just order again from your phone.": "Quer mais alguma coisa? É só pedir de novo pelo celular.",
  "Order cancelled": "Pedido cancelado",
  "Please check with a server at the counter.": "Fale com a equipe no caixa, por favor.",
  "We can't find that order.": "Não encontramos esse pedido.",
  "Please ask a server at the counter.": "Fale com a equipe no caixa, por favor.",
  "Checking on your order…": "Conferindo seu pedido…",
  "order #{n}": "pedido nº {n}",
  "Order progress": "Andamento do pedido",
  "Total, pay at the counter": "Total, pagar no caixa",
  "Order something else": "Pedir mais alguma coisa",
  // kitchen display
  Kitchen: "Cozinha",
  Live: "Ao vivo",
  "Open {n}": "Abertos {n}",
  Open: "Abertos",
  "Avg wait": "Espera média",
  New: "Novos",
  Preparing: "Em preparo",
  "Ready to run": "Pronto para servir",
  Start: "Iniciar",
  "Mark ready": "Marcar pronto",
  Served: "Servido",
  "New orders appear here.": "Os pedidos novos aparecem aqui.",
  "Nothing here.": "Nada aqui.",
  "Menu availability": "Disponibilidade do cardápio",
  "Switch an item off when it runs out. Guests see it as sold out right away.":
    "Desligue um item quando acabar. O cliente vê como esgotado na hora.",
  "Pay at counter": "Pagar no caixa",
  "{name} available": "{name} disponível",
  "Turn on sound": "Ligar som",
  "Auto traffic": "Movimento automático",
  // owner dashboard
  Today: "Hoje",
  Menu: "Cardápio",
  "Tables & QR": "Mesas e QR",
  "Look & feel": "Aparência",
  "Owner dashboard": "Painel do dono",
  "Dashboard sections": "Seções do painel",
  "Saved. Guests see it now.": "Salvo. O cliente já vê a mudança.",
  "Today at a glance": "Resumo de hoje",
  "Sales today": "Vendas hoje",
  "Sales, last 24 h": "Vendas nas últimas 24 h",
  "{n} orders": "{n} pedidos",
  "Average ticket": "Ticket médio",
  "per order": "por pedido",
  "Kitchen time": "Tempo de cozinha",
  "{n} min": "{n} min",
  "order placed → ready": "do pedido até ficar pronto",
  "Open right now": "Abertos agora",
  "{n} waiting over 10 min": "{n} esperando há mais de 10 min",
  "all on time": "tudo no tempo",
  "Sales by hour": "Vendas por hora",
  "tap a bar for details": "toque numa barra para ver",
  "Best sellers": "Mais vendidos",
  "items sold": "itens vendidos",
  "Latest orders": "Últimos pedidos",
  "updates live": "atualiza ao vivo",
  Order: "Pedido",
  Table: "Mesa",
  Items: "Itens",
  Time: "Hora",
  Status: "Situação",
  "{price} from {n} orders": "{price} em {n} pedidos",
  "{price} from {n} order": "{price} em {n} pedido",
  Ready: "Pronto",
  Cancelled: "Cancelado",
  "Change prices, mark items sold out, add a badge or a line from the counter. Everything updates on guests' phones right away.":
    "Mude preços, marque itens esgotados, coloque um selo ou uma frase do balcão. Tudo aparece no celular do cliente na hora.",
  "{n} item is sold out.": "{n} item esgotado.",
  "{n} items are sold out.": "{n} itens esgotados.",
  "Price for {name}": "Preço de {name}",
  "On menu": "No cardápio",
  "Sold out": "Esgotado",
  Done: "Pronto",
  "Edit details for {name}": "Editar detalhes de {name}",
  "Close details for {name}": "Fechar detalhes de {name}",
  Badge: "Selo",
  "No badge": "Sem selo",
  "\"House favorite\" becomes the big card at the top of the menu.": "\"Favorito da casa\" vira o destaque no topo do cardápio.",
  "A line from the counter": "Uma frase do balcão",
  "Something only you would say about this dish": "Algo que só vocês diriam sobre esse item",
  "{n}/160 · shown in handwriting": "{n}/160 · aparece em destaque no cardápio",
  "Shows up when guests are in the mood for": "Aparece quando o cliente está com vontade de",
  "Each table has its own code for the table plaque. Scanning it (or tapping the NFC tag) opens the menu with the table already set. Links use {domain} until you connect your domain.":
    "Cada mesa tem o próprio código para a placa. Ao escanear (ou aproximar o celular da etiqueta NFC), o cardápio abre com a mesa já marcada. Os links usam {domain} até vocês conectarem o domínio.",
  "No open order": "Sem pedido aberto",
  "Copy link": "Copiar link",
  Copied: "Copiado",
  "Select the link below": "Selecione o link abaixo",
  "Pick the look of your guest menu and how you introduce yourself. Changes go live immediately.":
    "Escolha o visual do cardápio e como vocês se apresentam. As mudanças valem na hora.",
  "Menu style": "Estilo do cardápio",
  "in use": "em uso",
  "Tagline under the greeting": "Frase abaixo da saudação",
  "See it on the guest menu": "Ver no cardápio do cliente",
  "Cafés, bakeries, brunch spots": "Cafés, padarias e brunch",
  "Burger joints, lunch counters": "Hamburguerias e lanchonetes",
  "Cafés and patisseries": "Cafés e confeitarias",
};

const DICTS: Record<string, Record<string, string>> = { "pt-BR": PT };

export type T = (key: string, vars?: Record<string, string | number>) => string;

export function makeT(locale?: string | null): T {
  const d = DICTS[locale ?? "en"];
  return (key, vars) => {
    let s = d?.[key] ?? key;
    if (vars) for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v));
    return s;
  };
}

export function makeMoney(locale?: string | null, currency?: string | null) {
  const f = new Intl.NumberFormat(locale === "pt-BR" ? "pt-BR" : "en-US", { style: "currency", currency: currency ?? "USD" });
  return (cents: number) => f.format(cents / 100);
}

export type Fmt = { t: T; money: (cents: number) => string; locale: string };
export function makeFmt(locale?: string | null, currency?: string | null): Fmt {
  return { t: makeT(locale), money: makeMoney(locale, currency), locale: locale ?? "en" };
}
