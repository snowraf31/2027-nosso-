import type { MenuItem } from "@/lib/types";

/* ------------------------------------------------------------------ */
/* Hand-drawn doodles. Stroke uses currentColor so they follow the theme */
/* ------------------------------------------------------------------ */

const PATHS: Record<string, React.ReactNode> = {
  cup: (
    <>
      <path d="M11 20.5c6.5-.6 14-.4 21 .2l-.6 7.6c-.5 6-4.9 9.9-10.1 9.8-5.1-.1-9.3-4.2-9.6-9.9z" />
      <path d="M32.2 23.4c2.4-.4 4.6.6 4.7 3s-2 4-5 4.2" />
      <path d="M17.6 7.5c-2.2 2.6 1.9 4.4-.2 7.6M23.8 6c-2.2 2.9 2 4.6-.1 8.2M30 8c-1.9 2.4 1.7 4-.2 6.8" />
      <path d="M7.5 41.6c9.6-.9 20.6-.9 31.4.2" />
    </>
  ),
  egg: (
    <>
      <path d="M9.6 27.4c-3.4-7.4 3.5-14.6 11.4-13.2 4.6-6.2 15.2-4 16.2 3.6 6.2 3.2 4.8 13.8-3.9 15.4-5.4 5.8-17.4 4.6-19.4-1.6-3.6.6-5.6-1.6-4.3-4.2z" />
      <circle cx="26.5" cy="24.5" r="5.2" />
      <path d="M24.3 22.8c.6-.9 1.6-1.4 2.6-1.4" />
    </>
  ),
  sandwich: (
    <>
      <path d="M6.5 21.2 23.6 11c.4-.2.9-.2 1.3 0l17 9.6-17.6 9.9c-.4.2-.9.2-1.3 0z" />
      <path d="M6.4 21.4v5.2c0 .5.3 1 .8 1.3l16.2 9.2c.4.2.9.2 1.3 0l16.6-9.4c.5-.3.7-.8.7-1.3v-5" />
      <path d="M9 25.6c2.4 1.8 4.6-.9 7.2.8s4.6-.6 7.3 1.1 4.8-.8 7.4.7 4.6-1.2 7.4.3" />
    </>
  ),
  pastry: (
    <>
      <path d="M6 31.2C9.4 19.6 17.8 12.4 24 12.4s14.8 7.4 18 18.8c-3.4 2.4-8 1.6-10.2-1.8-1.6 4.4-5 6.6-7.8 6.6s-6.4-2.4-7.8-6.6c-2.4 3.4-7 4.2-10.2 1.8z" />
      <path d="M18.4 15.6l2.6 14.6M29.8 15.4l-2.8 14.8M24 12.6v17.2" />
    </>
  ),
  leaf: (
    <>
      <path d="M10.4 38.2C8.8 21.4 20.6 9.8 39.2 9.6c.8 18.4-10.4 30.4-28.8 28.6z" />
      <path d="M11.6 37 31 17.4M19.4 29.2l-.4-6.8M25.4 23.2l7 .2" />
    </>
  ),
  bowl: (
    <>
      <path d="M7.6 23.4c10.8-.8 22-.8 33 .2-.6 8.8-7.6 15-16.6 15S8 32.2 7.6 23.4z" />
      <path d="M18 41.4c4-.4 8.2-.4 12.2.1" />
      <circle cx="17" cy="18.6" r="3" />
      <circle cx="25.4" cy="16.4" r="3.2" />
      <circle cx="32" cy="19.6" r="2.6" />
    </>
  ),
  fork: (
    <>
      <path d="M15.6 7.4v11.4c0 2.6 1.8 4.4 4 4.4s4-1.8 4-4.4V7.4M19.6 7.6v33" />
      <path d="M33 7.2c-4.6 3.6-5.2 13.6-.6 16.6v16.8" />
    </>
  ),
  glass: (
    <>
      <path d="M13.4 9.4c7.4-.6 14.4-.6 21.4.2l-2.6 27.6c-.2 1.6-1.6 2.8-3.2 2.8h-9.6c-1.6 0-3-1.2-3.2-2.8z" />
      <path d="M14.4 19.6c6.6.8 12.6.8 19.4-.2M28 9.6l4.6-6" />
    </>
  ),
  cake: (
    <>
      <path d="M7.6 30.2 24 21.6l16.4 8.2v8.6c0 .8-.5 1.5-1.3 1.8L25.2 44a3 3 0 0 1-2.4 0L8.9 40.2c-.8-.3-1.3-1-1.3-1.8z" />
      <path d="M7.8 30.4 23.2 38c.5.3 1.1.3 1.6 0l15.4-8.2" />
      <path d="M8 34.6c5.2 2.8 10.4 5.4 15.6 7.8M24.4 42.4c5.2-2.4 10.4-5 15.6-7.8" />
      <path d="M24 21.4c.2-3.4 1.4-6 4.6-7.4M28.2 14.2c2.6-2.2 6.4-1.6 7.2 1.6-2.6 1.6-5.2 1.4-7.2-1.6z" />
    </>
  ),
  burger: (
    <>
      <path d="M8.4 21.6c-.2-7.4 7-12.4 15.6-12.4s15.8 5 15.6 12.4c-10.4.6-20.8.6-31.2 0z" />
      <path d="M18 15.2l1.2.8M25.4 13.4l1.2.6M30.6 16.6l1 .9M14.4 18.4l.9.7" />
      <path d="M7.4 26c2.4-1.9 4.6 1.7 7 0s4.6 1.7 7 0 4.6 1.7 7 0 4.6 1.7 7 0 4.4 1.6 6.2-.2" />
      <path d="M8.6 30.4c10.2-.5 20.6-.5 30.8.1 1.4.1 1.4 3.9 0 4-10.2.5-20.6.5-30.8-.1-1.4-.1-1.4-3.9 0-4z" />
      <path d="M9.2 38.4c9.8-.4 19.8-.4 29.6.1-.2 2.4-2 3.8-4.2 3.8H13.4c-2.2 0-4-1.4-4.2-3.9z" />
    </>
  ),
  fries: (
    <>
      <path d="M11.6 22.4c8.2-.6 16.4-.6 24.8 0l-3 19.4c-6.2.4-12.4.4-18.6 0z" />
      <path d="M15.4 22 13 8.6M20.2 22.2l-1-14.8M25 22.2l1-15.6M29.8 22.2l2.2-12.8M34 22.4l3-9.8" />
      <path d="M17.6 29.4c3.4 2.6 10.2 2.6 13.4-.2" />
    </>
  ),
  shake: (
    <>
      <path d="M14.4 19.2c6.4-.4 12.8-.4 19.2 0l-2.8 22.4c-4.6.4-9 .4-13.6 0z" />
      <path d="M12.8 19.4c-.4-5.4 5-8.8 11.2-8.8s11.6 3.4 11.2 8.8" />
      <path d="M26.6 10.8 30.8 3.4M23.2 9.6c-.6-2.4 1-3.8 2.6-3.4" />
      <path d="M16.6 27.4c4.8.6 10 .6 14.8 0" />
    </>
  ),
  flame: (
    <>
      <path d="M24 42c-7.4 0-12-5-12-11.6 0-6 4.6-9.4 6-15 2.6 3 3 5.6 3 8 1.6-4 4.6-8.6 4-16 6 4.2 11 11.6 11 21.6C36 36.2 31.4 42 24 42z" />
      <path d="M24 42c-3 0-5-2-5-5 0-3 2.6-4.6 3-7 2 2 3 3.6 3 5.6 1-1 2-2.6 2-4 2 2 2 4 2 5.6 0 2.8-2 4.8-5 4.8z" />
    </>
  ),

};

export function Doodle({ name, className }: { name?: string | null; className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 48 48"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.9}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {PATHS[name ?? ""] ?? PATHS.bowl}
    </svg>
  );
}

/* ------------------------------------------------------------------ */
/* Moods: the "what are you in the mood for" row                        */
/* ------------------------------------------------------------------ */

export const MOODS = [
  { key: "coffee", label: "Coffee fix", icon: "cup" },
  { key: "light", label: "Something light", icon: "leaf" },
  { key: "hearty", label: "Big appetite", icon: "fork" },
  { key: "spicy", label: "Bring the heat", icon: "flame" },
  { key: "sweet", label: "A little sweet", icon: "pastry" },
] as const;

export function greetingFor(date = new Date()) {
  const h = date.getHours();
  if (h < 5) return "Up late";
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

/* ------------------------------------------------------------------ */
/* Choices and cart lines                                              */
/* ------------------------------------------------------------------ */

export type Picked = Record<string, string[]>;

export type CartLine = {
  key: string;
  itemId: string;
  name: string;
  qty: number;
  optionIds: string[];
  optionNames: string[];
  unitCents: number;
  note: string;
};

/** The default choice for every group (first available options up to the minimum). Null if impossible. */
export function defaultPicked(item: MenuItem): Picked | null {
  const picked: Picked = {};
  for (const g of item.groups) {
    const avail = g.options.filter((o) => o.available);
    if (avail.length < g.min_select) return null;
    picked[g.id] = avail.slice(0, g.min_select).map((o) => o.id);
  }
  return picked;
}

export function pickedFromLine(item: MenuItem, line: CartLine): Picked {
  return Object.fromEntries(
    item.groups.map((g) => [g.id, g.options.filter((o) => line.optionIds.includes(o.id)).map((o) => o.id)])
  );
}

export function lineFrom(item: MenuItem, picked: Picked, qty: number, note: string): Omit<CartLine, "key"> {
  const chosen = item.groups.flatMap((g) => g.options.filter((o) => (picked[g.id] ?? []).includes(o.id)));
  return {
    itemId: item.id,
    name: item.name,
    qty,
    optionIds: chosen.map((o) => o.id),
    optionNames: chosen.map((o) => o.name),
    unitCents: item.price_cents + chosen.reduce((a, o) => a + o.price_cents, 0),
    note: note.trim(),
  };
}

export const sameLine = (a: Omit<CartLine, "key">, b: Omit<CartLine, "key">) =>
  a.itemId === b.itemId && a.note === b.note && a.optionIds.join() === b.optionIds.join();

/* ------------------------------------------------------------------ */
/* Storage that never throws (private mode, blocked storage)           */
/* ------------------------------------------------------------------ */

export function readStore<T>(key: string, fallback: T, session = false): T {
  try {
    const raw = (session ? sessionStorage : localStorage).getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

export function writeStore(key: string, value: unknown, session = false) {
  try {
    const s = session ? sessionStorage : localStorage;
    if (value === null) s.removeItem(key);
    else s.setItem(key, JSON.stringify(value));
  } catch {
    /* ignore */
  }
}
