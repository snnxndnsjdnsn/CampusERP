'use client';

import { useEffect, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, humanise } from '@/lib/format';
import { asArray, asObject, rpcCall, useRpcAction } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

export type FeedbackTask = {
  feedback_cycle_id: number;
  cycle_name: string;
  questionnaire_type: string;
  is_anonymous: boolean;
  end_at: string | null;
  course_offering_id: number | null;
  course_label: string | null;
  faculty_assignment_id: number | null;
  instructor_name: string | null;
  submitted: boolean;
};

export type FeedbackCycleOption = {
  feedback_cycle_id: number;
  cycle_name: string;
  status: string;
  start_at: string;
  end_at: string;
  result_visibility: string;
};

type Choice = { id: number; text: string };

type FormItem = {
  questionnaire_item_id: number;
  display_order: number;
  is_required: boolean;
  question_text: string;
  response_type: string;
  category_name: string | null;
  choices: Choice[];
};

type AnswerValue = string | number | number[];

type Offering = {
  course_offering_id: number;
  course_label: string;
  programme_name: string | null;
  responses: number;
};

type ResultQuestion = {
  questionnaire_item_id: number;
  question_text: string;
  response_type: string;
  answered: number;
  average: number | null;
  distribution: { label: string; count: number }[];
  texts: string[];
};

type ResultPayload = {
  cycle_name: string;
  visibility: string;
  questionnaire_type: string;
  anonymous: boolean;
  response_count: number;
  suppressed: boolean;
  minimum: number;
  questions: ResultQuestion[];
};

/* --------------------------------------------------------------- helpers */

function taskKey(t: FeedbackTask): string {
  return `${t.feedback_cycle_id}:${t.course_offering_id ?? 0}:${t.faculty_assignment_id ?? 0}`;
}

function normaliseItem(raw: Record<string, unknown>): FormItem {
  const choices = asArray<Record<string, unknown>>(raw.choices).map((c) => ({
    id: Number(c.id),
    text: String(c.text ?? ''),
  }));
  return {
    questionnaire_item_id: Number(raw.questionnaire_item_id),
    display_order: Number(raw.display_order ?? 0),
    is_required: raw.is_required === true,
    question_text: String(raw.question_text ?? ''),
    response_type: String(raw.response_type ?? 'TEXT'),
    category_name: raw.category_name === null || raw.category_name === undefined ? null : String(raw.category_name),
    choices,
  };
}

function normaliseResults(raw: unknown): ResultPayload {
  const o = asObject(raw);
  const questions = asArray<Record<string, unknown>>(o.questions).map((q) => ({
    questionnaire_item_id: Number(q.questionnaire_item_id ?? 0),
    question_text: String(q.question_text ?? ''),
    response_type: String(q.response_type ?? ''),
    answered: Number(q.answered ?? 0),
    average: q.average === null || q.average === undefined ? null : Number(q.average),
    distribution: asArray<Record<string, unknown>>(q.distribution).map((d) => ({
      label: String(d.label ?? ''),
      count: Number(d.count ?? 0),
    })),
    texts: asArray<string>(q.texts).map((t) => String(t)),
  }));
  return {
    cycle_name: String(o.cycle_name ?? ''),
    visibility: String(o.visibility ?? ''),
    questionnaire_type: String(o.questionnaire_type ?? ''),
    anonymous: o.anonymous === true,
    response_count: Number(o.response_count ?? 0),
    suppressed: o.suppressed === true,
    minimum: Number(o.minimum ?? 0),
    questions,
  };
}

/* ------------------------------------------------------- student: the form */

function FeedbackForm({ task, onClose }: { task: FeedbackTask; onClose: () => void }) {
  const { busy, error, notice, run } = useRpcAction();
  const [items, setItems] = useState<FormItem[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [answers, setAnswers] = useState<Record<number, AnswerValue>>({});

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const res = await rpcCall<Record<string, unknown>[]>('feedback_form', { p_cycle_id: task.feedback_cycle_id });
      if (cancelled) return;
      if (!res.ok) {
        setLoadError(res.error);
        return;
      }
      setItems(res.data.map(normaliseItem));
    })();
    return () => {
      cancelled = true;
    };
  }, [task.feedback_cycle_id]);

  function setAnswer(id: number, value: AnswerValue) {
    setAnswers((prev) => ({ ...prev, [id]: value }));
  }

  function toggleChoice(id: number, choiceId: number, checked: boolean) {
    const current = answers[id];
    const list = Array.isArray(current) ? current : [];
    setAnswer(id, checked ? [...list, choiceId] : list.filter((c) => c !== choiceId));
  }

  async function submit() {
    if (!items) return;
    const payload = items.map((item) => {
      const value = answers[item.questionnaire_item_id];
      const base = { questionnaire_item_id: item.questionnaire_item_id };
      if (item.response_type === 'RATING') return { ...base, score: Number(value ?? 0) };
      if (item.response_type === 'SINGLE_CHOICE') return { ...base, choice_id: Number(value ?? 0) };
      if (item.response_type === 'MULTIPLE_CHOICE') return { ...base, choice_ids: Array.isArray(value) ? value : [] };
      return { ...base, text: String(value ?? '') };
    });
    const res = await run<string>(
      'feedback_submit',
      {
        p_cycle_id: task.feedback_cycle_id,
        p_course_offering_id: task.course_offering_id,
        p_faculty_assignment_id: task.faculty_assignment_id,
        p_answers: payload,
      },
      { success: 'Your feedback has been recorded.' },
    );
    if (res.ok) onClose();
  }

  if (loadError) return <ErrorPanel message={loadError} />;
  if (!items) return <p className="text-sm text-muted-foreground">Loading the questionnaire…</p>;
  if (items.length === 0) return <EmptyState title="This questionnaire has no questions" />;

  return (
    <div className="space-y-4">
      {items.map((item) => (
        <div key={item.questionnaire_item_id} className="rounded-md border border-border p-3">
          <Label className="block text-sm font-medium">
            {item.display_order}. {item.question_text}
            {item.is_required ? <span className="text-destructive"> *</span> : null}
          </Label>
          {item.category_name ? <p className="mt-0.5 text-xs text-muted-foreground">{item.category_name}</p> : null}

          <div className="mt-2">
            {item.response_type === 'RATING' ? (
              <Input
                type="number"
                min={1}
                max={10}
                step={1}
                className="w-28"
                value={String(answers[item.questionnaire_item_id] ?? '')}
                onChange={(e) => setAnswer(item.questionnaire_item_id, Number(e.target.value))}
                aria-label={`Rating for: ${item.question_text}`}
              />
            ) : item.response_type === 'SINGLE_CHOICE' ? (
              <div className="space-y-1">
                {item.choices.map((c) => (
                  <label key={c.id} className="flex items-center gap-2 text-sm">
                    <input
                      type="radio"
                      name={`q-${item.questionnaire_item_id}`}
                      checked={Number(answers[item.questionnaire_item_id] ?? 0) === c.id}
                      onChange={() => setAnswer(item.questionnaire_item_id, c.id)}
                    />
                    <span>{c.text}</span>
                  </label>
                ))}
              </div>
            ) : item.response_type === 'MULTIPLE_CHOICE' ? (
              <div className="space-y-1">
                {item.choices.map((c) => {
                  const current = answers[item.questionnaire_item_id];
                  const list = Array.isArray(current) ? current : [];
                  return (
                    <label key={c.id} className="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={list.includes(c.id)}
                        onChange={(e) => toggleChoice(item.questionnaire_item_id, c.id, e.target.checked)}
                      />
                      <span>{c.text}</span>
                    </label>
                  );
                })}
              </div>
            ) : (
              <Textarea
                value={String(answers[item.questionnaire_item_id] ?? '')}
                onChange={(e) => setAnswer(item.questionnaire_item_id, e.target.value)}
                aria-label={`Answer for: ${item.question_text}`}
              />
            )}
          </div>
        </div>
      ))}

      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}

      <div className="flex gap-2">
        <Button onClick={submit} disabled={busy}>
          {busy ? 'Submitting…' : 'Submit feedback'}
        </Button>
        <Button variant="outline" onClick={onClose} disabled={busy}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

/* --------------------------------------------------- student: the task list */

export function FeedbackTaskList({ tasks }: { tasks: FeedbackTask[] }) {
  const [openKey, setOpenKey] = useState<string | null>(null);

  if (tasks.length === 0) {
    return <EmptyState title="No feedback is open for you" description="When a feedback cycle opens for your courses, it appears here." />;
  }

  return (
    <div className="space-y-3">
      {tasks.map((task) => {
        const key = taskKey(task);
        const open = openKey === key;
        return (
          <Card key={key}>
            <CardHeader>
              <CardTitle className="flex flex-wrap items-center justify-between gap-2">
                <span>{task.course_label ?? task.cycle_name}</span>
                <Badge variant={task.submitted ? 'success' : 'warning'}>
                  {task.submitted ? 'Submitted' : 'Awaiting your response'}
                </Badge>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Cycle</dt>
                  <dd>{task.cycle_name}</dd>
                </div>
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Type</dt>
                  <dd>{humanise(task.questionnaire_type)}</dd>
                </div>
                {task.instructor_name ? (
                  <div className="flex gap-2">
                    <dt className="text-muted-foreground">Instructor</dt>
                    <dd>{task.instructor_name}</dd>
                  </div>
                ) : null}
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Closes</dt>
                  <dd>{formatDateTime(task.end_at)}</dd>
                </div>
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Anonymity</dt>
                  <dd>{task.is_anonymous ? 'Anonymous' : 'Identified'}</dd>
                </div>
              </dl>

              {task.submitted ? (
                <p className="text-sm text-muted-foreground">You have already responded to this feedback.</p>
              ) : open ? (
                <FeedbackForm task={task} onClose={() => setOpenKey(null)} />
              ) : (
                <Button onClick={() => setOpenKey(key)}>Give feedback</Button>
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------- staff: the results */

export function FeedbackResultsExplorer({ cycles }: { cycles: FeedbackCycleOption[] }) {
  const [cycleId, setCycleId] = useState<number | null>(cycles.length > 0 ? (cycles[0]?.feedback_cycle_id ?? null) : null);
  const [offerings, setOfferings] = useState<Offering[]>([]);
  const [offeringId, setOfferingId] = useState<number | null>(null);
  const [results, setResults] = useState<ResultPayload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      if (cycleId === null) {
        setOfferings([]);
        return;
      }
      const res = await rpcCall<Record<string, unknown>[]>('feedback_cycle_offerings', { p_cycle_id: cycleId });
      if (cancelled) return;
      if (!res.ok) {
        setError(res.error);
        setOfferings([]);
        return;
      }
      setError(null);
      setOfferings(
        res.data.map((o) => ({
          course_offering_id: Number(o.course_offering_id),
          course_label: String(o.course_label ?? ''),
          programme_name: o.programme_name === null || o.programme_name === undefined ? null : String(o.programme_name),
          responses: Number(o.responses ?? 0),
        })),
      );
    })();
    return () => {
      cancelled = true;
    };
  }, [cycleId]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      if (cycleId === null) {
        setResults(null);
        return;
      }
      setLoading(true);
      const res = await rpcCall<unknown>('feedback_results', {
        p_cycle_id: cycleId,
        p_course_offering_id: offeringId,
      });
      if (cancelled) return;
      setLoading(false);
      if (!res.ok) {
        setError(res.error);
        setResults(null);
        return;
      }
      setError(null);
      setResults(normaliseResults(res.data));
    })();
    return () => {
      cancelled = true;
    };
  }, [cycleId, offeringId]);

  if (cycles.length === 0) {
    return <EmptyState title="No feedback cycles exist yet" description="Cycles appear here once the administrator schedules them." />;
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="feedback-cycle">Cycle</Label>
          <Select
            id="feedback-cycle"
            value={cycleId === null ? '' : String(cycleId)}
            onChange={(e) => {
              setCycleId(Number(e.target.value));
              setOfferingId(null);
            }}
          >
            {cycles.map((c) => (
              <option key={c.feedback_cycle_id} value={c.feedback_cycle_id}>
                {c.cycle_name} — {humanise(c.status)}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="feedback-offering">Course offering</Label>
          <Select
            id="feedback-offering"
            value={offeringId === null ? '' : String(offeringId)}
            onChange={(e) => setOfferingId(e.target.value === '' ? null : Number(e.target.value))}
          >
            <option value="">All offerings in this cycle</option>
            {offerings.map((o) => (
              <option key={o.course_offering_id} value={o.course_offering_id}>
                {o.course_label} ({o.responses} responses)
              </option>
            ))}
          </Select>
        </div>
      </div>

      {error ? <ErrorPanel message={error} /> : null}
      {loading ? <p className="text-sm text-muted-foreground">Loading results…</p> : null}

      {results ? (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Badge variant="info">{humanise(results.visibility)}</Badge>
            <Badge variant="muted">{humanise(results.questionnaire_type)}</Badge>
            <Badge variant={results.anonymous ? 'muted' : 'warning'}>{results.anonymous ? 'Anonymous' : 'Identified'}</Badge>
            <span className="text-muted-foreground">
              {results.response_count} response{results.response_count === 1 ? '' : 's'}
            </span>
          </div>

          {results.suppressed ? (
            <EmptyState
              title="Results are withheld"
              description={`At least ${results.minimum} responses are needed before results can be shown.`}
            />
          ) : results.questions.length === 0 ? (
            <EmptyState title="No questions in this questionnaire" />
          ) : (
            results.questions.map((q) => (
              <Card key={q.questionnaire_item_id}>
                <CardHeader>
                  <CardTitle className="text-sm font-medium">{q.question_text}</CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <p className="text-xs text-muted-foreground">
                    {humanise(q.response_type)} · {q.answered} answered
                    {q.average !== null ? ` · average ${q.average}` : ''}
                  </p>
                  {q.distribution.length > 0 ? (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Response</TableHead>
                          <TableHead className="text-right">Count</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {q.distribution.map((d) => (
                          <TableRow key={d.label}>
                            <TableCell>{d.label}</TableCell>
                            <TableCell className="text-right tabular-nums">{d.count}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  ) : null}
                  {q.texts.length > 0 ? (
                    <ul className="space-y-1 text-sm">
                      {q.texts.map((t, i) => (
                        <li key={`${q.questionnaire_item_id}-${i}`} className="rounded border border-border p-2">
                          {t}
                        </li>
                      ))}
                    </ul>
                  ) : null}
                </CardContent>
              </Card>
            ))
          )}
        </div>
      ) : null}
    </div>
  );
}
