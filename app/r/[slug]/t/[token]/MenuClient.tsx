"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { GuestMenu, MenuItem } from "@/lib/types";
import { ALLERGEN_LABEL, DIETARY_LABEL, estimateTax } from "@/lib/format";
import { makeFmt, type Fmt } from "@/lib/i18n";
import {
  Doodle,
  MOODS,
  defaultPicked,
  greetingFor,
  lineFrom,
  pickedFromLine,
  readStore,
  sameLine,
  writeStore,
  type CartLine,
  type Picked,
} from "@/components/guest/ui";

type LastOrder = { id: string; number: number; k: string };
type SheetState = { item: MenuItem; editKey?: string };
type Toast = { id: number; title: string; detail: string; lineKey?: string };

const DIETS = ["vegan", "gf", "lf", "nf"] as const;
const TINTS = 4;

export default function MenuClient({ menu }: { menu: GuestMenu }) {
  const router = useRouter();
  const cartKey = `tabletop:cart:${menu.token}`;
  const lastKey = `tabletop:last:${menu.token}`;
  const menuPath = `/r/${menu.restaurant.slug}/t/${menu.token}`;
  const brand = menu.restaurant.brand_style ?? "harbor";
  const L = useMemo(() => makeFmt(menu.restaurant.locale, menu.restaurant.currency), [menu.restaurant.locale, menu.restaurant.currency]);
  const { t, money } = L;
  const showTax = menu.restaurant.tax_rate > 0;

  const [cart, setCart] = useState<CartLine[]>([]);
  const [lastOrder, setLastOrder] = useState<LastOrder | null>(null);
  const [hydrated, setHydrated] = useState(false);
  const [greeting, setGreeting] = useState<string | null>(null);
  const [diets, setDiets] = useState<Set<string>>(new Set());
  const [mood, setMood] = useState<string | null>(null);
  const [activeCat, setActiveCat] = useState(menu.categories[0]?.id ?? "");
  const [view, setView] = useState<"menu" | "cart">("menu");
  const [sheet, setSheet] = useState<SheetState | null>(null);
  const [toast, setToast] = useState<Toast | null>(null);
  const [bump, setBump] = useState(0);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const idempotencyKey = useRef<string | null>(null);
  const navRef = useRef<HTMLElement | null>(null);

  /* ---------- lookups ---------- */
  const byId = useMemo(() => new Map(menu.items.map((i) => [i.id, i])), [menu.items]);
  const tintOf = useMemo(() => {
    const m = new Map<string, number>();
    menu.categories.forEach((c, i) => m.set(c.id, (i % TINTS) + 1));
    return (item: MenuItem) => m.get(item.category_id ?? "") ?? 1;
  }, [menu.categories]);
  const iconOf = useMemo(() => {
    const m = new Map(menu.categories.map((c) => [c.id, c.icon]));
    return (item: MenuItem) => m.get(item.category_id ?? "") ?? "bowl";
  }, [menu.categories]);

  // Screen readers and translation tools read the page in the restaurant's language
  useEffect(() => {
    document.documentElement.lang = L.locale === "pt-BR" ? "pt-BR" : "en";
  }, [L.locale]);

  /* ---------- restore cart, greeting ---------- */
  useEffect(() => {
    setCart(readStore<CartLine[]>(cartKey, []));
    setLastOrder(readStore<LastOrder | null>(lastKey, null));
    setGreeting(greetingFor());
    setHydrated(true);
  }, [cartKey, lastKey]);

  useEffect(() => {
    if (hydrated) writeStore(cartKey, cart.length ? cart : null);
    idempotencyKey.current = null; // a changed cart is a new order attempt
  }, [cart, cartKey, hydrated]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3600);
    return () => clearTimeout(t);
  }, [toast]);

  /* ---------- filtering ---------- */
  const matches = (i: MenuItem) =>
    [...diets].every((d) => i.dietary_tags.includes(d)) && (!mood || i.moods.includes(mood));
  const filtering = diets.size > 0 || mood !== null;

  const sections = useMemo(
    () =>
      menu.categories
        .map((c) => ({ ...c, items: menu.items.filter((i) => i.category_id === c.id && matches(i)) }))
        .filter((c) => !filtering || c.items.length > 0),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [menu, diets, mood]
  );
  const shownCount = sections.reduce((a, s) => a + s.items.length, 0);
  const moodsHere = MOODS.filter((m) => menu.items.some((i) => i.moods.includes(m.key)));
  const dietsHere = DIETS.filter((d) => menu.items.some((i) => i.dietary_tags.includes(d)));
  const featured =
    menu.items.find((i) => i.available && (i.badge === "House favorite" || i.badge === t("House favorite"))) ??
    menu.items.find((i) => i.available && i.badge && i.story) ??
    null;

  /* ---------- cart math ---------- */
  const count = cart.reduce((a, l) => a + l.qty, 0);
  const subtotal = cart.reduce((a, l) => a + l.unitCents * l.qty, 0);
  const tax = estimateTax(subtotal, menu.restaurant.tax_rate);
  const inCart = useMemo(() => {
    const m = new Map<string, number>();
    cart.forEach((l) => m.set(l.itemId, (m.get(l.itemId) ?? 0) + l.qty));
    return m;
  }, [cart]);

  /* ---------- category tracking ---------- */
  useEffect(() => {
    if (view !== "menu") return;
    const els = sections.map((s) => document.getElementById(`cat-${s.id}`)).filter((e): e is HTMLElement => !!e);
    const obs = new IntersectionObserver(
      (entries) => {
        const top = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
        if (top) setActiveCat(top.target.id.slice(4));
      },
      { rootMargin: "-90px 0px -65% 0px" }
    );
    els.forEach((e) => obs.observe(e));
    return () => obs.disconnect();
  }, [view, sections]);

  // Keep the active tab visible in the tab bar (scrolls the bar only, never the page)
  useEffect(() => {
    const nav = navRef.current;
    const tab = nav?.querySelector<HTMLElement>(`[data-cat="${activeCat}"]`);
    if (nav && tab) nav.scrollTo({ left: tab.offsetLeft - (nav.clientWidth - tab.clientWidth) / 2, behavior: "smooth" });
  }, [activeCat]);

  function pickMood(key: string) {
    const turningOn = mood !== key;
    setMood(turningOn ? key : null);
    if (turningOn) {
      requestAnimationFrame(() =>
        document.getElementById("g-results")?.scrollIntoView({ behavior: "smooth", block: "start" })
      );
    }
  }

  function jumpTo(id: string) {
    setActiveCat(id);
    document.getElementById(`cat-${id}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  /* ---------- cart actions ---------- */
  function addLine(line: Omit<CartLine, "key">): string {
    const same = cart.find((l) => sameLine(l, line));
    const key = same?.key ?? `${line.itemId}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
    setCart((prev) =>
      prev.some((l) => l.key === key)
        ? prev.map((l) => (l.key === key ? { ...l, qty: Math.min(20, l.qty + line.qty) } : l))
        : [...prev, { ...line, key }]
    );
    setBump((b) => b + 1);
    return key;
  }

  function quickAdd(item: MenuItem) {
    const picked = defaultPicked(item);
    if (!item.available) return;
    if (!picked) return setSheet({ item });
    const line = lineFrom(item, picked, 1, "");
    const key = addLine(line);
    setToast({ id: Date.now(), title: t("{name} added", { name: item.name }), detail: line.optionNames.join(" · "), lineKey: key });
  }

  function saveFromSheet(line: Omit<CartLine, "key">, pair: Omit<CartLine, "key"> | null, editKey?: string) {
    if (editKey) {
      setCart((prev) => prev.map((l) => (l.key === editKey ? { ...line, key: editKey } : l)));
    } else {
      addLine(line);
    }
    if (pair) addLine(pair);
    setSheet(null);
    if (!editKey) {
      setToast({
        id: Date.now(),
        title: pair ? t("{a} + {b} added", { a: line.name, b: pair.name }) : t("{name} added", { name: `${line.qty > 1 ? `${line.qty} × ` : ""}${line.name}` }),
        detail: line.optionNames.join(" · "),
      });
    }
  }

  function changeQty(key: string, delta: number) {
    setCart((prev) =>
      prev.flatMap((l) => (l.key !== key ? [l] : l.qty + delta < 1 ? [] : [{ ...l, qty: Math.min(20, l.qty + delta) }]))
    );
  }

  function editLine(key: string) {
    const line = cart.find((l) => l.key === key);
    const item = line && byId.get(line.itemId);
    if (item) setSheet({ item, editKey: key });
    setToast(null);
  }

  function toggleDiet(d: string) {
    setDiets((prev) => {
      const next = new Set(prev);
      if (next.has(d)) next.delete(d);
      else next.add(d);
      return next;
    });
  }

  /* ---------- send ---------- */
  async function placeOrder() {
    if (!cart.length || sending) return;
    setSending(true);
    setError(null);
    idempotencyKey.current ??= crypto.randomUUID();
    try {
      const res = await fetch("/api/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          table_token: menu.token,
          idempotency_key: idempotencyKey.current,
          payment_method: "counter",
          items: cart.map((l) => ({ menu_item_id: l.itemId, quantity: l.qty, option_ids: l.optionIds, note: l.note || undefined })),
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(data.error ?? t("We couldn't send your order. Please try again."));
        if (res.status === 409) router.refresh(); // pick up sold-out changes
        return;
      }
      writeStore(lastKey, { id: data.id, number: data.number, k: data.public_token });
      writeStore(cartKey, null);
      writeStore("tabletop:return", menuPath, true);
      writeStore("tabletop:brand", brand, true);
      writeStore("tabletop:locale", { locale: menu.restaurant.locale ?? null, currency: menu.restaurant.currency ?? null }, true);
      router.push(`/r/${menu.restaurant.slug}/order/${data.id}?k=${data.public_token}`);
    } catch {
      setError(t("No connection. Check your Wi-Fi and tap Send again. You won't be charged twice."));
    } finally {
      setSending(false);
    }
  }

  /* ================================================================== */
  /* Cart view                                                          */
  /* ================================================================== */
  if (view === "cart") {
    const suggestions = [...new Set(cart.flatMap((l) => byId.get(l.itemId)?.pairs_with ?? []))]
      .map((id) => byId.get(id))
      .filter((i): i is MenuItem => !!i && i.available && !inCart.has(i.id) && !!defaultPicked(i))
      .slice(0, 3);

    return (
      <main className="g" data-brand={brand}>
        <header className="g-sub">
          <button className="g-back" onClick={() => setView("menu")} aria-label={t("Back to the menu")}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5 8 12l7 7" /></svg>
          </button>
          <h1>{t("Your order")}</h1>
          <span className="g-table">{t("Table {n}", { n: menu.table.label })}</span>
        </header>

        <div className="g-pad">
          {cart.length === 0 && (
            <div className="g-empty">
              <Doodle name="bowl" className="g-empty-doodle" />
              <p>{t("Nothing here yet.")}</p>
              <button className="g-btn ghost" onClick={() => setView("menu")}>{t("Browse the menu")}</button>
            </div>
          )}

          <ul className="g-lines">
            {cart.map((l) => {
              const item = byId.get(l.itemId);
              return (
                <li key={l.key} className="g-line">
                  <span className="g-tile sm" data-tint={item ? tintOf(item) : 1}>
                    <Doodle name={item ? iconOf(item) : "bowl"} />
                  </span>
                  <div className="g-line-body">
                    <div className="g-line-top">
                      <span className="g-line-name">{l.name}</span>
                      <span className="g-price">{money(l.unitCents * l.qty)}</span>
                    </div>
                    {(l.optionNames.length > 0 || l.note) && (
                      <p className="g-line-mods">
                        {l.optionNames.join(" · ")}
                        {l.note && <span className="g-line-note"> “{l.note}”</span>}
                      </p>
                    )}
                    <div className="g-line-actions">
                      <Stepper L={L} value={l.qty} onChange={(d) => changeQty(l.key, d)} label={l.name} small />
                      {item && item.groups.length > 0 && (
                        <button className="g-link" onClick={() => editLine(l.key)}>{t("Edit")}</button>
                      )}
                    </div>
                  </div>
                </li>
              );
            })}
          </ul>

          {suggestions.length > 0 && (
            <section className="g-also" aria-label={t("Suggestions")}>
              <h2 className="g-hand">{t("anything else?")}</h2>
              <div className="g-also-row">
                {suggestions.map((s) => (
                  <button key={s.id} className="g-also-card" onClick={() => quickAdd(s)}>
                    <span className="g-tile sm" data-tint={tintOf(s)}><Doodle name={iconOf(s)} /></span>
                    <span className="g-also-name">{s.name}</span>
                    <span className="g-also-price">+ {money(s.price_cents)}</span>
                  </button>
                ))}
              </div>
            </section>
          )}

          {cart.length > 0 && (
            <div className="g-totals">
              {showTax && <div><span>{t("Subtotal")}</span><span>{money(subtotal)}</span></div>}
              {showTax && <div><span>{t("Sales tax")}</span><span>{money(tax)}</span></div>}
              <div className="g-grand"><span>{t("Total")}</span><span>{money(subtotal + tax)}</span></div>
              <p className="g-fine">{t("You'll pay at the counter when you're done. No rush.")}</p>
            </div>
          )}
        </div>

        {cart.length > 0 && (
          <footer className="g-dock">
            {error && <div className="g-error" role="alert">{error}</div>}
            <button className="g-btn block big" onClick={placeOrder} disabled={sending}>
              {sending ? t("Sending to the kitchen…") : <>{t("Send to the kitchen")} <span className="g-btn-sum">{money(subtotal + tax)}</span></>}
            </button>
          </footer>
        )}

        {sheet && (
          <ItemSheet
            L={L}
            key={sheet.item.id + (sheet.editKey ?? "")}
            item={sheet.item}
            tint={tintOf(sheet.item)}
            icon={iconOf(sheet.item)}
            editing={cart.find((l) => l.key === sheet.editKey) ?? null}
            pair={null}
            onClose={() => setSheet(null)}
            onSave={saveFromSheet}
          />
        )}
        {toast && <ToastBar L={L} toast={toast} onEdit={editLine} />}
      </main>
    );
  }

  /* ================================================================== */
  /* Menu view                                                          */
  /* ================================================================== */
  return (
    <main className="g" data-brand={brand}>
      <header className="g-hero">
        <div className="g-hero-top">
          <span className="g-brand">{menu.restaurant.name}</span>
          <span className="g-table">{t("Table {n}", { n: menu.table.label })}</span>
        </div>
        <h1 className="g-hello">
          <span className="g-hello-1">{greeting ? `${t(greeting)}.` : t("Welcome in.")}</span>
          <span className="g-hello-2">{t("What sounds good?")}</span>
        </h1>
        {menu.restaurant.tagline && <p className="g-tagline">{menu.restaurant.tagline}</p>}
        <p className="g-hand g-hint">{t("order here, we'll bring it to you ↓")}</p>
      </header>

      {lastOrder && (
        <a className="g-track" href={`/r/${menu.restaurant.slug}/order/${lastOrder.id}?k=${lastOrder.k}`} onClick={(e) => {
          e.preventDefault();
          writeStore("tabletop:return", menuPath, true);
          writeStore("tabletop:brand", brand, true);
          router.push(`/r/${menu.restaurant.slug}/order/${lastOrder.id}?k=${lastOrder.k}`);
        }}>
          <span className="g-track-dot" aria-hidden="true" />
          <span>{t("Order #{n} is with the kitchen", { n: lastOrder.number })}</span>
          <span className="g-track-go">{t("Track →")}</span>
        </a>
      )}

      {moodsHere.length > 0 && (
        <section className="g-moods" aria-label={t("What are you in the mood for?")}>
          <h2 className="g-label">{t("In the mood for")}</h2>
          <div className="g-mood-row">
            {moodsHere.map((m) => (
              <button
                key={m.key}
                className="g-mood"
                aria-pressed={mood === m.key}
                onClick={() => pickMood(m.key)}
              >
                <Doodle name={m.icon} className="g-mood-doodle" />
                <span>{t(m.label)}</span>
              </button>
            ))}
          </div>
          <div className="g-diets" role="group" aria-label={t("Dietary needs")}>
            {dietsHere.map((d) => (
              <button key={d} className="g-diet" aria-pressed={diets.has(d)} onClick={() => toggleDiet(d)}>
                {diets.has(d) && <span aria-hidden="true">✓ </span>}
                {t(DIETARY_LABEL[d])}
              </button>
            ))}
          </div>
        </section>
      )}

      {!filtering && featured && (
        <section className="g-feature" data-tint={tintOf(featured)} aria-label={t("House favorite")}>
          <span className="g-stamp big">{featured.badge}</span>
          <Doodle name={iconOf(featured)} className="g-feature-doodle" />
          <h2 className="g-feature-name">{featured.name}</h2>
          {featured.story && <p className="g-hand g-feature-story">{featured.story}</p>}
          <div className="g-feature-foot">
            <span className="g-price lg">{money(featured.price_cents)}</span>
            <button className="g-link" onClick={() => setSheet({ item: featured })}>{t("See details")}</button>
            <button className="g-btn" onClick={() => quickAdd(featured)}>{t("Add to order")}</button>
          </div>
        </section>
      )}

      <span id="g-results" className="g-anchor" aria-hidden="true" />
      {filtering && (
        <div className="g-filtering" role="status">
          <span>
            {t(shownCount === 1 ? "{n} dish" : "{n} dishes", { n: shownCount })}
            {mood && <> {t("for")} <b>{t(MOODS.find((m) => m.key === mood)?.label ?? "").toLowerCase()}</b></>}
            {diets.size > 0 && <>, {[...diets].map((d) => t(DIETARY_LABEL[d]).toLowerCase()).join(" + ")}</>}
          </span>
          <button className="g-link" onClick={() => { setMood(null); setDiets(new Set()); }}>{t("Clear")}</button>
        </div>
      )}

      {sections.length > 0 && (
        <nav className="g-tabs" aria-label={t("Menu sections")} ref={navRef}>
          {sections.map((c) => (
            <button key={c.id} data-cat={c.id} aria-current={activeCat === c.id} onClick={() => jumpTo(c.id)}>
              <span className="g-tab-dot" data-tint={(menu.categories.findIndex((x) => x.id === c.id) % TINTS) + 1} />
              {c.name}
            </button>
          ))}
        </nav>
      )}

      <div className="g-pad">
        {shownCount === 0 && (
          <div className="g-empty">
            <Doodle name="leaf" className="g-empty-doodle" />
            <p>{t("Nothing fits that combination.")}</p>
            <button className="g-btn ghost" onClick={() => { setMood(null); setDiets(new Set()); }}>{t("Show everything")}</button>
          </div>
        )}

        {sections.map((c) => (
          <section key={c.id} id={`cat-${c.id}`} className="g-sec">
            <header className="g-sec-head">
              <h2>{c.name}</h2>
              {c.note && <span className="g-hand g-sec-note">{c.note}</span>}
            </header>
            {c.items.length === 0 && <p className="g-muted">{t("Nothing here right now.")}</p>}
            <ul className="g-dishes">
              {c.items.map((item) => {
                const n = inCart.get(item.id) ?? 0;
                return (
                  <li key={item.id} className={`g-dish${item.available ? "" : " out"}`}>
                    <button
                      className="g-dish-main"
                      onClick={() => item.available && setSheet({ item })}
                      aria-disabled={!item.available}
                    >
                      <span className="g-tile" data-tint={tintOf(item)}>
                        {item.photo_url ? <img src={item.photo_url} alt="" loading="lazy" /> : <Doodle name={iconOf(item)} />}
                      </span>
                      <span className="g-dish-body">
                        <span className="g-dish-name">
                          {item.name}
                          {item.badge && <span className="g-stamp">{item.badge}</span>}
                        </span>
                        {item.description && <span className="g-dish-desc">{item.description}</span>}
                        <span className="g-dish-meta">
                          {item.dietary_tags.map((tag) => (
                            <span key={tag} className="g-tag">{t(DIETARY_LABEL[tag] ?? tag)}</span>
                          ))}
                          {item.allergens.includes("tree_nuts") && <span className="g-tag warn">{t("Contains nuts")}</span>}
                        </span>
                      </span>
                    </button>
                    <div className="g-dish-side">
                      <span className="g-price">{money(item.price_cents)}</span>
                      {item.available ? (
                        <button
                          className={`g-add${n ? " has" : ""}`}
                          onClick={() => quickAdd(item)}
                          aria-label={n ? t("Add another {name} ({n} in your order)", { name: item.name, n }) : t("Add {name}", { name: item.name })}
                        >
                          {n ? <span>{n}</span> : <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>}
                        </button>
                      ) : (
                        <span className="g-hand g-soldout">{t("sold out")}</span>
                      )}
                    </div>
                  </li>
                );
              })}
            </ul>
          </section>
        ))}

        <p className="g-sign g-hand">{t("thanks for stopping by ♥")}</p>
      </div>

      {count > 0 && (
        <button key={bump} className={`g-cartbar${bump ? " bump" : ""}`} onClick={() => { setView("cart"); window.scrollTo(0, 0); }}>
          <span className="g-cartbar-n">{count}</span>
          <span className="g-cartbar-label">{t("Review order")}</span>
          <span className="g-cartbar-sum">{money(subtotal)}</span>
        </button>
      )}

      {sheet && (
        <ItemSheet
          L={L}
          key={sheet.item.id + (sheet.editKey ?? "")}
          item={sheet.item}
          tint={tintOf(sheet.item)}
          icon={iconOf(sheet.item)}
          editing={cart.find((l) => l.key === sheet.editKey) ?? null}
          pair={sheet.editKey ? null : (sheet.item.pairs_with.map((id) => byId.get(id)).find((p) => p && p.available && defaultPicked(p)) ?? null)}
          pairTint={(p) => tintOf(p)}
          pairIcon={(p) => iconOf(p)}
          onClose={() => setSheet(null)}
          onSave={saveFromSheet}
        />
      )}
      {toast && <ToastBar L={L} toast={toast} onEdit={editLine} />}
    </main>
  );
}

/* ==================================================================== */
/* Pieces                                                               */
/* ==================================================================== */

function Stepper({ L, value, onChange, label, small }: { L: Fmt; value: number; onChange: (d: number) => void; label: string; small?: boolean }) {
  const { t } = L;
  return (
    <div className={`g-step${small ? " sm" : ""}`}>
      <button onClick={() => onChange(-1)} aria-label={value === 1 && small ? t("Remove {name}", { name: label }) : t("One less {name}", { name: label })}>
        {value === 1 && small ? (
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12" /></svg>
        ) : (
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14" /></svg>
        )}
      </button>
      <span aria-live="polite">{value}</span>
      <button onClick={() => onChange(1)} aria-label={t("One more {name}", { name: label })} disabled={value >= 20}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
      </button>
    </div>
  );
}

function ToastBar({ L, toast, onEdit }: { L: Fmt; toast: Toast; onEdit: (key: string) => void }) {
  return (
    <div className="g-toast" role="status" key={toast.id}>
      <svg viewBox="0 0 24 24" aria-hidden="true" className="g-toast-check"><path d="m5 12.5 4.2 4L19 7" /></svg>
      <span className="g-toast-text">
        <b>{toast.title}</b>
        {toast.detail && <span>{toast.detail}</span>}
      </span>
      {toast.lineKey && <button onClick={() => onEdit(toast.lineKey!)}>{L.t("Customize")}</button>}
    </div>
  );
}

function ItemSheet({
  L,
  item,
  tint,
  icon,
  editing,
  pair,
  pairTint,
  pairIcon,
  onClose,
  onSave,
}: {
  L: Fmt;
  item: MenuItem;
  tint: number;
  icon: string | null;
  editing: CartLine | null;
  pair: MenuItem | null;
  pairTint?: (i: MenuItem) => number;
  pairIcon?: (i: MenuItem) => string | null;
  onClose: () => void;
  onSave: (line: Omit<CartLine, "key">, pair: Omit<CartLine, "key"> | null, editKey?: string) => void;
}) {
  const { t, money } = L;
  const [picked, setPicked] = useState<Picked>(() => (editing ? pickedFromLine(item, editing) : defaultPicked(item) ?? {}));
  const [qty, setQty] = useState(editing?.qty ?? 1);
  const [note, setNote] = useState(editing?.note ?? "");
  const [noteOpen, setNoteOpen] = useState(!!editing?.note);
  const [withPair, setWithPair] = useState(false);
  const closeRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    document.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus({ preventScroll: true });
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  function choose(groupId: string, optionId: string, min: number, max: number) {
    setPicked((prev) => {
      const cur = prev[groupId] ?? [];
      if (max === 1) {
        if (cur[0] === optionId) return min === 0 ? { ...prev, [groupId]: [] } : prev;
        return { ...prev, [groupId]: [optionId] };
      }
      if (cur.includes(optionId)) return { ...prev, [groupId]: cur.filter((x) => x !== optionId) };
      if (cur.length >= max) return prev;
      return { ...prev, [groupId]: [...cur, optionId] };
    });
  }

  const line = lineFrom(item, picked, qty, note);
  const pairPicked = pair ? defaultPicked(pair) : null;
  const pairLine = pair && pairPicked && withPair ? lineFrom(pair, pairPicked, 1, "") : null;
  const missing = item.groups.find((g) => (picked[g.id] ?? []).length < g.min_select);
  const total = line.unitCents * qty + (pairLine?.unitCents ?? 0);

  return (
    <div className="g-sheet-bg" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="g-sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-title">
        <div className="g-sheet-band" data-tint={tint}>
          {item.photo_url ? <img src={item.photo_url} alt="" /> : <Doodle name={icon} className="g-sheet-doodle" />}
          {item.badge && <span className="g-stamp big">{item.badge}</span>}
          <button ref={closeRef} className="g-close" onClick={onClose} aria-label={t("Close")}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18" /></svg>
          </button>
        </div>

        <div className="g-sheet-body">
          <div className="g-sheet-title">
            <h3 id="sheet-title">{item.name}</h3>
            <span className="g-price lg">{money(item.price_cents)}</span>
          </div>
          {item.description && <p className="g-sheet-desc">{item.description}</p>}
          {item.story && (
            <p className="g-quote">
              <span className="g-hand">{item.story}</span>
              <span className="g-quote-by">{t("from the counter")}</span>
            </p>
          )}
          {item.allergens.length > 0 && (
            <p className="g-allergens">
              <b>{t("Contains")}</b> {item.allergens.map((a) => t(ALLERGEN_LABEL[a] ?? a)).join(", ")}. {t("Tell your server about any allergy.")}
            </p>
          )}

          {item.groups.map((g) => {
            const sel = picked[g.id] ?? [];
            const rule =
              g.min_select > 0
                ? g.max_select === 1 ? t("Pick one") : t("Pick {a}–{b}", { a: g.min_select, b: g.max_select })
                : g.max_select === 1 ? t("Optional") : t("Up to {n}", { n: g.max_select });
            return (
              <fieldset className="g-group" key={g.id}>
                <legend>
                  <span>{g.name}</span>
                  <span className={`g-rule${g.min_select > sel.length ? " need" : ""}`}>{rule}</span>
                </legend>
                <div className="g-pills">
                  {g.options.map((o) => {
                    const on = sel.includes(o.id);
                    const full = !on && g.max_select > 1 && sel.length >= g.max_select;
                    return (
                      <button
                        key={o.id}
                        type="button"
                        className="g-pill"
                        role={g.max_select === 1 ? "radio" : "checkbox"}
                        aria-checked={on}
                        disabled={!o.available || full}
                        onClick={() => choose(g.id, o.id, g.min_select, g.max_select)}
                      >
                        {on && <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12.5 4.2 4L19 7" /></svg>}
                        <span>{o.name}</span>
                        {!o.available ? <em>{t("sold out")}</em> : o.price_cents > 0 && <em>+{money(o.price_cents)}</em>}
                      </button>
                    );
                  })}
                </div>
              </fieldset>
            );
          })}

          <div className="g-note">
            {noteOpen ? (
              <>
                <label htmlFor="g-note-input">{t("Note for the kitchen")}</label>
                <textarea
                  id="g-note-input"
                  rows={2}
                  maxLength={200}
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder={t("No onions, extra hot, allergy…")}
                  autoFocus={!editing}
                />
              </>
            ) : (
              <button className="g-link" onClick={() => setNoteOpen(true)}>{t("+ Add a note for the kitchen")}</button>
            )}
          </div>

          {pair && pairPicked && (
            <div className="g-pair">
              <span className="g-tile sm" data-tint={pairTint?.(pair) ?? 1}><Doodle name={pairIcon?.(pair) ?? "bowl"} /></span>
              <span className="g-pair-text">
                <span className="g-hand">{t("goes great with")}</span>
                <b>{pair.name}</b>
              </span>
              <button className="g-pill" role="checkbox" aria-checked={withPair} onClick={() => setWithPair((v) => !v)}>
                {withPair && <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12.5 4.2 4L19 7" /></svg>}
                <span>{withPair ? t("Added") : t("Add")}</span>
                <em>+{money(lineFrom(pair, pairPicked, 1, "").unitCents)}</em>
              </button>
            </div>
          )}
        </div>

        <div className="g-sheet-foot">
          <Stepper L={L} value={qty} onChange={(d) => setQty((q) => Math.max(1, Math.min(20, q + d)))} label={item.name} />
          <button className="g-btn block" disabled={!!missing} onClick={() => onSave(line, pairLine, editing?.key)}>
            {missing ? t("Pick a {group}", { group: missing.name.toLowerCase() }) : editing ? t("Update · {price}", { price: money(total) }) : t("Add to order · {price}", { price: money(total) })}
          </button>
        </div>
      </div>
    </div>
  );
}
