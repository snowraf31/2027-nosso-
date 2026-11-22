import Link from "next/link";

export default function Home() {
  return (
    <main className="center">
      <div className="card">
        <h1>Tabletop</h1>
        <p className="muted" style={{ margin: 0 }}>
          Guests order from the QR code or NFC tag on their table. Orders go straight to the kitchen screen.
        </p>
        <Link className="btn block" href="/r/harbor-pine/t/demo-table-7">
          Open demo menu (Table 7)
        </Link>
        <Link className="btn ghost block" href="/kitchen">
          Kitchen screen
        </Link>
      </div>
    </main>
  );
}
