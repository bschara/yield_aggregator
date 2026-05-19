export function ErrorBanner({ message }: { message: string }) {
  return (
    <div className="rounded-lg bg-red-900/30 border border-red-800 text-red-400 text-sm px-4 py-3">
      {message}
    </div>
  );
}
