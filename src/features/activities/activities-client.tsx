'use client';

import { useCallback, useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { rpcCall } from '@/features/shared/client-rpc';
import { formatDate, formatNumber, humanise } from '@/lib/format';
import { ActivityForm } from './activity-form';
import { ActivityPanel } from './activity-panel';
import type {
  ActivityReportRow,
  ActivityTypeRow,
  Option,
  StudentActivityDetail,
  StudentActivityRow,
  StudentOption,
} from './types';

/**
 * The student activities desk.
 *
 * `student_activity_list` decides which records the caller may see; opening one
 * asks `student_activity_get` for the full record. Every write is a
 * `student_activity_*` function, and the browser never decides whether a move
 * is allowed.
 */
export function ActivitiesDesk({
  activities,
  types,
  years,
  participationLevels,
  eventModes,
  students,
  documentTypes,
  evidenceTypes,
  report,
  readError,
}: {
  activities: StudentActivityRow[];
  types: ActivityTypeRow[];
  years: Option[];
  participationLevels: Option[];
  eventModes: Option[];
  students: StudentOption[];
  documentTypes: Option[];
  evidenceTypes: Option[];
  report: ActivityReportRow[];
  readError: string | null;
}) {
  const [detail, setDetail] = useState<StudentActivityDetail | null>(null);
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  const open = useCallback(async (id: number) => {
    setLoading(true);
    setLoadError(null);
    const result = await rpcCall<StudentActivityDetail>('student_activity_get', { p_activity_id: id });
    setLoading(false);
    if (!result.ok) {
      setLoadError(result.error);
      return;
    }
    setDetail(result.data);
    setCreating(false);
    setEditing(false);
  }, []);

  return (
    <div className="space-y-4">
      {readError ? (
        <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{readError}</p>
      ) : null}
      {loadError ? (
        <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{loadError}</p>
      ) : null}

      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          {activities.length} activit{activities.length === 1 ? 'y' : 'ies'} visible to you.
        </p>
        <Button
          size="sm"
          disabled={loading}
          onClick={() => {
            setCreating((v) => !v);
            setEditing(false);
            setDetail(null);
          }}
        >
          {creating ? 'Close the form' : 'New activity'}
        </Button>
      </div>

      {creating ? (
        <div className="rounded-lg border border-border bg-card p-4">
          <h3 className="mb-3 text-sm font-semibold">New activity</h3>
          <ActivityForm
            activity={null}
            types={types}
            years={years}
            participationLevels={participationLevels}
            eventModes={eventModes}
            students={students}
            onSaved={(id) => void open(id)}
            onCancel={() => setCreating(false)}
          />
        </div>
      ) : null}

      {editing && detail ? (
        <div className="rounded-lg border border-border bg-card p-4">
          <h3 className="mb-3 text-sm font-semibold">Edit activity</h3>
          <ActivityForm
            key={detail.student_activity_id}
            activity={detail}
            types={types}
            years={years}
            participationLevels={participationLevels}
            eventModes={eventModes}
            students={students}
            onSaved={() => void open(detail.student_activity_id)}
            onCancel={() => setEditing(false)}
          />
        </div>
      ) : null}

      {detail && !editing ? (
        <ActivityPanel
          detail={detail}
          documentTypes={documentTypes}
          evidenceTypes={evidenceTypes}
          students={students}
          onChanged={() => void open(detail.student_activity_id)}
          onClosed={() => setDetail(null)}
          onEdit={() => setEditing(true)}
        />
      ) : null}

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Activity
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Student
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Type
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Achievement
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Started
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Verification
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Approval
              </th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Evidence
              </th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Actions
              </th>
            </tr>
          </thead>
          <tbody>
            {activities.length === 0 ? (
              <tr>
                <td colSpan={9} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No student activities are visible to you yet.
                </td>
              </tr>
            ) : (
              activities.map((a) => (
                <tr key={a.student_activity_id} className="border-b last:border-0 hover:bg-muted/40">
                  <td className="px-3 py-2 font-medium">{a.activity_title}</td>
                  <td className="px-3 py-2">
                    <div>{a.student_name}</div>
                    <div className="text-xs text-muted-foreground">{a.student_number}</div>
                  </td>
                  <td className="px-3 py-2">{a.type_name}</td>
                  <td className="px-3 py-2">{a.achievement_type ? humanise(a.achievement_type) : '—'}</td>
                  <td className="px-3 py-2">{formatDate(a.start_date)}</td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(a.verification_status)}>{a.verification_status}</Badge>
                  </td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(a.approval_status)}>{a.approval_status}</Badge>
                  </td>
                  <td className="px-3 py-2 text-right tabular-nums">{formatNumber(a.evidence_count)}</td>
                  <td className="px-3 py-2 text-right">
                    <Button size="sm" variant="outline" disabled={loading} onClick={() => void open(a.student_activity_id)}>
                      Open
                    </Button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {report.length > 0 ? (
        <div className="overflow-x-auto rounded-lg border border-border">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/40">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Type
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Approval
                </th>
                <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Activities
                </th>
                <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Awards
                </th>
              </tr>
            </thead>
            <tbody>
              {report.map((r) => (
                <tr key={`${r.type_name}-${r.approval_status}`} className="border-b last:border-0">
                  <td className="px-3 py-2">{r.type_name}</td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(r.approval_status)}>{r.approval_status}</Badge>
                  </td>
                  <td className="px-3 py-2 text-right tabular-nums">{formatNumber(r.activities)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{formatNumber(r.winners)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
