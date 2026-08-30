import React, { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowRight, Loader2, Paperclip } from 'lucide-react';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { uploadFile } from '@/utils/fileUploader';
import { getGradientPlaceholder } from '@/utils/gradientPlaceholders';

// The landing page's working capture box. Visitors stash real items with no
// account: the first save lazily creates a Supabase *anonymous* session, so
// items live in the real items table and get the full server-side enrichment
// pipeline. At TRY_LIMIT the box becomes an account form — auth.updateUser
// converts the anonymous user in place, so everything they stashed comes with
// them.
const TRY_LIMIT = 10;
const NUDGE_AT = 5;

const URL_RE = /^(https?:\/\/)?([\w-]+\.)+[a-z]{2,}(\/\S*)?$/i;

interface TryItem {
  id: string;
  type: string;
  title: string | null;
  description: string | null;
  file_path: string | null;
  created_at: string;
}

const coverSrcFor = (item: TryItem): string => {
  if (item.file_path) {
    if (item.file_path.startsWith('http')) {
      return `${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(item.file_path)}`;
    }
    return supabase.storage.from('stash-media').getPublicUrl(item.file_path).data.publicUrl;
  }
  return getGradientPlaceholder(item.id);
};

const TryStash = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<TryItem[]>([]);
  const [justSavedId, setJustSavedId] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const [showAccountForm, setShowAccountForm] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [converting, setConverting] = useState(false);
  const [convertError, setConvertError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const userIdRef = useRef<string | null>(null);

  const isRealUser = !!user && !(user as { is_anonymous?: boolean }).is_anonymous;
  const count = items.length;
  const atLimit = count >= TRY_LIMIT;

  const fetchItems = useCallback(async (uid: string) => {
    const { data } = await supabase
      .from('items')
      .select('id, type, title, description, file_path, created_at')
      .eq('user_id', uid)
      .order('created_at', { ascending: false })
      .limit(TRY_LIMIT + 2);
    if (data) setItems(data);
  }, []);

  // Restore a returning visitor's try-stash (anonymous sessions persist), and
  // stream enrichment upgrades into the cards — a link becoming a titled,
  // pictured card on its own is the whole pitch.
  useEffect(() => {
    const anonId = user && !isRealUser ? user.id : null;
    userIdRef.current = anonId;
    if (!anonId) return;

    void fetchItems(anonId);

    const channel = supabase
      .channel(`try-stash-${anonId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'items', filter: `user_id=eq.${anonId}` },
        payload => {
          const next = payload.new as TryItem;
          setItems(prev => prev.map(it => (it.id === next.id ? { ...it, ...next } : it)));
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [user, isRealUser, fetchItems]);

  const ensureSession = async (): Promise<string> => {
    const { data: { session } } = await supabase.auth.getSession();
    if (session?.user) return session.user.id;
    const { data, error: anonError } = await supabase.auth.signInAnonymously();
    if (anonError || !data.user) throw new Error(anonError?.message || 'Could not start a session');
    return data.user.id;
  };

  const invokeCapture = async (fn: string, body: Record<string, unknown>) => {
    const { data, error: fnError } = await supabase.functions.invoke(fn, { body });
    if (fnError) throw fnError;
    return data;
  };

  const afterSave = async (uid: string) => {
    await fetchItems(uid);
    setInput('');
  };

  const handleSubmit = async () => {
    const text = input.trim();
    if (!text || busy || atLimit) return;
    setBusy(true);
    setError(null);
    try {
      const uid = await ensureSession();
      if (URL_RE.test(text)) {
        const url = text.startsWith('http') ? text : `https://${text}`;
        const result = await invokeCapture('add-url', { url, is_public: false });
        setJustSavedId(result?.item?.id ?? null);
      } else {
        const result = await invokeCapture('add-note', { content: text, is_public: false });
        setJustSavedId(result?.note?.id ?? null);
      }
      await afterSave(uid);
    } catch (e) {
      console.error('Try-stash save failed:', e);
      setError("Couldn't save that — give it another try.");
    } finally {
      setBusy(false);
    }
  };

  const handleFiles = async (files: FileList | null) => {
    const file = files?.[0];
    if (!file || busy || atLimit) return;
    setBusy(true);
    setError(null);
    try {
      const uid = await ensureSession();
      const path = await uploadFile(file, uid);
      const result = await invokeCapture('add-file', {
        file_path: path,
        mime_type: file.type,
        file_size: file.size,
        title: file.name.replace(/\.[^.]+$/, ''),
        is_public: false,
      });
      setJustSavedId(result?.item?.id ?? null);
      await afterSave(uid);
    } catch (e) {
      console.error('Try-stash file save failed:', e);
      setError("Couldn't save that file — give it another try.");
    } finally {
      setBusy(false);
    }
  };

  const handleConvert = async (e: React.FormEvent) => {
    e.preventDefault();
    if (converting) return;
    setConverting(true);
    setConvertError(null);
    try {
      const { error: upError } = await supabase.auth.updateUser({ email, password });
      if (upError) throw upError;
      navigate('/home');
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Something went wrong';
      setConvertError(message);
    } finally {
      setConverting(false);
    }
  };

  // Signed-in members don't need the demo box — point them home instead
  if (isRealUser) {
    return (
      <div className="mx-auto mt-10 max-w-xl text-center">
        <button
          onClick={() => navigate('/home')}
          className="inline-flex items-center gap-2 rounded-full bg-foreground px-8 py-3.5 font-montreal text-background transition-colors hover:bg-foreground/90"
        >
          Open your stash
          <ArrowRight className="h-4 w-4" />
        </button>
      </div>
    );
  }

  const helperLine = () => {
    if (error) return <span className="text-red-600">{error}</span>;
    if (count === 0) return 'No account needed — it saves right now.';
    if (count < 3) {
      return (
        <span>
          Saved — Stash is already reading it. <span className="text-foreground/70">Watch the card fill itself in.</span>
        </span>
      );
    }
    if (count < NUDGE_AT) return 'Try dropping a screenshot on the box — Stash reads the pixels too.';
    return `${TRY_LIMIT - count} ${TRY_LIMIT - count === 1 ? 'save' : 'saves'} left before you'll want an account.`;
  };

  const accountForm = (
    <form onSubmit={handleConvert} className="mx-auto w-full max-w-md rounded-2xl border border-black/10 bg-white/85 p-6 text-left shadow-[0_2px_8px_rgba(0,0,0,0.05),0_16px_40px_rgba(109,40,217,0.10)] backdrop-blur">
      <h3 className="font-tobias text-xl text-foreground">
        {atLimit ? 'Your first ten are safe.' : 'Keep this stash forever.'}
      </h3>
      <p className="mb-4 mt-1 font-montreal text-sm text-muted-foreground">
        Create a free account and everything here comes with you. 14 days free, then $4.99/month.
      </p>
      <div className="space-y-2">
        <input
          type="email"
          required
          placeholder="Email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          className="w-full rounded-xl border border-black/10 bg-white px-4 py-2.5 font-montreal text-[15px] outline-none focus:border-violet-400 focus:ring-2 focus:ring-violet-200"
        />
        <input
          type="password"
          required
          minLength={6}
          placeholder="Password"
          value={password}
          onChange={e => setPassword(e.target.value)}
          className="w-full rounded-xl border border-black/10 bg-white px-4 py-2.5 font-montreal text-[15px] outline-none focus:border-violet-400 focus:ring-2 focus:ring-violet-200"
        />
      </div>
      {convertError && <p className="mt-2 font-montreal text-xs text-red-600">{convertError}</p>}
      <button
        type="submit"
        disabled={converting}
        className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-foreground py-2.5 font-montreal text-[15px] text-background transition-colors hover:bg-foreground/90 disabled:opacity-60"
      >
        {converting ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Create my account'}
      </button>
      {!atLimit && (
        <button
          type="button"
          onClick={() => setShowAccountForm(false)}
          className="mt-2 w-full py-1 text-center font-montreal text-xs text-muted-foreground hover:text-foreground"
        >
          Not yet — keep stashing
        </button>
      )}
    </form>
  );

  return (
    <div className="mx-auto mt-10 w-full max-w-2xl">
      {/* The box — or, past the limit / on request, the account form */}
      {atLimit || showAccountForm ? (
        accountForm
      ) : (
        <>
          <p className="mb-3 text-center font-montreal text-[15px] text-foreground/80">
            Stash a link, an image, a doc — whatever — right now:
          </p>
          <div
            onDragOver={e => { e.preventDefault(); setDragOver(true); }}
            onDragLeave={() => setDragOver(false)}
            onDrop={e => { e.preventDefault(); setDragOver(false); void handleFiles(e.dataTransfer.files); }}
            className={`flex items-center gap-2 rounded-2xl border bg-white/85 p-2 pl-4 shadow-[0_2px_8px_rgba(0,0,0,0.05),0_16px_40px_rgba(109,40,217,0.10)] backdrop-blur transition-all duration-150 ${
              dragOver ? 'border-violet-400 ring-2 ring-violet-200' : 'border-black/10'
            }`}
          >
            <input
              value={input}
              onChange={e => setInput(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') void handleSubmit(); }}
              placeholder="Paste a link, or just type a thought…"
              aria-label="Stash a link or note"
              className="min-w-0 flex-1 bg-transparent py-2 font-montreal text-[15px] text-foreground outline-none placeholder:text-muted-foreground/70"
            />
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*,application/pdf,audio/*,video/*"
              className="hidden"
              onChange={e => { void handleFiles(e.target.files); e.target.value = ''; }}
            />
            <button
              onClick={() => fileInputRef.current?.click()}
              title="Attach a file"
              aria-label="Attach a file"
              className="grid h-10 w-10 flex-none place-items-center rounded-xl text-muted-foreground transition-colors hover:bg-violet-50 hover:text-violet-700"
            >
              <Paperclip className="h-[18px] w-[18px]" />
            </button>
            <button
              onClick={() => void handleSubmit()}
              disabled={busy || !input.trim()}
              className="flex h-10 flex-none items-center gap-1.5 rounded-xl bg-foreground px-4 font-montreal text-sm text-background transition-colors hover:bg-foreground/90 disabled:opacity-40"
            >
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Stash it'}
            </button>
          </div>
          <p className="mt-2.5 text-center font-montreal text-[13px] text-muted-foreground">
            {helperLine()}
          </p>
        </>
      )}

      {/* The visitor's real stash, filling itself in via realtime enrichment */}
      {count > 0 && (
        <div className="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <AnimatePresence initial={false}>
            {items.map(item => (
              <motion.div
                key={item.id}
                layout
                initial={{ opacity: 0, y: 14, scale: 0.96 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                transition={{ type: 'spring', stiffness: 260, damping: 24 }}
                className={`overflow-hidden rounded-xl border bg-white text-left shadow-[0_1px_3px_rgba(0,0,0,0.06),0_8px_20px_rgba(109,40,217,0.08)] transition-shadow duration-700 ${
                  item.id === justSavedId ? 'border-violet-300 ring-2 ring-violet-200/70' : 'border-black/5'
                }`}
              >
                <div className="relative h-20 w-full overflow-hidden bg-gray-50">
                  <img src={coverSrcFor(item)} alt="" className="h-full w-full object-cover" loading="lazy" />
                  <span className="absolute left-1.5 top-1.5 rounded bg-black/40 px-1.5 py-px font-montreal text-[9px] uppercase tracking-wider text-white">
                    {item.type}
                  </span>
                </div>
                <div className="p-2.5">
                  <h4 className="line-clamp-1 font-tobias text-[13.5px] leading-snug text-foreground">
                    {item.title || 'Reading it now…'}
                  </h4>
                  <p className="line-clamp-2 mt-0.5 font-montreal text-[11px] leading-snug text-muted-foreground">
                    {item.description || ' '}
                  </p>
                </div>
              </motion.div>
            ))}
          </AnimatePresence>
        </div>
      )}

      {/* Soft nudge once the stash is real; the box stays usable until the limit */}
      {count >= NUDGE_AT && !atLimit && !showAccountForm && (
        <div className="mx-auto mt-6 flex max-w-md items-center justify-between gap-3 rounded-xl border border-violet-200/60 bg-violet-50/60 px-4 py-2.5">
          <p className="font-montreal text-[13px] text-violet-900/80">
            Like it so far? A free account keeps this stash forever.
          </p>
          <button
            onClick={() => setShowAccountForm(true)}
            className="flex-none rounded-lg bg-violet-600 px-3 py-1.5 font-montreal text-xs text-white transition-colors hover:bg-violet-700"
          >
            Keep my stash
          </button>
        </div>
      )}
    </div>
  );
};

export default TryStash;
