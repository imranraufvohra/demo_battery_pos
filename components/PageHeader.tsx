import { T } from "@/components/T";
export default function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="anim-rise flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="font-display text-4xl font-bold leading-none tracking-tight md:text-5xl"><T>{title}</T></h1>
        {subtitle && <p className="mt-2 text-lead"><T>{subtitle}</T></p>}
      </div>
      {action}
    </div>
  );
}
