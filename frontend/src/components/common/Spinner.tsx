export function Spinner({ size = 5 }: { size?: number }) {
  return (
    <div
      className={`w-${size} h-${size} border-2 border-gray-600 border-t-brand-500 rounded-full animate-spin`}
    />
  );
}
