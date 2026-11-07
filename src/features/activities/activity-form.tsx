'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Select, Textarea } from '@/components/ui/input';
import { useRpcAction } from '@/features/shared/client-rpc';
import { ACHIEVEMENT_TYPES, type ActivityTypeRow, type Option, type StudentActivityDetail, type StudentOption } from './types';

/**
 * The student activity editor.
 *
 * The fields are the ones `student_activity_save` understands; the database
 * validates the dates, the achievement type and the link, and refuses anything
 * it will not accept.
 */

export function ActivityForm({
  activity,
  types,
  years,
  participationLevels,
  eventModes,
  students,
  onSaved,
  onCancel,
}: {
  activity: StudentActivityDetail | null;
  types: ActivityTypeRow[];
  years: Option[];
  participationLevels: Option[];
  eventModes: Option[];
  students: StudentOption[];
  onSaved: (id: number) => void;
  onCancel: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [typeId, setTypeId] = useState(activity ? String(activity.student_activity_type_id) : '');

  const activeTypes = types.filter((t) => t.is_active !== false);
  const selectedType = activeTypes.find((t) => String(t.student_activity_type_id) === typeId) ?? null;

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const num = (key: string) => (str(key) ? Number(str(key)) : null);

    const payload: Record<string, unknown> = {
      student_activity_type_id: num('student_activity_type_id'),
      activity_title: str('activity_title'),
      academic_year_id: num('academic_year_id'),
      participation_level_id: num('participation_level_id'),
      event_mode_id: num('event_mode_id'),
      organizer_name: str('organizer_name'),
      event_name: str('event_name'),
      team_name: str('team_name'),
      participation_role: str('participation_role'),
      start_date: str('start_date'),
      end_date: str('end_date'),
      venue_name: str('venue_name'),
      city: str('city'),
      achievement_type: str('achievement_type') || 'PARTICIPATION',
      position_rank: num('position_rank'),
      award_name: str('award_name'),
      activity_url: str('activity_url'),
      description: str('description'),
      outcomes: str('outcomes'),
    };

    const result = await run<number>('student_activity_save', {
      p_activity_id: activity ? activity.student_activity_id : null,
      p_student_id: activity ? null : num('student_id'),
      p: payload,
    });
    if (result.ok) onSaved(result.data);
  }

  return (
    <form onSubmit={submit} className="space-y-4" noValidate>
      {error ? <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{error}</p> : null}

      <div className="grid gap-3 md:grid-cols-3">
        {!activity ? (
          <div>
            <label htmlFor="activity-student" className="mb-1 block text-sm font-medium leading-none">
              Student
            </label>
            <Select id="activity-student" name="student_id" defaultValue="">
              <option value="">Yourself</option>
              {students.map((s) => (
                <option key={s.student_id} value={s.student_id}>
                  {s.display_name} · {s.student_number}
                </option>
              ))}
            </Select>
          </div>
        ) : null}

        <div>
          <label htmlFor="activity-type" className="mb-1 block text-sm font-medium leading-none">
            Activity type <span className="text-destructive">*</span>
          </label>
          <Select
            id="activity-type"
            name="student_activity_type_id"
            required
            value={typeId}
            onChange={(e) => setTypeId(e.target.value)}
          >
            <option value="">Select a type</option>
            {activeTypes.map((t) => (
              <option key={t.student_activity_type_id} value={t.student_activity_type_id}>
                {t.type_name} · {t.activity_group}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="activity-title" className="mb-1 block text-sm font-medium leading-none">
            Title <span className="text-destructive">*</span>
          </label>
          <Input
            id="activity-title"
            name="activity_title"
            required
            maxLength={500}
            defaultValue={activity?.activity_title ?? ''}
            placeholder="Inter-college debate"
          />
        </div>

        <div>
          <label htmlFor="activity-year" className="mb-1 block text-sm font-medium leading-none">
            Academic year
          </label>
          <Select id="activity-year" name="academic_year_id" defaultValue={activity?.academic_year_id ?? ''}>
            <option value="">Not stated</option>
            {years.map((y) => (
              <option key={y.id} value={y.id}>
                {y.label}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="activity-level" className="mb-1 block text-sm font-medium leading-none">
            Participation level
          </label>
          <Select id="activity-level" name="participation_level_id" defaultValue={activity?.participation_level_id ?? ''}>
            <option value="">Not stated</option>
            {participationLevels.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="activity-mode" className="mb-1 block text-sm font-medium leading-none">
            Event mode
          </label>
          <Select id="activity-mode" name="event_mode_id" defaultValue={activity?.event_mode_id ?? ''}>
            <option value="">Not stated</option>
            {eventModes.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="activity-organizer" className="mb-1 block text-sm font-medium leading-none">
            Organiser
          </label>
          <Input
            id="activity-organizer"
            name="organizer_name"
            maxLength={250}
            defaultValue={activity?.organizer_name ?? ''}
          />
        </div>

        <div>
          <label htmlFor="activity-event" className="mb-1 block text-sm font-medium leading-none">
            Event name
          </label>
          <Input id="activity-event" name="event_name" maxLength={250} defaultValue={activity?.event_name ?? ''} />
        </div>

        <div>
          <label htmlFor="activity-team" className="mb-1 block text-sm font-medium leading-none">
            Team name
            {selectedType?.requires_team_details ? <span className="text-destructive"> *</span> : null}
          </label>
          <Input id="activity-team" name="team_name" maxLength={250} defaultValue={activity?.team_name ?? ''} />
        </div>

        <div>
          <label htmlFor="activity-role" className="mb-1 block text-sm font-medium leading-none">
            Your role
          </label>
          <Input
            id="activity-role"
            name="participation_role"
            maxLength={150}
            defaultValue={activity?.participation_role ?? ''}
          />
        </div>

        <div>
          <label htmlFor="activity-start" className="mb-1 block text-sm font-medium leading-none">
            Start date
          </label>
          <Input id="activity-start" name="start_date" type="date" defaultValue={activity?.start_date ?? ''} />
        </div>

        <div>
          <label htmlFor="activity-end" className="mb-1 block text-sm font-medium leading-none">
            End date
          </label>
          <Input id="activity-end" name="end_date" type="date" defaultValue={activity?.end_date ?? ''} />
        </div>

        <div>
          <label htmlFor="activity-venue" className="mb-1 block text-sm font-medium leading-none">
            Venue
          </label>
          <Input id="activity-venue" name="venue_name" maxLength={250} defaultValue={activity?.venue_name ?? ''} />
        </div>

        <div>
          <label htmlFor="activity-city" className="mb-1 block text-sm font-medium leading-none">
            City
          </label>
          <Input id="activity-city" name="city" maxLength={100} defaultValue={activity?.city ?? ''} />
        </div>

        {selectedType?.supports_achievement !== false ? (
          <>
            <div>
              <label htmlFor="activity-achievement" className="mb-1 block text-sm font-medium leading-none">
                Achievement
              </label>
              <Select
                id="activity-achievement"
                name="achievement_type"
                defaultValue={activity?.achievement_type ?? 'PARTICIPATION'}
              >
                {ACHIEVEMENT_TYPES.map((a) => (
                  <option key={a} value={a}>
                    {a.replace(/_/g, ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase())}
                  </option>
                ))}
              </Select>
            </div>

            <div>
              <label htmlFor="activity-rank" className="mb-1 block text-sm font-medium leading-none">
                Position
              </label>
              <Input
                id="activity-rank"
                name="position_rank"
                type="number"
                min={1}
                defaultValue={activity?.position_rank ?? ''}
              />
            </div>

            <div>
              <label htmlFor="activity-award" className="mb-1 block text-sm font-medium leading-none">
                Award
              </label>
              <Input id="activity-award" name="award_name" maxLength={250} defaultValue={activity?.award_name ?? ''} />
            </div>
          </>
        ) : null}

        <div className="md:col-span-3">
          <label htmlFor="activity-url" className="mb-1 block text-sm font-medium leading-none">
            Link
          </label>
          <Input
            id="activity-url"
            name="activity_url"
            type="url"
            maxLength={1000}
            defaultValue={activity?.activity_url ?? ''}
            placeholder="https://…"
          />
        </div>

        <div className="md:col-span-3">
          <label htmlFor="activity-description" className="mb-1 block text-sm font-medium leading-none">
            Description
          </label>
          <Textarea
            id="activity-description"
            name="description"
            rows={3}
            maxLength={5000}
            defaultValue={activity?.description ?? ''}
          />
        </div>

        <div className="md:col-span-3">
          <label htmlFor="activity-outcomes" className="mb-1 block text-sm font-medium leading-none">
            Outcomes
          </label>
          <Textarea
            id="activity-outcomes"
            name="outcomes"
            rows={3}
            maxLength={5000}
            defaultValue={activity?.outcomes ?? ''}
          />
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={busy}>
          {busy ? 'Saving…' : activity ? 'Save changes' : 'Create activity'}
        </Button>
        <Button type="button" variant="outline" onClick={onCancel} disabled={busy}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
