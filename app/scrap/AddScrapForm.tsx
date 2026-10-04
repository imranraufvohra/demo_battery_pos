"use client";

import { useMemo, useState } from "react";
import Icon from "@/components/Icons";
import Sheet from "@/components/Sheet";
import { BATTERY_TYPES } from "@/lib/inventory";
import { parseAmount, parseQty, todayKarachi } from "@/lib/invoices";
import { getBrowserClient } from "@/lib/supabase/lazy";

import { T } from "@/components/T";
import { useT } from "@/lib/i18n/client";
export default function AddScrapForm({
  onClose,
  onAdded,
}: {
  onClose: () => void;
  onAdded: (message: string) => void;
}) {
  const tt = useT();
  const [customerName, setCustomerName] = useState("");
  const [brand, setBrand] = useState("");
  const [model, setModel] = useState("");
  const [batteryType, setBatteryType] = useState("");
  const [batteryNumber, setBatteryNumber] = useState("");
  const [qtyText, setQtyText] = useState("1");
  const [weightText, setWeightText] = useState("");
  const [receivedDate, setReceivedDate] = useState(() => todayKarachi());
  const [note, setNote] = useState("");
  const today = useMemo(() => todayKarachi(), []);

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const qty = parseQty(qtyText);
  const weight = weightText.trim() ? parseAmount(weightText) : null;

  function problem(): string | null {
    if (!brand.trim() || !model.trim()) return "Enter the brand and model of the old battery.";
    if (qtyText.trim() === "" || qty == null) return "Enter a quantity of 1 or more.";
    if (weightText.trim() !== "" && (weight == null || weight <= 0)) {
      return "Enter a valid weight in kg, or leave it blank.";
    }
    if (!receivedDate) return "Choose the date it was received.";
    if (receivedDate > today) return "The received date cannot be in the future.";
    return null;
  }

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const found = problem();
    if (found) {
      setError(found);
      return;
    }
    setSaving(true);
    setError(null);
    const supabase = await getBrowserClient();
    const { data, error: dbError } = await supabase.rpc("record_scrap_intake", {
      p_invoice_id: null,
      p_customer_id: null,
      p_customer_name: customerName.trim() || null,
      p_brand: brand.trim(),
      p_model: model.trim(),
      p_battery_type: batteryType.trim() || null,
      p_battery_number: batteryNumber.trim() || null,
      p_quantity: qty,
      p_estimated_weight_kg: weight,
      p_note: note.trim() || null,
      p_received_date: receivedDate,
    });
    if (dbError || !data) {
      setError(
        dbError?.code === "42883" || dbError?.code === "PGRST202"
          ? "The scrap battery setup is missing. Run 07_scrap_battery.sql in Supabase, then try again."
          : dbError?.message ?? "The battery was not added. Please try again."
      );
      setSaving(false);
      return;
    }
    onAdded(`${brand.trim()} ${model.trim()} added to the scrap pile.`);
  }

  return (
    <Sheet onClose={onClose} labelledBy="add-scrap-title" dismissable={!saving}>
      <form onSubmit={onSubmit} noValidate className="flex min-h-0 flex-1 flex-col">
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <h2 id="add-scrap-title" className="font-display text-2xl font-bold">
            <T>Add scrap battery</T>
          </h2>
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            aria-label={tt("Close")}
            className="inline-flex h-10 w-10 items-center justify-center rounded-full text-lead transition-colors hover:bg-plate disabled:opacity-60"
          >
            <Icon name="x" className="h-5 w-5" />
          </button>
        </div>

        <div className="flex-1 space-y-6 overflow-y-auto px-5 py-6">
          <p className="text-sm text-lead">
            <T>{"For an old battery that didn't come through a bill — e.g. one brought in on its own, or one missed on the New bill screen. This goes straight to the scrap pile, not sellable stock."}</T>
          </p>

          <fieldset className="space-y-3">
            <legend className="mb-1 font-display text-xl font-semibold"><T>Battery</T></legend>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label htmlFor="as-brand" className="mb-1.5 block text-sm font-medium">
                  <T>Brand</T>
                </label>
                <input
                  id="as-brand"
                  autoFocus
                  value={brand}
                  onChange={(e) => setBrand(e.target.value)}
                  aria-invalid={!brand.trim()}
                  className="input"
                />
              </div>
              <div>
                <label htmlFor="as-model" className="mb-1.5 block text-sm font-medium">
                  <T>Model</T>
                </label>
                <input
                  id="as-model"
                  value={model}
                  onChange={(e) => setModel(e.target.value)}
                  aria-invalid={!model.trim()}
                  className="input"
                />
              </div>
              <div>
                <label htmlFor="as-type" className="mb-1.5 block text-sm font-medium">
                  <T>Type (optional)</T>
                </label>
                <input
                  id="as-type"
                  list="as-battery-types"
                  value={batteryType}
                  onChange={(e) => setBatteryType(e.target.value)}
                  placeholder={tt("Unknown")}
                  className="input"
                />
                <datalist id="as-battery-types">
                  {BATTERY_TYPES.map((t) => (
                    <option key={t} value={t} />
                  ))}
                </datalist>
              </div>
              <div>
                <label htmlFor="as-qty" className="mb-1.5 block text-sm font-medium">
                  <T>Qty</T>
                </label>
                <input
                  id="as-qty"
                  value={qtyText}
                  onChange={(e) => setQtyText(e.target.value.replace(/\D/g, ""))}
                  inputMode="numeric"
                  aria-invalid={qty == null}
                  className="input tabular-nums"
                />
              </div>
            </div>
            <div>
              <label htmlFor="as-number" className="mb-1.5 block text-sm font-medium">
                <T>Serial / plate number (optional)</T>
              </label>
              <input
                id="as-number"
                value={batteryNumber}
                onChange={(e) => setBatteryNumber(e.target.value)}
                className="input"
              />
            </div>
            <div>
              <label htmlFor="as-weight" className="mb-1.5 block text-sm font-medium">
                <T>Weight in kg (optional)</T>
              </label>
              <input
                id="as-weight"
                inputMode="decimal"
                value={weightText}
                onChange={(e) => setWeightText(e.target.value)}
                placeholder={tt("Usually weighed together at sale time")}
                className="input tabular-nums"
              />
            </div>
          </fieldset>

          <fieldset className="space-y-3">
            <legend className="mb-1 font-display text-xl font-semibold"><T>Where it came from</T></legend>
            <div>
              <label htmlFor="as-customer" className="mb-1.5 block text-sm font-medium">
                <T>Customer name (optional)</T>
              </label>
              <input
                id="as-customer"
                value={customerName}
                onChange={(e) => setCustomerName(e.target.value)}
                placeholder={tt("Leave blank if unknown")}
                className="input"
              />
            </div>
            <div>
              <label htmlFor="as-date" className="mb-1.5 block text-sm font-medium">
                <T>Received date</T>
              </label>
              <input
                id="as-date"
                type="date"
                value={receivedDate}
                max={today}
                onChange={(e) => setReceivedDate(e.target.value)}
                className="input"
              />
            </div>
            <div>
              <label htmlFor="as-note" className="mb-1.5 block text-sm font-medium">
                <T>Note (optional)</T>
              </label>
              <textarea
                id="as-note"
                rows={2}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                className="input resize-none"
              />
            </div>
          </fieldset>
        </div>

        <div className="pb-safe border-t border-line bg-white px-5 py-4">
          {error && (
            <p role="alert" className="mb-3 rounded-xl bg-terminal/10 px-3 py-2 text-sm text-terminal-deep">
              <T>{error}</T>
            </p>
          )}
          <div className="flex justify-end gap-3">
            <button type="button" onClick={onClose} disabled={saving} className="btn btn-quiet">
              <T>Cancel</T>
            </button>
            <button type="submit" disabled={saving} className="btn btn-primary min-w-36">
              <T>{saving ? "Saving" : "Add to scrap"}</T>
            </button>
          </div>
        </div>
      </form>
    </Sheet>
  );
}
