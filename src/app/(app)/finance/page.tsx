import Link from 'next/link';
import type { SupabaseClient } from '@supabase/supabase-js';
import { PageHeader, StatTile } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select } from '@/components/ui/input';
import { AccountPicker, AccountSummary, StudentAccountDesk } from '@/features/finance/accounts-client';
import { AssessmentPanel, PaymentPanel } from '@/features/finance/billing-client';
import { normaliseExtras, readAccountRows, readAssessmentItems } from '@/features/finance/data';
import { lookupOptions, tableOptions } from '@/features/finance/lookups';
import { BenefitPanel, HoldPanel, InstalmentPanel, RefundPanel } from '@/features/finance/operations-client';
import { FeeStructureDesk } from '@/features/finance/structures-client';
import type {
  AccountExtras,
  AccountInfo,
  AccountRow,
  AssessmentItemRow,
  AssessmentRow,
  HoldRow,
  PaymentRow,
  RefundRow,
  StructureRow,
} from '@/features/finance/types';
import { safeRpc, safeRows } from '@/features/shared/server-rpc';
import { formatMoney, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

/**
 * Fees & finance.
 *
 * The screen is a set of tabs over one student financial account. Every write
 * goes to a `fin_*` function; every read is either a `fin_*` function or a
 * table read whose RLS policy decides what the caller may see.
 */

const TABS = [
  { key: 'structures', label: 'Fee structures' },
  { key: 'accounts', label: 'Student accounts' },
  { key: 'assessments', label: 'Assessments' },
  { key: 'payments', label: 'Payments & receipts' },
  { key: 'holds', label: 'Holds' },
  { key: 'benefits', label: 'Benefits & concessions' },
  { key: 'refunds', label: 'Refunds' },
  { key: 'instalments', label: 'Instalments' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

/** The tabs that act on one student account. */
const ACCOUNT_TABS: readonly TabKey[] = [
  'assessments',
  'payments',
  'holds',
  'benefits',
  'refunds',
  'instalments',
];

const STRUCTURE_STATUSES = ['DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'SUPERSEDED'];
const ACCOUNT_STATUSES = ['ACTIVE', 'ON_HOLD', 'CLOSED'];

const ASSESSMENT_COLUMNS =
  'fee_assessment_id, assessment_number, student_account_id, academic_year_id, assessment_type, assessment_date, due_date, gross_amount, concession_amount, scholarship_amount, adjustment_amount, net_payable_amount, amount_paid, balance_amount, assessment_status';

const REFUND_COLUMNS =
  'refund_request_id, refund_request_number, student_account_id, payment_transaction_id, request_date, refund_reason, requested_amount, approved_amount, request_status';

function resolveTab(value: string | undefined): TabKey {
  const found = TABS.find((t) => t.key === value);
  return found ? found.key : 'structures';
}

function isAccountTab(tab: TabKey): boolean {
  return ACCOUNT_TABS.includes(tab);
}

export default async function FinancePage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string; q?: string; status?: string; account?: string }>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;

  const tab = resolveTab(sp.tab);
  const q = (sp.q ?? '').trim();
  const status = (sp.status ?? '').trim();
  const accountId = Number(sp.account);
  const hasAccount = Number.isInteger(accountId) && accountId > 0;

  const tabHref = (key: TabKey) => {
    const params = new URLSearchParams();
    params.set('tab', key);
    if (hasAccount && isAccountTab(key)) params.set('account', String(accountId));
    return `/finance?${params.toString()}`;
  };

  return (
    <>
      <PageHeader
        title="Fees & finance"
        description="Fee structures, student accounts, assessments, payments and the operations that run on them. Every move is recorded by the database."
      />

      <nav aria-label="Finance sections" className="mb-4 flex flex-wrap gap-1 border-b border-border">
        {TABS.map((t) => {
          const active = t.key === tab;
          return (
            <Link
              key={t.key}
              href={tabHref(t.key)}
              aria-current={active ? 'page' : undefined}
              className={
                active
                  ? 'border-b-2 border-primary px-3 py-2 text-sm font-medium text-foreground'
                  : 'border-b-2 border-transparent px-3 py-2 text-sm font-medium text-muted-foreground hover:text-foreground'
              }
            >
              {t.label}
            </Link>
          );
        })}
      </nav>

      {tab === 'structures' ? <StructuresTab supabase={supabase} q={q} status={status} /> : null}
      {tab === 'accounts' ? <AccountsTab supabase={supabase} q={q} status={status} /> : null}
      {isAccountTab(tab) ? (
        <AccountTab supabase={supabase} tab={tab} accountId={hasAccount ? accountId : null} q={q} status={status} />
      ) : null}
    </>
  );
}

/* ------------------------------------------------------------------ */
/* Fee structures                                                      */
/* ------------------------------------------------------------------ */

async function StructuresTab({
  supabase,
  q,
  status,
}: {
  supabase: SupabaseClient;
  q: string;
  status: string;
}) {
  const [structures, institutions, campuses, programmes, years, categories, feeTypes, semesters, terms, lateFeeRules] =
    await Promise.all([
      safeRows<StructureRow>(supabase, 'fin_structure_list', {
        p_search: q || null,
        p_status: status || null,
        p_limit: 50,
      }),
      tableOptions(supabase, {
        table: 'institution',
        idColumn: 'institution_id',
        labelColumn: 'institution_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      tableOptions(supabase, {
        table: 'campus',
        idColumn: 'campus_id',
        labelColumn: 'campus_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      tableOptions(supabase, {
        table: 'programme',
        idColumn: 'programme_id',
        labelColumn: 'programme_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      tableOptions(supabase, {
        table: 'academic_year',
        idColumn: 'academic_year_id',
        labelColumn: 'year_code',
      }),
      tableOptions(supabase, {
        table: 'admission_category',
        idColumn: 'admission_category_id',
        labelColumn: 'category_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      lookupOptions(supabase, 'fee_type'),
      tableOptions(supabase, {
        table: 'semester',
        idColumn: 'semester_id',
        labelColumn: 'semester_name',
      }),
      tableOptions(supabase, {
        table: 'academic_term',
        idColumn: 'academic_term_id',
        labelColumn: 'term_name',
      }),
      lookupOptions(supabase, 'late_fee_rule'),
    ]);

  const rows = structures.rows;
  const lookupErrors = [
    institutions.error,
    campuses.error,
    programmes.error,
    years.error,
    categories.error,
    feeTypes.error,
    semesters.error,
    terms.error,
    lateFeeRules.error,
  ].filter((e): e is string => Boolean(e));

  return (
    <div className="space-y-4">
      <FilterBar tab="structures" q={q} status={status} statuses={STRUCTURE_STATUSES} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Structures" value={formatNumber(rows.length)} />
        <StatTile
          label="Approved"
          value={formatNumber(rows.filter((r) => r.approval_status === 'APPROVED').length)}
          tone="success"
        />
        <StatTile
          label="Awaiting approval"
          value={formatNumber(rows.filter((r) => r.approval_status === 'SUBMITTED').length)}
          tone="warning"
        />
        <StatTile
          label="Priced total"
          value={formatMoney(rows.reduce((sum, r) => sum + Number(r.total_amount ?? 0), 0))}
        />
      </div>

      {structures.error ? <ErrorPanel message={`Fee structures could not be read: ${structures.error}`} /> : null}
      {lookupErrors.length > 0 ? (
        <ErrorPanel message={`Some lookup lists could not be read: ${lookupErrors.join('; ')}`} />
      ) : null}

      <FeeStructureDesk
        structures={rows}
        institutions={institutions.options}
        campuses={campuses.options}
        programmes={programmes.options}
        years={years.options}
        categories={categories.options}
        feeTypes={feeTypes.options}
        semesters={semesters.options}
        terms={terms.options}
        lateFeeRules={lateFeeRules.options}
      />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Student accounts                                                    */
/* ------------------------------------------------------------------ */

async function AccountsTab({ supabase, q, status }: { supabase: SupabaseClient; q: string; status: string }) {
  const accounts = await safeRows<AccountRow>(supabase, 'fin_accounts', {
    p_search: q || null,
    p_status: status || null,
    p_limit: 50,
  });
  const rows = accounts.rows;

  return (
    <div className="space-y-4">
      <FilterBar tab="accounts" q={q} status={status} statuses={ACCOUNT_STATUSES} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Accounts" value={formatNumber(rows.length)} />
        <StatTile label="Payable" value={formatMoney(rows.reduce((s, r) => s + Number(r.total_payable ?? 0), 0))} />
        <StatTile
          label="Paid"
          value={formatMoney(rows.reduce((s, r) => s + Number(r.total_paid ?? 0), 0))}
          tone="success"
        />
        <StatTile
          label="Outstanding"
          value={formatMoney(rows.reduce((s, r) => s + Number(r.total_balance ?? 0), 0))}
          tone={rows.some((r) => Number(r.total_balance ?? 0) > 0) ? 'warning' : 'default'}
        />
      </div>

      {accounts.error ? <ErrorPanel message={`Student accounts could not be read: ${accounts.error}`} /> : null}

      <StudentAccountDesk accounts={rows} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Account-scoped tabs                                                 */
/* ------------------------------------------------------------------ */

async function AccountTab({
  supabase,
  tab,
  accountId,
  q,
  status,
}: {
  supabase: SupabaseClient;
  tab: TabKey;
  accountId: number | null;
  q: string;
  status: string;
}) {
  const accounts = await safeRows<AccountRow>(supabase, 'fin_accounts', {
    p_search: q || null,
    p_status: status || null,
    p_limit: 50,
  });

  if (accountId === null) {
    return (
      <div className="space-y-4">
        <FilterBar tab={tab} q={q} status={status} statuses={ACCOUNT_STATUSES} />
        {accounts.error ? <ErrorPanel message={`Student accounts could not be read: ${accounts.error}`} /> : null}
        <AccountPicker accounts={accounts.rows} tab={tab} />
      </div>
    );
  }

  const [info, extras] = await Promise.all([
    safeRows<AccountInfo>(supabase, 'fin_account_info', { p_student_account_id: accountId }),
    safeRpc<Record<string, unknown>>(supabase, 'fin_account_extras', { p_student_account_id: accountId }),
  ]);

  const account = info.rows[0] ?? null;

  if (!account) {
    return (
      <div className="space-y-4">
        {info.error ? <ErrorPanel message={`The account could not be read: ${info.error}`} /> : null}
        <EmptyState
          title="Account not available"
          description="This account is not visible to you, or it no longer exists. Choose another account below."
        />
        <AccountPicker accounts={accounts.rows} tab={tab} />
      </div>
    );
  }

  const extrasPayload = normaliseExtras(extras.data);

  return (
    <div className="space-y-4">
      <AccountSummary account={account} />
      {extras.error ? <ErrorPanel message={`Some account sections could not be read: ${extras.error}`} /> : null}
      {tab === 'assessments' ? <Assessments supabase={supabase} account={account} /> : null}
      {tab === 'payments' ? <Payments supabase={supabase} account={account} /> : null}
      {tab === 'holds' ? <Holds supabase={supabase} account={account} /> : null}
      {tab === 'benefits' ? <Benefits supabase={supabase} account={account} extras={extrasPayload} /> : null}
      {tab === 'refunds' ? <Refunds supabase={supabase} account={account} /> : null}
      {tab === 'instalments' ? <Instalments supabase={supabase} account={account} extras={extrasPayload} /> : null}
    </div>
  );
}

async function Assessments({ supabase, account }: { supabase: SupabaseClient; account: AccountInfo }) {
  const [assessments, feeTypes, years, lateFeeRules] = await Promise.all([
    readAccountRows<AssessmentRow>(supabase, 'student_fee_assessment', ASSESSMENT_COLUMNS, account.student_account_id, {
      order: { column: 'assessment_date', ascending: false },
      limit: 100,
    }),
    lookupOptions(supabase, 'fee_type'),
    tableOptions(supabase, {
      table: 'academic_year',
      idColumn: 'academic_year_id',
      labelColumn: 'year_code',
    }),
    lookupOptions(supabase, 'late_fee_rule'),
  ]);

  const items = await readAssessmentItems<AssessmentItemRow>(
    supabase,
    assessments.rows.map((a) => Number(a.fee_assessment_id)),
  );

  return (
    <AssessmentPanel
      account={account}
      assessments={assessments.rows}
      items={items.rows}
      feeTypes={feeTypes.options}
      years={years.options}
      lateFeeRules={lateFeeRules.options}
      readError={assessments.error ?? items.error ?? feeTypes.error ?? years.error ?? lateFeeRules.error}
    />
  );
}

async function Payments({ supabase, account }: { supabase: SupabaseClient; account: AccountInfo }) {
  const [payments, paymentModes, assessments] = await Promise.all([
    safeRows<PaymentRow>(supabase, 'fin_payment_receipts', { p_student_account_id: account.student_account_id }),
    lookupOptions(supabase, 'payment_mode'),
    readAccountRows<AssessmentRow>(supabase, 'student_fee_assessment', ASSESSMENT_COLUMNS, account.student_account_id, {
      order: { column: 'assessment_date', ascending: false },
      limit: 100,
    }),
  ]);

  const items = await readAssessmentItems<AssessmentItemRow>(
    supabase,
    assessments.rows.map((a) => Number(a.fee_assessment_id)),
  );

  return (
    <PaymentPanel
      account={account}
      payments={payments.rows}
      items={items.rows}
      paymentModes={paymentModes.options}
      readError={payments.error ?? paymentModes.error ?? assessments.error ?? items.error}
    />
  );
}

async function Holds({ supabase, account }: { supabase: SupabaseClient; account: AccountInfo }) {
  const holds = await safeRows<HoldRow>(supabase, 'fin_holds', { p_student_account_id: account.student_account_id });
  return <HoldPanel account={account} holds={holds.rows} readError={holds.error} />;
}

async function Benefits({
  supabase,
  account,
  extras,
}: {
  supabase: SupabaseClient;
  account: AccountInfo;
  extras: AccountExtras;
}) {
  const [concessionTypes, scholarshipSchemes, years, assessments] = await Promise.all([
    lookupOptions(supabase, 'concession_type'),
    lookupOptions(supabase, 'scholarship_scheme'),
    tableOptions(supabase, {
      table: 'academic_year',
      idColumn: 'academic_year_id',
      labelColumn: 'year_code',
    }),
    readAccountRows<AssessmentRow>(supabase, 'student_fee_assessment', ASSESSMENT_COLUMNS, account.student_account_id, {
      order: { column: 'assessment_date', ascending: false },
      limit: 100,
    }),
  ]);

  const items = await readAssessmentItems<AssessmentItemRow>(
    supabase,
    assessments.rows.map((a) => Number(a.fee_assessment_id)),
  );

  return (
    <BenefitPanel
      account={account}
      extras={extras}
      items={items.rows}
      concessionTypes={concessionTypes.options}
      scholarshipSchemes={scholarshipSchemes.options}
      years={years.options}
      readError={concessionTypes.error ?? scholarshipSchemes.error ?? years.error ?? assessments.error ?? items.error}
    />
  );
}

async function Refunds({ supabase, account }: { supabase: SupabaseClient; account: AccountInfo }) {
  const [refunds, payments, paymentModes] = await Promise.all([
    readAccountRows<RefundRow>(supabase, 'refund_request', REFUND_COLUMNS, account.student_account_id, {
      order: { column: 'request_date', ascending: false },
      limit: 100,
    }),
    safeRows<PaymentRow>(supabase, 'fin_payment_receipts', { p_student_account_id: account.student_account_id }),
    lookupOptions(supabase, 'payment_mode'),
  ]);

  return (
    <RefundPanel
      account={account}
      refunds={refunds.rows}
      payments={payments.rows}
      paymentModes={paymentModes.options}
      readError={refunds.error ?? payments.error ?? paymentModes.error}
    />
  );
}

async function Instalments({
  supabase,
  account,
  extras,
}: {
  supabase: SupabaseClient;
  account: AccountInfo;
  extras: AccountExtras;
}) {
  const [plans, assessments] = await Promise.all([
    lookupOptions(supabase, 'installment_plan'),
    readAccountRows<AssessmentRow>(supabase, 'student_fee_assessment', ASSESSMENT_COLUMNS, account.student_account_id, {
      order: { column: 'assessment_date', ascending: false },
      limit: 100,
    }),
  ]);

  return (
    <InstalmentPanel
      extras={extras}
      assessments={assessments.rows}
      plans={plans.options}
      readError={plans.error ?? assessments.error}
    />
  );
}

/* ------------------------------------------------------------------ */
/* Shared bits                                                         */
/* ------------------------------------------------------------------ */

/** The search and status filter for the list tabs. */
function FilterBar({
  tab,
  q,
  status,
  statuses,
}: {
  tab: string;
  q: string;
  status: string;
  statuses: string[];
}) {
  return (
    <form action="/finance" method="get" role="search" className="flex flex-wrap items-end gap-3">
      <input type="hidden" name="tab" value={tab} />
      <div className="min-w-[14rem] flex-1">
        <Label htmlFor="fee-q" className="mb-1 block">
          Search
        </Label>
        <Input id="fee-q" name="q" type="search" defaultValue={q} maxLength={120} placeholder="Name, number or code" />
      </div>
      <div className="min-w-[10rem]">
        <Label htmlFor="fee-status" className="mb-1 block">
          Status
        </Label>
        <Select id="fee-status" name="status" defaultValue={status}>
          <option value="">All</option>
          {statuses.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
      </div>
      <Button type="submit" variant="outline">
        Apply
      </Button>
      {q || status ? (
        <Link href={`/finance?tab=${tab}`} className="pb-2 text-sm font-medium text-primary underline-offset-4 hover:underline">
          Clear
        </Link>
      ) : null}
    </form>
  );
}
