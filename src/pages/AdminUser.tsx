import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { format } from 'date-fns';
import { ArrowLeft, Loader2, Search } from 'lucide-react';
import HeaderSection from '@/components/HeaderSection';
import ContentGrid, { type ContentTypeFilter } from '@/components/ContentGrid';
import { MetaChip } from '@/components/cards/CardBits';
import { NowProvider } from '@/hooks/useNow';
import { useAuth } from '@/hooks/useAuth';
import { useIsAdmin } from '@/hooks/useIsAdmin';
import { fetchAdminLibrary, type AdminLibrary } from '@/utils/adminApi';
import { typeLabel } from '@/utils/adminStats';

// Temporary admin dashboard — one member's library, as their grid shows it
// (spec: docs/superpowers/specs/2026-09-08-admin-dashboard-design.md).
// Strictly read-only: the grid runs in public-view mode, so there is no card
// menu, no edit sheet, no reminders, no delete — nothing here can write to
// the member's data.

const TYPE_PILLS: { value: ContentTypeFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'link', label: 'Links' },
  { value: 'note', label: 'Notes' },
  { value: 'doc', label: 'Docs' },
  { value: 'media', label: 'Media' },
];

const noop = () => {};

const countByType = (items: { type?: unknown }[]): [string, number][] => {
  const counts = new Map<string, number>();
  for (const item of items) {
    const type = typeof item.type === 'string' ? item.type : 'unknown';
    counts.set(type, (counts.get(type) ?? 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
};

const AdminUser = () => {
  const { userId } = useParams<{ userId: string }>();
  const { user, loading: authLoading } = useAuth();
  const { isAdmin, loading: adminLoading } = useIsAdmin();
  const navigate = useNavigate();

  const [library, setLibrary] = useState<AdminLibrary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<ContentTypeFilter>('all');

  useEffect(() => {
    if (!authLoading && !user) navigate('/auth');
  }, [authLoading, user, navigate]);

  const allowed = !authLoading && !!user && !adminLoading && isAdmin;
  useEffect(() => {
    if (!authLoading && user && !adminLoading && !isAdmin) navigate('/home');
  }, [authLoading, user, adminLoading, isAdmin, navigate]);

  useEffect(() => {
    if (!allowed || !userId) return;
    let cancelled = false;
    setLibrary(null);
    setError(null);
    fetchAdminLibrary(userId)
      .then((data) => {
        if (!cancelled) setLibrary(data);
      })
      .catch((err: Error) => {
        if (!cancelled) setError(err.message);
      });
    return () => {
      cancelled = true;
    };
  }, [allowed, userId]);

  const byType = useMemo(() => countByType(library?.items ?? []), [library]);

  if (!user) return null;

  const member = library?.user;
  const name = member?.display_name?.trim() || member?.username?.trim() || member?.email?.split('@')[0] || 'Anonymous';
  const itemCount = library?.items.length ?? 0;

  return (
    <div className="min-h-screen bg-white">
      <HeaderSection user={user} />

      <div className="container mx-auto max-w-7xl px-4 py-8">
        <Link
          to="/admin"
          className="mb-6 inline-flex items-center gap-1.5 text-sm text-[#646b76] transition-colors hover:text-[#22262f]"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Members
        </Link>

        {error ? (
          <div role="alert" className="rounded-2xl border border-black/[0.07] bg-[rgba(20,22,30,0.03)] px-5 py-4 text-sm">
            <p className="font-medium text-[#22262f]">Couldn't load this library</p>
            <p className="mt-1 text-[#646b76]">{error}</p>
          </div>
        ) : !library || !member ? (
          <div className="flex items-center gap-2 py-12 text-sm text-[#959ba6]">
            <Loader2 className="h-4 w-4 animate-spin" />
            Loading library
          </div>
        ) : (
          <>
            <div className="mb-6 flex items-start gap-4">
              <div className="flex h-12 w-12 flex-none items-center justify-center rounded-full bg-purple-400 text-lg font-medium text-white">
                {name.charAt(0).toUpperCase()}
              </div>
              <div className="min-w-0 flex-1">
                <h1 className="text-[28px] font-medium leading-[1.2] tracking-[-0.02em] text-[#22262f]">{name}</h1>
                <div className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-[#646b76]">
                  {member.email && <span>{member.email}</span>}
                  {member.username && <span>@{member.username}</span>}
                  <span>Joined {format(new Date(member.created_at), 'PP')}</span>
                  <span>
                    {itemCount} {itemCount === 1 ? 'item' : 'items'}
                  </span>
                </div>
                {byType.length > 0 && (
                  <div className="mt-3 flex flex-wrap gap-1.5">
                    {byType.map(([type, count]) => (
                      <MetaChip key={type}>{`${count} ${typeLabel(type, count)}`}</MetaChip>
                    ))}
                  </div>
                )}
              </div>
            </div>

            {itemCount === 0 ? (
              <p className="py-12 text-center text-sm text-[#959ba6]">Nothing saved yet.</p>
            ) : (
              <>
                <div className="mb-4 flex flex-wrap items-center gap-x-6 gap-y-3">
                  <label className="relative block w-full max-w-xs">
                    <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#959ba6]" />
                    <input
                      type="search"
                      aria-label="Search this library"
                      placeholder="Search this library"
                      value={query}
                      onChange={(e) => setQuery(e.target.value)}
                      className="h-9 w-full rounded-xl border border-black/[0.07] bg-white pl-9 pr-3 text-sm text-[#22262f] placeholder:text-[#959ba6] focus:outline-none focus:ring-2 focus:ring-[#b6a8ef]"
                    />
                  </label>
                  <div role="group" aria-label="Type" className="flex flex-wrap gap-1.5">
                    {TYPE_PILLS.map((pill) => {
                      const active = typeFilter === pill.value;
                      return (
                        <button
                          key={pill.value}
                          type="button"
                          aria-pressed={active}
                          onClick={() => setTypeFilter(pill.value)}
                          className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                            active
                              ? 'bg-[#6d5bd0] text-white'
                              : 'bg-[rgba(20,22,30,0.05)] text-[#646b76] hover:text-[#22262f]'
                          }`}
                        >
                          {pill.label}
                        </button>
                      );
                    })}
                  </div>
                </div>

                <NowProvider>
                  <ContentGrid
                    items={library.items}
                    onDeleteItem={noop}
                    onEditItem={noop}
                    onChatWithItem={noop}
                    tagFilters={[]}
                    searchQuery={query}
                    isPublicView
                    typeFilter={typeFilter}
                  />
                </NowProvider>
              </>
            )}
          </>
        )}
      </div>
    </div>
  );
};

export default AdminUser;
