"use client";

import { useState } from "react";
import Icon from "@/components/Icons";
import Sheet from "@/components/Sheet";
import { ACCESSORY_TYPES, BATTERY_TYPES, CATEGORIES, DEFAULT_UOM, PANEL_TYPES, typeOptionsFor } from "@/lib/inventory";
import { focusFirstError } from "@/lib/formFocus";
import type { Category } from "@/lib/types";
import type { NewPurchaseItemDraft } from "@/lib/purchases";

import { T, Opt } from "@/components/T";
import { useT } from "@/lib/i18n/client";
type Errors = Partial<Record<keyof NewPurchaseItemDraft, string>>;
const NUM = /^\d+(\.\d{1,2})?$/;

function empty(): NewPurchaseItemDraft {
  return {
    category: "battery",
    brand: "",
    model: "",
    type: "",
    voltage: "",
    plates: "",
    ah_rating: "",
    wattage: "",
    warranty_months: "",
    sale_price: "",
    reorder_level: "",
    hs_code: "",
    uom: "",
  };
}

function validate(f: NewPurchaseItemDraft): Errors {
  const e: Errors = {};
  if (!f.brand.trim()) e.brand = "Enter the brand or product name.";
  if (!f.model.trim()) e.model = "Enter the model, size or a short description.";
  if (f.sale_price && (!NUM.test(f.sale_price) || Number(f.sale_price) < 0)) e.sale_price = "Enter a valid price, or leave it empty.";
  if (f.reorder_level && (!/^\d+$/.test(f.reorder_level) || Number(f.reorder_level) < 0)) e.reorder_level = "Enter a whole number, or leave it empty.";
  return e;
}

/** Sheet for the "not in stock yet" purchase-line product. Unlike Inventory's Add-item form, this
 * does NOT create anything in the database -- it just hands a validated draft back to the purchase
 * line, which is only created (atomically, along with the rest of the bill) once the whole
 * purchase is saved via create_purchase(). */
export default function NewProductFields({
  onClose,
  onAdd,
}: {
  onClose: () => void;
  onAdd: (draft: NewPurchaseItemDraft, displayName: string) => void;
}) {
  const tt = useT();
  const [form, setForm] = useState<NewPurchaseItemDraft>(empty());
  const [errors, setErrors] = useState<Errors>({});
  const [otherType, setOtherType] = useState(false);
  const typeOptions = typeOptionsFor(form.category);

  const set = <K extends keyof NewPurchaseItemDraft>(key: K, value: NewPurchaseItemDraft[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
    setErrors((prev) => (prev[key] ? { ...prev, [key]: undefined } : prev));
  };

  function changeCategory(category: Category) {
    setForm((prev) => ({ ...empty(), category, brand: prev.brand, model: prev.model }));
    setOtherType(false);
    setErrors({});
  }

  const OTHER_TYPE = "__other__";
  function changeType(value: string) {
    if (value === OTHER_TYPE) {
      setOtherType(true);
      set("type", "");
    } else {
      setOtherType(false);
      set("type", value);
    }
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const found = validate(form);
    setErrors(found);
    if (Object.keys(found).length > 0) {
      focusFirstError();
      return;
    }
    const specs = [form.type, form.voltage && `${form.voltage}V`, form.ah_rating && `${form.ah_rating}Ah`, form.wattage && `${form.wattage}W`]
      .filter(Boolean)
      .join(" · ");
    const displayName = [form.brand.trim(), form.model.trim(), specs].filter(Boolean).join(" ");
    onAdd(form, displayName);
  }

  return (
    <Sheet onClose={onClose} labelledBy="new-product-title">
      <form onSubmit={submit} noValidate className="flex min-h-0 flex-1 flex-col">
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <h2 id="new-product-title" className="font-display text-2xl font-bold">
            <T>New product</T>
          </h2>
          <button type="button" onClick={onClose} aria-label={tt("Close")} className="inline-flex h-10 w-10 items-center justify-center rounded-full text-lead hover:bg-plate">
            <Icon name="x" className="h-5 w-5" />
          </button>
        </div>

        <div className="flex-1 space-y-5 overflow-y-auto px-5 py-6">
          <p className="text-sm text-lead">
            <T>{"Not in your inventory yet -- fill in the basics now. It's created for real once you save this purchase, with this quantity and cost."}</T>
          </p>

          <div>
            <label htmlFor="np-category" className="mb-1.5 block text-sm font-medium">
              <T>Category</T>
            </label>
            <select id="np-category" value={form.category} onChange={(e) => changeCategory(e.target.value as Category)} className="input">
              {CATEGORIES.map((c) => (
                <Opt key={c.value} value={c.value}>
                  <T>{c.label}</T>
                </Opt>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="np-brand" className="mb-1.5 block text-sm font-medium">
                <T>Brand</T>
              </label>
              <input id="np-brand" autoFocus value={form.brand} onChange={(e) => set("brand", e.target.value)} placeholder={tt("Osaka")} aria-invalid={!!errors.brand} className="input" />
              {errors.brand && <p className="mt-1 text-sm text-terminal-deep">{errors.brand}</p>}
            </div>
            <div>
              <label htmlFor="np-model" className="mb-1.5 block text-sm font-medium">
                <T>Model</T>
              </label>
              <input id="np-model" value={form.model} onChange={(e) => set("model", e.target.value)} placeholder={tt("200Ah Tubular")} aria-invalid={!!errors.model} className="input" />
              {errors.model && <p className="mt-1 text-sm text-terminal-deep">{errors.model}</p>}
            </div>
          </div>

          {form.category === "battery" ? (
            <>
              <div>
                <label htmlFor="np-type" className="mb-1.5 block text-sm font-medium">
                  <T>Battery type</T>
                </label>
                <select id="np-type" value={form.type} onChange={(e) => set("type", e.target.value)} className="input">
                  <Opt value="">Choose a type</Opt>
                  {BATTERY_TYPES.map((t) => (
                    <Opt key={t} value={t}>
                      <T>{t}</T>
                    </Opt>
                  ))}
                </select>
              </div>
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label htmlFor="np-voltage" className="mb-1.5 block text-sm font-medium">
                    <T>Voltage (V)</T>
                  </label>
                  <input id="np-voltage" inputMode="decimal" value={form.voltage} onChange={(e) => set("voltage", e.target.value)} className="input" />
                </div>
                <div>
                  <label htmlFor="np-plates" className="mb-1.5 block text-sm font-medium">
                    <T>Plates</T>
                  </label>
                  <input id="np-plates" inputMode="numeric" value={form.plates} onChange={(e) => set("plates", e.target.value)} className="input" />
                </div>
                <div>
                  <label htmlFor="np-ah" className="mb-1.5 block text-sm font-medium">
                    <T>Ah rating</T>
                  </label>
                  <input id="np-ah" inputMode="decimal" value={form.ah_rating} onChange={(e) => set("ah_rating", e.target.value)} className="input" />
                </div>
              </div>
            </>
          ) : (
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label htmlFor="np-type2" className="mb-1.5 block text-sm font-medium">
                  <T>{form.category === "panel" ? "Panel type" : "Kind of accessory"}</T>
                </label>
                <select id="np-type2" value={otherType ? OTHER_TYPE : form.type} onChange={(e) => changeType(e.target.value)} className="input">
                  <Opt value="">Choose a type</Opt>
                  {typeOptions.map((t) => (
                    <Opt key={t} value={t}>
                      <T>{t}</T>
                    </Opt>
                  ))}
                  <Opt value={OTHER_TYPE}>Other (type your own)</Opt>
                </select>
                {otherType && (
                  <input
                    id="np-type2-other"
                    type="text"
                    autoFocus
                    autoComplete="off"
                    value={form.type}
                    onChange={(e) => set("type", e.target.value)}
                    placeholder={tt("Type it in")}
                    className="input mt-2"
                  />
                )}
              </div>
              {form.category === "panel" && (
                <div>
                  <label htmlFor="np-wattage" className="mb-1.5 block text-sm font-medium">
                    <T>Wattage (W)</T>
                  </label>
                  <input id="np-wattage" inputMode="numeric" value={form.wattage} onChange={(e) => set("wattage", e.target.value)} className="input" />
                </div>
              )}
            </div>
          )}

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="np-warranty" className="mb-1.5 block text-sm font-medium">
                <T>Warranty (months)</T>
              </label>
              <input id="np-warranty" inputMode="numeric" value={form.warranty_months} onChange={(e) => set("warranty_months", e.target.value)} className="input" />
            </div>
            <div>
              <label htmlFor="np-reorder" className="mb-1.5 block text-sm font-medium">
                <T>Reorder level</T>
              </label>
              <input id="np-reorder" inputMode="numeric" value={form.reorder_level} onChange={(e) => set("reorder_level", e.target.value)} placeholder={tt("Optional")} aria-invalid={!!errors.reorder_level} className="input" />
              {errors.reorder_level && <p className="mt-1 text-sm text-terminal-deep"><T>{errors.reorder_level}</T></p>}
            </div>
          </div>

          <div>
            <label htmlFor="np-sale-price" className="mb-1.5 block text-sm font-medium">
              <T>Sale price (Rs)</T>
            </label>
            <input id="np-sale-price" inputMode="decimal" value={form.sale_price} onChange={(e) => set("sale_price", e.target.value)} placeholder={tt("What you'll charge customers -- optional for now")} aria-invalid={!!errors.sale_price} className="input tabular-nums" />
            {errors.sale_price && <p className="mt-1 text-sm text-terminal-deep">{errors.sale_price}</p>}
          </div>

          <details className="rounded-2xl bg-plate/60 p-3.5">
            <summary className="cursor-pointer text-sm font-semibold text-lead"><T>More (HS code, unit)</T></summary>
            <div className="mt-3 grid grid-cols-2 gap-4">
              <div>
                <label htmlFor="np-hs" className="mb-1.5 block text-sm font-medium">
                  <T>HS code</T>
                </label>
                <input id="np-hs" value={form.hs_code} onChange={(e) => set("hs_code", e.target.value)} className="input" />
              </div>
              <div>
                <label htmlFor="np-uom" className="mb-1.5 block text-sm font-medium">
                  <T>Unit</T>
                </label>
                <input id="np-uom" value={form.uom} onChange={(e) => set("uom", e.target.value)} placeholder={tt(DEFAULT_UOM)} className="input" />
              </div>
            </div>
          </details>
        </div>

        <div className="pb-safe border-t border-line bg-white px-5 py-4">
          <div className="flex justify-end gap-3">
            <button type="button" onClick={onClose} className="btn btn-quiet">
              <T>Cancel</T>
            </button>
            <button type="submit" className="btn btn-primary">
              <T>Add to bill</T>
            </button>
          </div>
        </div>
      </form>
    </Sheet>
  );
}
