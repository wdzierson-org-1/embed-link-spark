import React, { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';
import { PaperBackdrop } from '@/components/machine/PaperBackdrop';
import { StatusLine } from '@/components/machine/Machine';
import { St4shWordmark } from '@/components/brand/St4sh';
import { TooltipProvider } from '@/components/ui/tooltip';
import ItemWindowBar from '@/components/edit/ItemWindowBar';
import EditItemLinkSection from '@/components/EditItemLinkSection';
import EditItemImageStage from '@/components/edit/EditItemImageStage';
import EditItemEmbedStage from '@/components/edit/EditItemEmbedStage';
import { embedSourceFor } from '@/utils/embeds';
import EditItemMediaZone from '@/components/edit/EditItemMediaZone';
import EditItemDocumentSection from '@/components/EditItemDocumentSection';
import EditItemDetailsDrawer from '@/components/edit/EditItemDetailsDrawer';
import LocationDetailsSection from '@/components/edit/LocationDetailsSection';
import { readPlace } from '../../supabase/functions/_shared/place';
import ReadOnlyNovelRenderer from '@/components/ReadOnlyNovelRenderer';
import TranscriptContent from '@/components/TranscriptContent';
import { ReadOnlyText } from '@/components/EditItemContentSection';
import { SectionHead } from '@/components/edit/EditPanelSection';
import { getContentTabsConfig, hasCapturedTranscript, type ContentTabKey } from '@/utils/editPanelTabs';
import { noteIsEmpty } from '@/utils/noteContent';
import { SHARE_TOKEN_PATTERN } from '@/utils/shareToken';
import type { ItemAttributes } from '@/types/itemAttributes';

/**
 * The shared page (DESIGN-v2 §12.15; docs/ui-changes.md 2026-10-09): `/s/<token>` shows one
 * save read-only to anyone holding its link: the item panel's object on the library's paper,
 * with the logo, who shared it, and a way to Stash. Everything is read from `shared_item()`,
 * which answers the token alone; a dead or mistyped link gets a plain page.
 */
type SharedRow = Database['public']['Functions']['shared_item']['Returns'][number];
type SharedSave = Omit<SharedRow, 'attributes'> & { attributes: ItemAttributes | null };

const SITE = 'https://www.gostash.it/';
const TITLE = 'font-montreal text-[28px] font-medium leading-[1.12] tracking-[-0.03em] text-ink';
const CTA = 'inline-flex h-9 flex-none items-center bg-ink px-3 text-[13px] font-medium text-white transition-colors hover:bg-white hover:text-ink hover:shadow-[inset_0_0_0_1px_var(--ink)]';

// A stored path becomes its public address; a rescued link preview is already a URL
const publicUrlFor = (filePath: string | null | undefined): string => {
  if (!filePath) return '';
  if (filePath.startsWith('http')) return filePath;
  return supabase.storage.from('stash-media').getPublicUrl(filePath).data.publicUrl;
};

const Shell = ({ attribution, children }: { attribution?: string; children: React.ReactNode }) => (
  <TooltipProvider>
    <div className="relative isolate min-h-screen bg-paper">
      <PaperBackdrop />
      <header className="relative mx-auto flex h-[68px] max-w-[1360px] items-center justify-between gap-4 px-5 sm:px-8">
        <div className="flex min-w-0 items-center gap-3">
          <a
            href={SITE}
            aria-label="Stash"
            className="inline-flex h-9 flex-none items-center bg-white px-3 text-ink shadow-[0_0_0_1px_rgba(0,0,0,0.06)] transition-colors hover:bg-ink hover:text-white"
          >
            <St4shWordmark className="h-[14px]" />
          </a>
          {attribution && <span className="truncate font-pixel text-pixel text-muted-foreground">{attribution}</span>}
        </div>
        <a href={SITE} className={CTA}>Get Stash</a>
      </header>
      <main className="relative mx-auto max-w-[1360px] px-5 pb-20 pt-3 sm:px-8">
        <div className="grid grid-cols-12 gap-6">
          <div className="col-span-12 lg:col-span-8 lg:col-start-3">{children}</div>
        </div>
      </main>
    </div>
  </TooltipProvider>
);

const Gone = () => (
  <Shell>
    <article className="border border-ink bg-white p-8 shadow-print sm:p-10">
      <h1 className={TITLE}>This link no longer works.</h1>
      <p className="mt-3 text-[15px] leading-[1.5] text-muted-foreground">
        Whoever shared it stopped sharing, or the address was mistyped.
      </p>
      <a href={SITE} className={`${CTA} mt-7`}>Get Stash</a>
    </article>
  </Shell>
);

const EmptyTab = ({ children }: { children: React.ReactNode }) => (
  <p className="py-6 text-[15px] leading-[1.5] text-muted-foreground">{children}</p>
);

const SharedItem = () => {
  const { token = '' } = useParams<{ token: string }>();
  const wellFormed = SHARE_TOKEN_PATTERN.test(token);
  const [state, setState] = useState<'loading' | 'ready' | 'gone'>(wellFormed ? 'loading' : 'gone');
  const [save, setSave] = useState<SharedSave | null>(null);
  const [shownTab, setShownTab] = useState<ContentTabKey>('summary');

  useEffect(() => {
    if (!wellFormed) {
      setState('gone');
      return;
    }
    let cancelled = false;
    setState('loading');
    void supabase
      .rpc('shared_item', { p_token: token })
      .then(({ data, error }) => {
        if (cancelled) return;
        const row = !error && Array.isArray(data) ? data[0] : undefined;
        if (!row) {
          setState('gone');
          return;
        }
        const next = row as SharedSave;
        setSave(next);
        setShownTab(getContentTabsConfig(next.type).defaultTab);
        setState('ready');
      });
    return () => {
      cancelled = true;
    };
  }, [token, wellFormed]);

  useEffect(() => {
    if (!save) return;
    const previous = document.title;
    document.title = `${save.title || 'A save'} · Stash`;
    return () => {
      document.title = previous;
    };
  }, [save]);

  const config = useMemo(() => getContentTabsConfig(save?.type ?? undefined), [save?.type]);

  if (state === 'gone') return <Gone />;
  if (state === 'loading' || !save) {
    return (
      <Shell>
        <div className="pt-10">
          <StatusLine tone="busy">opening the save…</StatusLine>
        </div>
      </Shell>
    );
  }

  const attribution = save.username ? `from @${save.username}’s stash` : 'shared from a stash';
  const isNoteObject = config.defaultTab === 'notes';
  const sourceTabs = config.tabs.filter((tab) => tab.key !== 'notes');
  const hasNote = !noteIsEmpty(save.content);
  const mediaUrl = publicUrlFor(save.file_path);
  const isPlayable = save.type === 'audio' || save.type === 'video';
  const hasPicture = (save.type === 'image' || save.type === 'link') && Boolean(mediaUrl);
  const embed = save.type === 'link' ? embedSourceFor(save) : null;
  const isDocument = save.type === 'document' || save.type === 'pdf';

  const view = (tab: ContentTabKey) => {
    if (tab === 'summary') {
      return save.summary ? <ReadOnlyText text={save.summary} capped={false} /> : <EmptyTab>No summary for this {isDocument ? 'document' : 'link'}.</EmptyTab>;
    }
    if (tab === 'original') {
      return save.page_body ? <ReadOnlyText text={save.page_body} capped={false} /> : <EmptyTab>No page content was captured.</EmptyTab>;
    }
    if (save.type === 'link' && !hasCapturedTranscript(save.attributes)) return <EmptyTab>No transcript for this video yet.</EmptyTab>;
    return <TranscriptContent itemId={save.id} transcript={save.page_body} />;
  };

  return (
    <Shell attribution={attribution}>
      <article className="border border-ink bg-white shadow-print">
        <ItemWindowBar item={save} />
        <div className="px-4 pb-10 pt-8 sm:px-10">
          {save.type === 'link' && save.url && (
            <div className="mb-7">
              <EditItemLinkSection url={save.url} />
            </div>
          )}

          <h1 className={`${TITLE} break-words`}>{save.title || 'Untitled'}</h1>
          {save.description && (
            <p className="mt-2.5 text-[15px] leading-[1.5] text-muted-foreground">{save.description}</p>
          )}

          {isPlayable && mediaUrl && <EditItemMediaZone item={save} src={mediaUrl} title={save.title ?? undefined} />}
          {embed ? (
            <EditItemEmbedStage embed={embed} title={save.title ?? undefined} />
          ) : (
            hasPicture && <EditItemImageStage src={mediaUrl} alt={save.title || 'Picture'} />
          )}
          {isDocument && save.file_path && (
            <div className="mt-6">
              <EditItemDocumentSection filePath={save.file_path} fileName={save.title ?? undefined} mimeType={save.mime_type ?? undefined} />
            </div>
          )}

          {isNoteObject ? (
            <div className="mt-7 text-[15px] leading-[1.6] text-ink">
              {hasNote ? <ReadOnlyNovelRenderer content={save.content ?? ''} maxLines={100000} /> : <EmptyTab>Nothing written yet.</EmptyTab>}
            </div>
          ) : (
            <>
              {sourceTabs.length > 0 && (
                <section className="mt-[30px]" aria-label={config.title}>
                  <div className="flex min-h-7 items-end justify-between gap-3 border-b border-ink pb-1.5">
                    <div className="-mb-1.5 flex flex-wrap gap-[3px]" role="tablist" aria-label="Source content">
                      {sourceTabs.map((tab) => (
                        <button
                          key={tab.key}
                          type="button"
                          role="tab"
                          aria-selected={shownTab === tab.key}
                          onClick={() => setShownTab(tab.key)}
                          className={`h-7 px-2 font-pixel text-pixel lowercase leading-none transition-colors ${
                            shownTab === tab.key ? 'bg-ink text-white' : 'text-muted-foreground hover:bg-fill hover:text-ink'
                          }`}
                        >
                          {tab.label}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div className="mt-4">{view(sourceTabs.some((tab) => tab.key === shownTab) ? shownTab : sourceTabs[0].key)}</div>
                </section>
              )}
              {hasNote && (
                <section className="mt-[30px]" aria-label="Notes">
                  <SectionHead label="Notes" />
                  <div className="mt-3 text-[15px] leading-[1.6] text-ink">
                    <ReadOnlyNovelRenderer content={save.content ?? ''} maxLines={100000} />
                  </div>
                </section>
              )}
            </>
          )}

          {readPlace(save.attributes?.place) && <LocationDetailsSection place={readPlace(save.attributes?.place)!} />}

          <div className="mt-[30px]">
            <EditItemDetailsDrawer item={save} />
          </div>
        </div>
      </article>
    </Shell>
  );
};

export default SharedItem;
