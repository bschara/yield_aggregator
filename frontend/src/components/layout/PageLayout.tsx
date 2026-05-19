import type { ReactNode } from "react";

export function PageLayout({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-semibold text-white mb-6">{title}</h1>
      {children}
    </div>
  );
}
