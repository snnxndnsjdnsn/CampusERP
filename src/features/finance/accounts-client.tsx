'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useRpcAction } from '@/features/shared/client-rpc';
import type { AccountInfo, AccountRow } from './types';
import { Field, FormError, Money, ReadError } from './ui';

/**
 * Student financial accounts.
 *
 * `fin_accounts` decides which accounts the caller may see; `fin_open_account`
 * creates the one the fee office works with. Nothing is filtered in the browser.
 */

export function StudentAccountDesk({ accounts }: { accounts: AccountRow[] }) {
  const { run, busy, error } = useRpcAction();
  const [studentNumber, setStudentNumber] = useState('');
  const [opened, setOpened] = useState<number | null>(null);

  async function openAccount(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const number = studentNumber.trim();
    if (!number) return;
    const result = await run<number>('fin_open_account', { p_student_number: number });
    if (result.ok) {
      setOpened(result.data);
      setStudentNumber('');
    }
  }

  return (
    <div className="space-y-4">
      <form onSubmit={openAccount} className="rounded-lg border border-border bg-card p-4" noValidate>
        <h3 className="text-sm font-semibold">Open a financial account</h3>
        <p className="mt-1 text-sm text-muted-foreground">
          The account number is derived from the student number. Opening an account twice returns the same one.
        </p>
        <div className="mt-3 flex flex-wrap items-end gap-2">
          <div className="min-w-[14rem] flex-1">
            <Field label="Student number" htmlFor="open_account_student_number">
              <Input
                id="open_account_student_number"
                value={studentNumber}
                onChange={(e) => setStudentNumber(e.target.value)}
                required
                maxLength={30}
                placeholder="STU-2026-0001"
              />
            </Field>
          </div>
          <Button type="submit" disabled={busy}>
            {busy ? 'Opening…' : 'Open account'}
          </Button>
        </div>
        <div className="mt-3 space-y-2">
          <FormError message={error} />
          {opened !== null ? (
            <p className="text-sm text-emerald-700">
              Account #{opened} is ready.{' '}
              <Link className="font-medium underline underline-offset-4" href={`/finance?tab=assessments&account=${opened}`}>
                Open its assessments
              </Link>
            </p>
          ) : null}
        </div>
      </form>

      <ReadError message={null} />

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Student</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Account</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Payable</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Paid</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Balance</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {accounts.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No student accounts are visible to you.
                </td>
              </tr>
            ) : (
              accounts.map((a) => (
                <tr key={a.student_account_id} className="border-b last:border-0 hover:bg-muted/40">
                  <td className="px-3 py-2">
                    <div className="font-medium">{a.display_name}</div>
                    <div className="text-xs text-muted-foreground">{a.student_number}</div>
                  </td>
                  <td className="px-3 py-2">{a.account_number}</td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(a.account_status)}>{a.account_status}</Badge>
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={a.total_payable} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={a.total_paid} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={a.total_balance} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Link
                      href={`/finance?tab=assessments&account=${a.student_account_id}`}
                      className="text-sm font-medium text-primary underline-offset-4 hover:underline"
                    >
                      Open
                    </Link>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/** The account chooser shown when an account-scoped tab has no account selected. */
export function AccountPicker({ accounts, tab }: { accounts: AccountRow[]; tab: string }) {
  if (accounts.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
        No student accounts are visible to you, so there is nothing to show on this tab.
      </div>
    );
  }

  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <h3 className="text-sm font-semibold">Choose a student account</h3>
      <p className="mt-1 text-sm text-muted-foreground">Every action on this tab applies to the account you pick.</p>
      <ul className="mt-3 divide-y divide-border">
        {accounts.map((a) => (
          <li key={a.student_account_id} className="flex flex-wrap items-center justify-between gap-2 py-2">
            <div>
              <div className="font-medium">{a.display_name}</div>
              <div className="text-xs text-muted-foreground">
                {a.student_number} · {a.account_number}
              </div>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-sm tabular-nums text-muted-foreground">
                <Money value={a.total_balance} />
              </span>
              <Link
                href={`/finance?tab=${tab}&account=${a.student_account_id}`}
                className="text-sm font-medium text-primary underline-offset-4 hover:underline"
              >
                Open
              </Link>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** The account header shown above every account-scoped tab. */
export function AccountSummary({ account }: { account: AccountInfo }) {
  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold">{account.display_name}</h3>
          <p className="mt-1 text-sm text-muted-foreground">
            {account.student_number} · {account.account_number}
          </p>
        </div>
        <Badge variant={statusVariant(account.account_status)}>{account.account_status}</Badge>
      </div>
      <dl className="mt-3 grid gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <Summary label="Opening balance" value={<Money value={account.opening_balance} />} />
        <Summary label="Credit" value={<Money value={account.credit_balance} />} />
        <Summary label="Total payable" value={<Money value={account.total_payable} />} />
        <Summary label="Total paid" value={<Money value={account.total_paid} />} />
        <Summary label="Balance" value={<Money value={account.total_balance} />} />
      </dl>
    </div>
  );
}

function Summary({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-1 text-sm font-semibold tabular-nums">{value}</dd>
    </div>
  );
}
