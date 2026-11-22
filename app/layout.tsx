import type { Metadata, Viewport } from "next";
import { Bagel_Fat_One, Bricolage_Grotesque, Caveat, Instrument_Sans, JetBrains_Mono, Oswald, Permanent_Marker, Playfair_Display } from "next/font/google";
import "./globals.css";

// Display: a friendly grotesque we squeeze narrow for headlines
const display = Bricolage_Grotesque({ subsets: ["latin"], axes: ["opsz", "wdth"], variable: "--font-display" });
// Body: clean and very readable on small screens
const body = Instrument_Sans({ subsets: ["latin"], variable: "--font-body" });
// Handwriting: notes from the staff
const hand = Caveat({ subsets: ["latin"], weight: ["500", "600"], variable: "--font-hand" });
// "diner" brand style: chunky display and sharpie notes (loaded only when used)
const dinerDisplay = Bagel_Fat_One({ subsets: ["latin"], weight: "400", variable: "--font-diner-display", preload: false });
const dinerHand = Permanent_Marker({ subsets: ["latin"], weight: "400", variable: "--font-diner-hand", preload: false });
// "glace" brand style: condensed headlines and italic serif notes
const glaceDisplay = Oswald({ subsets: ["latin"], variable: "--font-glace-display", preload: false });
const glaceHand = Playfair_Display({ subsets: ["latin"], style: ["italic"], weight: ["500", "600"], variable: "--font-glace-hand", preload: false });
// Kitchen display numbers
const mono = JetBrains_Mono({ subsets: ["latin"], variable: "--font-mono" });

export const metadata: Metadata = {
  title: "Tabletop",
  description: "Order from your table.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f2f4ee" },
    { media: "(prefers-color-scheme: dark)", color: "#0e1512" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning className={`${display.variable} ${body.variable} ${hand.variable} ${mono.variable} ${dinerDisplay.variable} ${dinerHand.variable} ${glaceDisplay.variable} ${glaceHand.variable}`}>
      <body>{children}</body>
    </html>
  );
}
