import { Button } from '@/components/ui/button';

export default function NotFound() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center p-6">
      <div className="w-full max-w-md rounded-lg border border-border bg-card p-6 text-center shadow-sm">
        <h1 className="text-lg font-semibold tracking-tight">Page not found</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          The page you asked for does not exist, or your role cannot see it.
        </p>
        <div className="mt-6 flex justify-center">
          <a href="/dashboard">
            <Button variant="outline">Back to the dashboard</Button>
          </a>
        </div>
      </div>
    </div>
  );
}
