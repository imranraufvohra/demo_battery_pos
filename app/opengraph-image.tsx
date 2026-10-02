import { ImageResponse } from "next/og";
import { BRAND } from "@/lib/brand";

export const alt = "Car battery shop POS and inventory software: free live demo";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          gap: 56,
          padding: 80,
          background: "linear-gradient(160deg, #1c2b33 0%, #223640 100%)",
          color: "white",
        }}
      >
        <svg width="220" height="220" viewBox="0 0 64 64" fill="none">
          <rect x="24" y="9" width="16" height="7" rx="2" fill="#f5b400" />
          <rect x="14" y="16" width="36" height="42" rx="6" stroke="#f5b400" strokeWidth="4" />
          <path d="M35 24 23 40h8l-2 11 12-17h-8z" fill="#f5b400" />
        </svg>
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ fontSize: 30, color: "#f5b400", letterSpacing: 2 }}>FREE LIVE DEMO</div>
          <div style={{ fontSize: 68, fontWeight: 700, lineHeight: 1.05, marginTop: 14 }}>Car Battery Shop POS & Inventory</div>
          <div style={{ fontSize: 30, color: "rgba(255,255,255,0.7)", marginTop: 22 }}>
            Billing, stock, warranty claims, scrap and reports
          </div>
          <div style={{ fontSize: 26, color: "rgba(255,255,255,0.5)", marginTop: 34 }}>{BRAND.poweredBy}</div>
        </div>
      </div>
    ),
    size
  );
}
