export default function Loading() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center p-6">
      <div className="text-sm text-muted-foreground" role="status" aria-live="polite">
        Loading…
      </div>
    </div>
  );
}
