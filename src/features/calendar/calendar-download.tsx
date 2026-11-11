'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { FileDown, FileText, Loader2 } from 'lucide-react';
import { buildCalendarExport, type CalendarExportInput } from './calendar-export';

type DownloadKind = 'word' | 'pdf';

/**
 * The Download Word / Download PDF buttons of the calendar of events.
 *
 * The click builds the export model from exactly what the page renders, then
 * hands it to `calendar-documents.ts`, which loads `docx` or `jspdf` on demand
 * and returns a blob. Failures stay on the button (an `role="alert"` line
 * underneath) rather than navigating away from the calendar.
 */
export function CalendarDownload(props: Omit<CalendarExportInput, 'generatedOn'>) {
  const [busy, setBusy] = useState<DownloadKind | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function download(kind: DownloadKind) {
    setBusy(kind);
    setError(null);
    try {
      const generatedOn = new Date();
      const model = buildCalendarExport({ ...props, generatedOn });
      const stamp = generatedOn.toISOString().slice(0, 10);
      const { pdfBlob, wordBlob } = await import('./calendar-documents');
      const blob = kind === 'word' ? await wordBlob(model) : await pdfBlob(model);
      saveBlob(blob, `calendar-of-events-${stamp}.${kind === 'word' ? 'docx' : 'pdf'}`);
    } catch {
      setError('The document could not be built. Please try again.');
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex flex-wrap justify-end gap-2">
        <Button size="sm" variant="outline" onClick={() => void download('word')} disabled={busy !== null}>
          {busy === 'word' ? (
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
          ) : (
            <FileText className="h-4 w-4" aria-hidden />
          )}
          Download Word
        </Button>
        <Button size="sm" variant="outline" onClick={() => void download('pdf')} disabled={busy !== null}>
          {busy === 'pdf' ? (
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
          ) : (
            <FileDown className="h-4 w-4" aria-hidden />
          )}
          Download PDF
        </Button>
      </div>
      {error ? (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      ) : null}
    </div>
  );
}

/** Save a generated blob as a named file, the way a download link would. */
function saveBlob(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = name;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
