'use client';

import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDate, humanise } from '@/lib/format';
import { useRpcAction } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

export type SensitivePan = {
  id: number;
  masked: string;
  name: string;
  status: string;
  remarks: string | null;
  issue_date: string | null;
  updated_at: string | null;
};

export type SensitiveAadhaar = {
  id: number;
  masked: string;
  name: string;
  status: string;
  remarks: string | null;
  purpose: string | null;
  updated_at: string | null;
};

export type SensitiveBank = {
  id: number;
  holder: string;
  bank: string;
  branch: string | null;
  masked: string;
  type: string;
  ifsc: string | null;
  upi: string | null;
  is_primary: boolean;
  is_salary: boolean;
  account_status: string;
  status: string;
  remarks: string | null;
};

export type SensitiveCan = {
  owner: boolean;
  edit_pan: boolean;
  edit_aadhaar: boolean;
  edit_bank: boolean;
  verify_pan: boolean;
  verify_aadhaar: boolean;
  verify_bank: boolean;
  reveal_pan: boolean;
  reveal_aadhaar: boolean;
  reveal_bank: boolean;
  delete_pan: boolean;
  delete_aadhaar: boolean;
  delete_bank: boolean;
};

export type SensitiveSummary = {
  pan: SensitivePan | null;
  aadhaar: SensitiveAadhaar | null;
  bank: SensitiveBank[];
  can: SensitiveCan;
};

export type CompetencyRow = {
  course_id: number;
  course_code: string;
  course_title: string;
  level: string;
  valid_from: string | null;
  valid_to: string | null;
  active: boolean;
};

export type CompetencySummary = {
  can_edit: boolean;
  can_delete: boolean;
  rows: CompetencyRow[];
};

export type CourseOption = { course_id: number; course_code: string; course_title: string };

export const EMPTY_CAN: SensitiveCan = {
  owner: false,
  edit_pan: false,
  edit_aadhaar: false,
  edit_bank: false,
  verify_pan: false,
  verify_aadhaar: false,
  verify_bank: false,
  reveal_pan: false,
  reveal_aadhaar: false,
  reveal_bank: false,
  delete_pan: false,
  delete_aadhaar: false,
  delete_bank: false,
};

/* ---------------------------------------------------------------- reveal */

/**
 * Reveal a full sensitive number.
 *
 * The database audits every reveal and insists on a purpose, so the form asks for
 * one before the call is made.
 */
export function SensitiveRevealControl({
  kind,
  id,
  label,
}: {
  kind: 'PAN' | 'AADHAAR' | 'BANK_ACCOUNT';
  id: number;
  label: string;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [open, setOpen] = useState(false);
  const [purpose, setPurpose] = useState('');
  const [value, setValue] = useState<string | null>(null);

  async function reveal() {
    const res = await run<string>('emp_sensitive_reveal', { p_kind: kind, p_id: id, p_purpose: purpose.trim() }, {
      success: 'The full number is shown below and the reveal has been recorded in the audit log.',
    });
    if (res.ok) {
      setValue(typeof res.data === 'string' ? res.data : '');
      setOpen(false);
    }
  }

  return (
    <div className="space-y-2">
      {value ? (
        <div className="rounded-md border border-border bg-muted/50 px-3 py-2">
          <div className="text-xs text-muted-foreground">{label}</div>
          <div className="font-mono text-sm">{value}</div>
        </div>
      ) : null}
      {open ? (
        <>
          <div className="space-y-1">
            <Label htmlFor={`reveal-purpose-${kind}-${id}`}>Why do you need the full {label}?</Label>
            <Input
              id={`reveal-purpose-${kind}-${id}`}
              value={purpose}
              onChange={(e) => setPurpose(e.target.value)}
              maxLength={500}
              placeholder="For example: payroll correction for March"
            />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex gap-2">
            <Button size="sm" onClick={reveal} disabled={busy || purpose.trim().length < 5}>
              {busy ? 'Revealing…' : 'Reveal'}
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
          </div>
        </>
      ) : (
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          Reveal
        </Button>
      )}
      {error && !open ? <ErrorPanel message={error} /> : null}
    </div>
  );
}

/* ---------------------------------------------------------------- review */

export function SensitiveReviewControl({
  kind,
  id,
  status,
}: {
  kind: 'PAN' | 'AADHAAR' | 'BANK_ACCOUNT';
  id: number;
  status: string;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [remarks, setRemarks] = useState('');
  const [open, setOpen] = useState(false);

  async function review(decision: 'VERIFIED' | 'REJECTED') {
    await run<void>(
      'emp_sensitive_review',
      { p_kind: kind, p_id: id, p_decision: decision, p_remarks: remarks.trim() || null },
      { success: decision === 'VERIFIED' ? 'The record has been verified.' : 'The record has been rejected.' },
    );
    setOpen(false);
    setRemarks('');
  }

  if (status !== 'PENDING') return null;

  return (
    <div className="space-y-2">
      {open ? (
        <>
          <div className="space-y-1">
            <Label htmlFor={`review-remarks-${kind}-${id}`}>Remarks (required to reject)</Label>
            <Textarea
              id={`review-remarks-${kind}-${id}`}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              maxLength={1000}
            />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={() => review('VERIFIED')} disabled={busy}>
              Verify
            </Button>
            <Button size="sm" variant="destructive" onClick={() => review('REJECTED')} disabled={busy || !remarks.trim()}>
              Reject
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
          </div>
        </>
      ) : (
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          Review
        </Button>
      )}
    </div>
  );
}

/* ---------------------------------------------------------------- delete */

export function SensitiveDeleteControl({ kind, id }: { kind: 'PAN' | 'AADHAAR' | 'BANK_ACCOUNT'; id: number }) {
  const { busy, error, notice, run } = useRpcAction();

  async function remove() {
    await run<void>('emp_sensitive_delete', { p_kind: kind, p_id: id }, { success: 'The record has been removed.' });
  }

  return (
    <div className="space-y-2">
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button size="sm" variant="ghost" onClick={remove} disabled={busy}>
        {busy ? 'Removing…' : 'Remove'}
      </Button>
    </div>
  );
}

/* ------------------------------------------------------------------- PAN */

export function PanPanel({ employeeId, pan, can }: { employeeId: number; pan: SensitivePan | null; can: SensitiveCan }) {
  const { busy, error, notice, run } = useRpcAction();
  const [value, setValue] = useState('');
  const [name, setName] = useState(pan?.name ?? '');
  const [issueDate, setIssueDate] = useState(pan?.issue_date ?? '');
  const [remarks, setRemarks] = useState('');

  async function save() {
    await run<number>(
      'emp_pan_save',
      {
        p_employee_id: employeeId,
        p_pan: value.trim().toUpperCase(),
        p_name: name.trim(),
        p_issue_date: issueDate || null,
        p_remarks: remarks.trim() || null,
      },
      { success: 'The PAN has been saved and is waiting for verification.' },
    );
    setValue('');
    setRemarks('');
  }

  return (
    <div className="space-y-3">
      {pan ? (
        <div className="flex flex-wrap items-center gap-3">
          <div>
            <div className="font-mono text-sm">{pan.masked}</div>
            <div className="text-xs text-muted-foreground">
              {pan.name} · {humanise(pan.status)}
              {pan.issue_date ? ` · issued ${formatDate(pan.issue_date)}` : ''}
            </div>
            {pan.remarks ? <div className="text-xs text-muted-foreground">{pan.remarks}</div> : null}
          </div>
          <div className="flex flex-wrap gap-2">
            {can.reveal_pan ? <SensitiveRevealControl kind="PAN" id={pan.id} label="PAN" /> : null}
            {can.verify_pan ? <SensitiveReviewControl kind="PAN" id={pan.id} status={pan.status} /> : null}
            {can.delete_pan ? <SensitiveDeleteControl kind="PAN" id={pan.id} /> : null}
          </div>
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">No PAN has been recorded yet.</p>
      )}

      {can.edit_pan ? (
        <div className="space-y-2 rounded-md border border-border p-3">
          <h4 className="text-sm font-semibold">{pan ? 'Replace the PAN' : 'Record the PAN'}</h4>
          <div className="grid gap-2 sm:grid-cols-3">
            <div className="space-y-1">
              <Label htmlFor="hr-pan">PAN</Label>
              <Input id="hr-pan" value={value} onChange={(e) => setValue(e.target.value)} maxLength={10} placeholder="ABCPE1234F" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-pan-name">Name on the PAN card</Label>
              <Input id="hr-pan-name" value={name} onChange={(e) => setName(e.target.value)} maxLength={200} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-pan-issue">Issue date</Label>
              <Input id="hr-pan-issue" type="date" value={issueDate} onChange={(e) => setIssueDate(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1">
            <Label htmlFor="hr-pan-remarks">Remarks</Label>
            <Input id="hr-pan-remarks" value={remarks} onChange={(e) => setRemarks(e.target.value)} maxLength={1000} />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <Button onClick={save} disabled={busy || value.trim() === '' || name.trim() === ''}>
            {busy ? 'Saving…' : 'Save the PAN'}
          </Button>
        </div>
      ) : null}
    </div>
  );
}

/* --------------------------------------------------------------- Aadhaar */

export function AadhaarPanel({
  employeeId,
  aadhaar,
  can,
}: {
  employeeId: number;
  aadhaar: SensitiveAadhaar | null;
  can: SensitiveCan;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [value, setValue] = useState('');
  const [name, setName] = useState(aadhaar?.name ?? '');
  const [purpose, setPurpose] = useState(aadhaar?.purpose ?? '');
  const [remarks, setRemarks] = useState('');

  async function save() {
    await run<number>(
      'emp_aadhaar_save',
      {
        p_employee_id: employeeId,
        p_aadhaar: value.trim(),
        p_name: name.trim(),
        p_purpose: purpose.trim(),
        p_remarks: remarks.trim() || null,
      },
      { success: 'The Aadhaar number has been saved and is waiting for verification.' },
    );
    setValue('');
    setRemarks('');
  }

  return (
    <div className="space-y-3">
      {aadhaar ? (
        <div className="flex flex-wrap items-center gap-3">
          <div>
            <div className="font-mono text-sm">{aadhaar.masked}</div>
            <div className="text-xs text-muted-foreground">
              {aadhaar.name} · {humanise(aadhaar.status)}
            </div>
            {aadhaar.purpose ? <div className="text-xs text-muted-foreground">Collected for: {aadhaar.purpose}</div> : null}
            {aadhaar.remarks ? <div className="text-xs text-muted-foreground">{aadhaar.remarks}</div> : null}
          </div>
          <div className="flex flex-wrap gap-2">
            {can.reveal_aadhaar ? <SensitiveRevealControl kind="AADHAAR" id={aadhaar.id} label="Aadhaar number" /> : null}
            {can.verify_aadhaar ? <SensitiveReviewControl kind="AADHAAR" id={aadhaar.id} status={aadhaar.status} /> : null}
            {can.delete_aadhaar ? <SensitiveDeleteControl kind="AADHAAR" id={aadhaar.id} /> : null}
          </div>
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">No Aadhaar number has been recorded yet.</p>
      )}

      {can.edit_aadhaar ? (
        <div className="space-y-2 rounded-md border border-border p-3">
          <h4 className="text-sm font-semibold">{aadhaar ? 'Replace the Aadhaar number' : 'Record the Aadhaar number'}</h4>
          <div className="grid gap-2 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="hr-aadhaar">Aadhaar number</Label>
              <Input id="hr-aadhaar" value={value} onChange={(e) => setValue(e.target.value)} maxLength={14} placeholder="1234 5678 9012" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-aadhaar-name">Name on the Aadhaar card</Label>
              <Input id="hr-aadhaar-name" value={name} onChange={(e) => setName(e.target.value)} maxLength={200} />
            </div>
          </div>
          <div className="space-y-1">
            <Label htmlFor="hr-aadhaar-purpose">Why is it collected?</Label>
            <Input id="hr-aadhaar-purpose" value={purpose} onChange={(e) => setPurpose(e.target.value)} maxLength={500} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="hr-aadhaar-remarks">Remarks</Label>
            <Input id="hr-aadhaar-remarks" value={remarks} onChange={(e) => setRemarks(e.target.value)} maxLength={1000} />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <Button onClick={save} disabled={busy || value.trim() === '' || name.trim() === '' || purpose.trim().length < 5}>
            {busy ? 'Saving…' : 'Save the Aadhaar number'}
          </Button>
        </div>
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------ bank account */

export function BankPanel({
  employeeId,
  accounts,
  can,
}: {
  employeeId: number;
  accounts: SensitiveBank[];
  can: SensitiveCan;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [accountId, setAccountId] = useState<number | null>(null);
  const [holder, setHolder] = useState('');
  const [bank, setBank] = useState('');
  const [branch, setBranch] = useState('');
  const [number, setNumber] = useState('');
  const [confirm, setConfirm] = useState('');
  const [ifsc, setIfsc] = useState('');
  const [type, setType] = useState('SAVINGS');
  const [upi, setUpi] = useState('');
  const [primary, setPrimary] = useState(false);
  const [salary, setSalary] = useState(false);

  function reset() {
    setAccountId(null);
    setHolder('');
    setBank('');
    setBranch('');
    setNumber('');
    setConfirm('');
    setIfsc('');
    setType('SAVINGS');
    setUpi('');
    setPrimary(false);
    setSalary(false);
  }

  async function save() {
    await run<number>(
      'emp_bank_save',
      {
        p_employee_id: employeeId,
        p_account_id: accountId,
        p_holder: holder.trim(),
        p_bank: bank.trim(),
        p_branch: branch.trim() || null,
        p_account_number: number.trim(),
        p_account_confirm: confirm.trim(),
        p_ifsc: ifsc.trim().toUpperCase(),
        p_type: type,
        p_upi: upi.trim() || null,
        p_is_primary: primary,
        p_is_salary: salary,
      },
      { success: 'The bank account has been saved and is waiting for verification.' },
    );
    reset();
  }

  return (
    <div className="space-y-4">
      {accounts.length === 0 ? (
        <EmptyState title="No bank accounts" description="Record the account salary is paid into." />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Holder</TableHead>
              <TableHead>Bank</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {accounts.map((a) => (
              <TableRow key={a.id}>
                <TableCell>
                  <div className="font-medium">{a.holder}</div>
                  {a.is_primary ? <Badge variant="info">Primary</Badge> : null}
                  {a.is_salary ? <Badge variant="muted">Salary</Badge> : null}
                </TableCell>
                <TableCell className="text-xs">
                  <div>{a.bank}</div>
                  {a.branch ? <div className="text-muted-foreground">{a.branch}</div> : null}
                  {a.ifsc ? <div className="font-mono text-muted-foreground">{a.ifsc}</div> : null}
                </TableCell>
                <TableCell className="font-mono text-xs">{a.masked}</TableCell>
                <TableCell className="text-xs">{humanise(a.type)}</TableCell>
                <TableCell>
                  <Badge variant={statusVariant(a.status)}>{humanise(a.status)}</Badge>
                  {a.remarks ? <div className="mt-1 text-xs text-muted-foreground">{a.remarks}</div> : null}
                </TableCell>
                <TableCell>
                  <div className="flex flex-col gap-2">
                    {can.reveal_bank ? <SensitiveRevealControl kind="BANK_ACCOUNT" id={a.id} label="Account number" /> : null}
                    {can.verify_bank ? <SensitiveReviewControl kind="BANK_ACCOUNT" id={a.id} status={a.status} /> : null}
                    {can.delete_bank ? <SensitiveDeleteControl kind="BANK_ACCOUNT" id={a.id} /> : null}
                    {can.edit_bank ? (
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          setAccountId(a.id);
                          setHolder(a.holder);
                          setBank(a.bank);
                          setBranch(a.branch ?? '');
                          setIfsc(a.ifsc ?? '');
                          setType(a.type);
                          setUpi(a.upi ?? '');
                          setPrimary(a.is_primary);
                          setSalary(a.is_salary);
                        }}
                      >
                        Edit
                      </Button>
                    ) : null}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {can.edit_bank ? (
        <div className="space-y-2 rounded-md border border-border p-3">
          <h4 className="text-sm font-semibold">{accountId === null ? 'Add a bank account' : 'Update the bank account'}</h4>
          <div className="grid gap-2 sm:grid-cols-3">
            <div className="space-y-1">
              <Label htmlFor="hr-bank-holder">Account holder</Label>
              <Input id="hr-bank-holder" value={holder} onChange={(e) => setHolder(e.target.value)} maxLength={200} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-bank-name">Bank</Label>
              <Input id="hr-bank-name" value={bank} onChange={(e) => setBank(e.target.value)} maxLength={200} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-bank-branch">Branch</Label>
              <Input id="hr-bank-branch" value={branch} onChange={(e) => setBranch(e.target.value)} maxLength={200} />
            </div>
          </div>
          <div className="grid gap-2 sm:grid-cols-3">
            <div className="space-y-1">
              <Label htmlFor="hr-bank-number">Account number</Label>
              <Input id="hr-bank-number" value={number} onChange={(e) => setNumber(e.target.value)} maxLength={18} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-bank-confirm">Repeat the account number</Label>
              <Input id="hr-bank-confirm" value={confirm} onChange={(e) => setConfirm(e.target.value)} maxLength={18} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-bank-ifsc">IFSC</Label>
              <Input id="hr-bank-ifsc" value={ifsc} onChange={(e) => setIfsc(e.target.value)} maxLength={11} placeholder="SBIN0001234" />
            </div>
          </div>
          <div className="grid gap-2 sm:grid-cols-3">
            <div className="space-y-1">
              <Label htmlFor="hr-bank-type">Account type</Label>
              <Select id="hr-bank-type" value={type} onChange={(e) => setType(e.target.value)}>
                {['SAVINGS', 'CURRENT', 'SALARY', 'NRE', 'NRO', 'OTHER'].map((t) => (
                  <option key={t} value={t}>
                    {humanise(t)}
                  </option>
                ))}
              </Select>
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-bank-upi">UPI id</Label>
              <Input id="hr-bank-upi" value={upi} onChange={(e) => setUpi(e.target.value)} maxLength={150} />
            </div>
            <div className="flex items-end gap-4 pb-1">
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={primary} onChange={(e) => setPrimary(e.target.checked)} />
                Primary
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={salary} onChange={(e) => setSalary(e.target.checked)} />
                Salary account
              </label>
            </div>
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex gap-2">
            <Button
              onClick={save}
              disabled={busy || holder.trim() === '' || bank.trim() === '' || ifsc.trim() === '' || (accountId === null && number.trim() === '')}
            >
              {busy ? 'Saving…' : 'Save the account'}
            </Button>
            {accountId !== null ? (
              <Button variant="ghost" onClick={reset} disabled={busy}>
                Cancel
              </Button>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------- competency */

export function CompetencyPanel({
  employeeId,
  summary,
  courses,
}: {
  employeeId: number;
  summary: CompetencySummary;
  courses: CourseOption[];
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [courseId, setCourseId] = useState('');
  const [level, setLevel] = useState('BEGINNER');
  const [validFrom, setValidFrom] = useState('');
  const [validTo, setValidTo] = useState('');

  async function save() {
    await run<void>(
      'emp_competency_save',
      {
        p_employee_id: employeeId,
        p_course_id: Number(courseId),
        p_level: level,
        p_valid_from: validFrom || null,
        p_valid_to: validTo || null,
      },
      { success: 'The competency has been saved.' },
    );
    setCourseId('');
    setValidFrom('');
    setValidTo('');
  }

  async function remove(id: number) {
    await run<void>('emp_competency_delete', { p_employee_id: employeeId, p_course_id: id }, { success: 'The competency has been removed.' });
  }

  return (
    <div className="space-y-4">
      {summary.rows.length === 0 ? (
        <EmptyState title="No competencies" description="Record the courses this employee is competent in." />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Course</TableHead>
              <TableHead>Level</TableHead>
              <TableHead>Valid</TableHead>
              <TableHead>State</TableHead>
              <TableHead>Remove</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {summary.rows.map((c) => (
              <TableRow key={c.course_id}>
                <TableCell>
                  <div className="font-medium">{c.course_title}</div>
                  <div className="font-mono text-xs text-muted-foreground">{c.course_code}</div>
                </TableCell>
                <TableCell className="text-xs">{humanise(c.level)}</TableCell>
                <TableCell className="text-xs">
                  <div>{formatDate(c.valid_from)}</div>
                  <div className="text-muted-foreground">to {formatDate(c.valid_to)}</div>
                </TableCell>
                <TableCell>
                  <Badge variant={c.active ? 'success' : 'muted'}>{c.active ? 'Active' : 'Expired'}</Badge>
                </TableCell>
                <TableCell>
                  {summary.can_delete ? (
                    <Button size="sm" variant="ghost" onClick={() => remove(c.course_id)} disabled={busy}>
                      Remove
                    </Button>
                  ) : (
                    <span className="text-xs text-muted-foreground">—</span>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {summary.can_edit ? (
        <div className="space-y-2 rounded-md border border-border p-3">
          <h4 className="text-sm font-semibold">Record a competency</h4>
          <div className="grid gap-2 sm:grid-cols-4">
            <div className="space-y-1">
              <Label htmlFor="hr-comp-course">Course</Label>
              {courses.length > 0 ? (
                <Select id="hr-comp-course" value={courseId} onChange={(e) => setCourseId(e.target.value)}>
                  <option value="">Choose a course</option>
                  {courses.map((c) => (
                    <option key={c.course_id} value={c.course_id}>
                      {c.course_code} — {c.course_title}
                    </option>
                  ))}
                </Select>
              ) : (
                <Input
                  id="hr-comp-course"
                  type="number"
                  value={courseId}
                  onChange={(e) => setCourseId(e.target.value)}
                  placeholder="Course id"
                />
              )}
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-comp-level">Level</Label>
              <Select id="hr-comp-level" value={level} onChange={(e) => setLevel(e.target.value)}>
                {['BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'EXPERT'].map((l) => (
                  <option key={l} value={l}>
                    {humanise(l)}
                  </option>
                ))}
              </Select>
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-comp-from">Valid from</Label>
              <Input id="hr-comp-from" type="date" value={validFrom} onChange={(e) => setValidFrom(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="hr-comp-to">Valid to</Label>
              <Input id="hr-comp-to" type="date" value={validTo} onChange={(e) => setValidTo(e.target.value)} />
            </div>
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <Button onClick={save} disabled={busy || courseId === ''}>
            {busy ? 'Saving…' : 'Save the competency'}
          </Button>
          {courses.length === 0 ? (
            <p className="text-xs text-muted-foreground">
              The course catalogue is not visible to you, so enter the course id directly.
            </p>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
