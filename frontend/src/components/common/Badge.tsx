type Variant = "green" | "yellow" | "red" | "gray" | "purple";

const styles: Record<Variant, string> = {
  green: "bg-green-900/40 text-green-400 border border-green-800",
  yellow: "bg-yellow-900/40 text-yellow-400 border border-yellow-800",
  red: "bg-red-900/40 text-red-400 border border-red-800",
  gray: "bg-gray-800 text-gray-400 border border-gray-700",
  purple: "bg-purple-900/40 text-purple-400 border border-purple-800",
};

export function Badge({ label, variant = "gray" }: { label: string; variant?: Variant }) {
  return (
    <span className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${styles[variant]}`}>
      {label}
    </span>
  );
}
