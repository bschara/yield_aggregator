export function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-gray-500">
      <span className="text-4xl mb-3">—</span>
      <p className="text-sm">{message}</p>
    </div>
  );
}
