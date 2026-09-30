Copy `components/PosDemo.tsx` and `lib/demo.ts` into the website repo (Next 14 / Tailwind 3), add
`NEXT_PUBLIC_POS_DEMO_URL=https://demo.makemystore.online` in Vercel, and render `<PosDemo />` after the
`PageHeader` in `app/pos-system/page.tsx`. Still to do: GA4 events, contact-form prefill for `?source=demo`,
60-second CTA, 10 s iframe timeout fallback, new FAQ "Can I try it first?".
