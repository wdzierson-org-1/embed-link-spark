import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { format, formatDistanceToNow } from 'date-fns';
import { ArrowDown, ArrowUp, Loader2, Search } from 'lucide-react';
import HeaderSection from '@/components/HeaderSection';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { useAuth } from '@/hooks/useAuth';
import { useIsAdmin } from '@/hooks/useIsAdmin';
import { fetchAdminUsers } from '@/utils/adminApi';
import {
  describeTypes,
  filterRows,
  isTestAccount,
  loginsPerDay,
  memberName,
  sortRows,
  summarizeMembers,
  type AdminUserRow,
  type SortDir,
  type SortKey,
} from '@/utils/adminStats';

// Temporary admin dashboard — who is signing in and what they save
// (spec: docs/superpowers/specs/2026-09-08-admin-dashboard-design.md).
// Reachable only through the avatar menu for accounts in admin_users; the
// server refuses everyone else, this page just sends them home.

const relative = (iso: string | null): string =>
  iso ? formatDistanceToNow(new Date(iso), { addSuffix: true }) : 'Never';
const absolute = (iso: string | null): string | undefined =>
  iso ? format(new Date(iso), 'PPpp') : undefined;

type Column = { key: SortKey; label: string; numeric?: boolean; defaultDir: SortDir };

const COLUMNS: Column[] = [
  { key: 'name', label: 'Member', defaultDir: 'asc' },
  { key: 'email', label: 'Email', defaultDir: 'asc' },
  { key: 'created_at', label: 'Joined', defaultDir: 'desc' },
  { key: 'last_sign_in_at', label: 'Last login', defaultDir: 'desc' },
  { key: 'last_active_at', label: 'Last active', defaultDir: 'desc' },
  { key: 'total_logins', label: 'Logins', numeric: true, defaultDir: 'desc' },
  { key: 'per_day', label: 'Per day', numeric: true, defaultDir: 'desc' },
  { key: 'active_days', label: 'Active days', numeric: true, defaultDir: 'desc' },
  { key: 'item_count', label: 'Items', numeric: true, defaultDir: 'desc' },
  { key: 'last_item_at', label: 'Last saved', defaultDir: 'desc' },
];

const Tile = ({ id, label, value, note }: { id: string; label: string; value: number; note?: string }) => (
  <div className="px-5 py-4">
    <div
      data-testid={`tile-${id}-value`}
      className="text-[28px] font-semibold leading-none tracking-[-0.02em] text-[#22262f] tabular-nums"
    >
      {value.toLocaleString()}
    </div>
    <div className="mt-2 text-[13.5px] text-[#646b76]">{label}</div>
    {note && <div className="mt-0.5 text-xs text-[#959ba6]">{note}</div>}
  </div>
);

const When = ({ iso }: { iso: string | null }) => (
  <span title={absolute(iso)} className={iso ? undefined : 'text-[#959ba6]'}>
    {relative(iso)}
  </span>
);

const Admin = () => {
  const { user, loading: authLoading } = useAuth();
  const { isAdmin, loading: adminLoading } = useIsAdmin();
  const navigate = useNavigate();

  const [rows, setRows] = useState<AdminUserRow[] | null>(null);
  // One clock per load so every relative time and rate agrees with itself
  const [now, setNow] = useState(() => new Date());
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [hideTestAccounts, setHideTestAccounts] = useState(true);
  const [sort, setSort] = useState<{ key: SortKey; dir: SortDir }>({ key: 'last_active_at', dir: 'desc' });

  useEffect(() => {
    if (!authLoading && !user) navigate('/auth');
  }, [authLoading, user, navigate]);

  const allowed = !authLoading && !!user && !adminLoading && isAdmin;
  useEffect(() => {
    if (!authLoading && user && !adminLoading && !isAdmin) navigate('/home');
  }, [authLoading, user, adminLoading, isAdmin, navigate]);

  useEffect(() => {
    if (!allowed) return;
    let cancelled = false;
    fetchAdminUsers()
      .then((data) => {
        if (cancelled) return;
        setNow(new Date());
        setRows(data);
      })
      .catch((err: Error) => {
        if (!cancelled) setError(err.message);
      });
    return () => {
      cancelled = true;
    };
  }, [allowed]);

  const counted = useMemo(
    () => (rows ?? []).filter((row) => !hideTestAccounts || !isTestAccount(row.email)),
    [rows, hideTestAccounts]
  );
  const summary = useMemo(() => summarizeMembers(counted, now), [counted, now]);
  const visible = useMemo(
    () => sortRows(filterRows(rows ?? [], { query, hideTestAccounts }), sort.key, sort.dir, now),
    [rows, query, hideTestAccounts, sort, now]
  );

  const toggleSort = (column: Column) =>
    setSort((current) =>
      current.key === column.key
        ? { key: column.key, dir: current.dir === 'asc' ? 'desc' : 'asc' }
        : { key: column.key, dir: column.defaultDir }
    );

  if (!user) return null;

  const anonymousNote =
    summary.anonymous > 0
      ? `${summary.anonymous} anonymous try-it ${summary.anonymous === 1 ? 'session' : 'sessions'} not listed`
      : undefined;

  return (
    <div className="min-h-screen bg-white">
      <HeaderSection user={user} />

      <div className="container mx-auto max-w-7xl px-4 py-8">
        <div className="mb-6">
          <h1 className="text-[32px] font-semibold leading-[1.12] tracking-[-0.022em] text-[#22262f]">Members</h1>
          <p className="mt-2 max-w-xl text-sm text-[#646b76]">
            Who is signing in and what they are saving, while the first members get set up. Internal only;
            this view is switched off once there are enough members.
          </p>
        </div>

        {error ? (
          <div role="alert" className="rounded-2xl border border-black/[0.07] bg-[rgba(20,22,30,0.03)] px-5 py-4 text-sm">
            <p className="font-medium text-[#22262f]">Couldn't load members</p>
            <p className="mt-1 text-[#646b76]">{error}</p>
          </div>
        ) : rows === null ? (
          <div className="flex items-center gap-2 py-12 text-sm text-[#959ba6]">
            <Loader2 className="h-4 w-4 animate-spin" />
            Loading members
          </div>
        ) : (
          <>
            <div className="mb-8 grid grid-cols-2 border-y border-black/[0.07] md:grid-cols-4 md:divide-x md:divide-black/[0.07]">
              <Tile id="members" label="Members" value={summary.members} note={anonymousNote} />
              <Tile id="active" label="Active in the last 7 days" value={summary.activeLast7d} />
              <Tile id="items" label="Items saved" value={summary.items} />
              <Tile id="items-week" label="Saved in the last 7 days" value={summary.itemsLast7d} />
            </div>

            <div className="mb-3 flex flex-wrap items-center gap-x-6 gap-y-3">
              <label className="relative block w-full max-w-xs">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#959ba6]" />
                <input
                  type="search"
                  aria-label="Search members"
                  placeholder="Search members"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  className="h-9 w-full rounded-xl border border-black/[0.07] bg-white pl-9 pr-3 text-sm text-[#22262f] placeholder:text-[#959ba6] focus:outline-none focus:ring-2 focus:ring-[#b6a8ef]"
                />
              </label>
              <label className="inline-flex cursor-pointer items-center gap-2 text-sm text-[#646b76]">
                <input
                  type="checkbox"
                  checked={hideTestAccounts}
                  onChange={(e) => setHideTestAccounts(e.target.checked)}
                  className="h-4 w-4 accent-[#6d5bd0]"
                />
                Hide test accounts
              </label>
              <span className="ml-auto text-xs text-[#959ba6]">
                {visible.length} {visible.length === 1 ? 'member' : 'members'} shown
              </span>
            </div>

            <Table>
              <TableHeader>
                <TableRow className="border-black/[0.07] hover:bg-transparent">
                  {COLUMNS.map((column) => {
                    const active = sort.key === column.key;
                    const Arrow = sort.dir === 'asc' ? ArrowUp : ArrowDown;
                    return (
                      <TableHead
                        key={column.key}
                        aria-sort={active ? (sort.dir === 'asc' ? 'ascending' : 'descending') : 'none'}
                        className={`h-10 whitespace-nowrap px-3 ${column.numeric ? 'text-right' : ''}`}
                      >
                        <button
                          type="button"
                          onClick={() => toggleSort(column)}
                          className={`inline-flex items-center gap-1 text-[11px] font-semibold uppercase tracking-[0.11em] ${
                            active ? 'text-[#22262f]' : 'text-[#959ba6] hover:text-[#646b76]'
                          }`}
                        >
                          {column.label}
                          {active && <Arrow className="h-3 w-3" aria-hidden />}
                        </button>
                      </TableHead>
                    );
                  })}
                </TableRow>
              </TableHeader>
              <TableBody>
                {visible.length === 0 ? (
                  <TableRow className="border-black/[0.07] hover:bg-transparent">
                    <TableCell colSpan={COLUMNS.length} className="py-10 text-center text-sm text-[#959ba6]">
                      No members match.
                    </TableCell>
                  </TableRow>
                ) : (
                  visible.map((row) => (
                    <TableRow key={row.user_id} className="border-black/[0.07] text-[#22262f] hover:bg-[rgba(20,22,30,0.02)]">
                      <TableCell className="px-3 py-3 align-top">
                        <Link to={`/admin/users/${row.user_id}`} className="font-medium text-[#6d5bd0] hover:underline">
                          {memberName(row)}
                        </Link>
                        {row.username && <div className="text-xs text-[#959ba6]">@{row.username}</div>}
                      </TableCell>
                      <TableCell className="px-3 py-3 align-top">
                        {row.email ? (
                          <Link to={`/admin/users/${row.user_id}`} className="text-[#6d5bd0] hover:underline">
                            {row.email}
                          </Link>
                        ) : (
                          <span className="text-[#959ba6]">No email</span>
                        )}
                      </TableCell>
                      <TableCell className="whitespace-nowrap px-3 py-3 align-top"><When iso={row.created_at} /></TableCell>
                      <TableCell className="whitespace-nowrap px-3 py-3 align-top"><When iso={row.last_sign_in_at} /></TableCell>
                      <TableCell className="whitespace-nowrap px-3 py-3 align-top"><When iso={row.last_active_at} /></TableCell>
                      <TableCell className="px-3 py-3 text-right align-top tabular-nums">{row.total_logins.toLocaleString()}</TableCell>
                      <TableCell className="px-3 py-3 text-right align-top tabular-nums">{loginsPerDay(row, now).toFixed(1)}</TableCell>
                      <TableCell className="px-3 py-3 text-right align-top tabular-nums">{row.active_days.toLocaleString()}</TableCell>
                      <TableCell className="px-3 py-3 text-right align-top tabular-nums">
                        {row.item_count.toLocaleString()}
                        {row.item_count > 0 && (
                          <div className="whitespace-nowrap text-xs font-normal text-[#959ba6]">{describeTypes(row.items_by_type)}</div>
                        )}
                      </TableCell>
                      <TableCell className="whitespace-nowrap px-3 py-3 align-top"><When iso={row.last_item_at} /></TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </>
        )}
      </div>
    </div>
  );
};

export default Admin;
