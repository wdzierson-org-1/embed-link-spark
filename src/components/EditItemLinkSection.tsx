import React, { useEffect, useRef, useState } from 'react';
import { ArrowUpRight, Check, Copy, Pencil, X } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { Spinner } from '@/components/machine/Machine';
import { domainOfUrl } from '@/utils/linkFlavor';

interface EditItemLinkSectionProps {
  url: string;
  /** Saves a changed address; without it the strip is read-only */
  onUrlSave?: (url: string) => Promise<void>;
}

/** The address as the person typed it, with https:// supplied; null if it isn't a web address */
export const normalizeWebAddress = (raw: string): string | null => {
  const trimmed = raw.trim();
  if (!trimmed || /\s/.test(trimmed)) return null;
  // Anything with a scheme (mailto:, javascript:, ftp://) is judged as typed; only a bare
  // host gets https:// supplied
  const withScheme = /^[a-z][a-z0-9+-]*:/i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    const parsed = new URL(withScheme);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return null;
    if (!parsed.hostname.includes('.')) return null;
    return parsed.href;
  } catch {
    return null;
  }
};

const COPIED_MS = 2000;

const cellFrame = 'grid w-10 flex-none place-items-center border-l border-ink transition-colors focus-visible:outline-none';
const cell = `${cellFrame} text-ink hover:bg-ink hover:text-white focus-visible:bg-ink focus-visible:text-white`;
// The cancel cell is red at rest and fills red: it must not carry the ink hover of the others
const cancelCell = `${cellFrame} text-error hover:bg-error hover:text-white focus-visible:bg-error focus-visible:text-white`;

/**
 * The source address as a machine strip (DESIGN-v2 §12.8): favicon · the whole address, a link
 * · copy · edit · open. Copy says `copied` for two seconds. Edit turns the strip into a field;
 * the same button turns spot and becomes save (Enter saves, Escape cancels), and turns back
 * once the address is saved. An address that isn't a web address is refused with a machine line.
 */
const EditItemLinkSection = ({ url, onUrlSave }: EditItemLinkSectionProps) => {
  const [faviconFailed, setFaviconFailed] = useState(false);
  const [copied, setCopied] = useState(false);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(url);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const copiedTimer = useRef<number>();
  const domain = domainOfUrl(url);

  useEffect(() => () => window.clearTimeout(copiedTimer.current), []);

  // A new item (or a saved address) resets the strip
  useEffect(() => {
    setEditing(false);
    setDraft(url);
    setError(null);
    setFaviconFailed(false);
  }, [url]);

  useEffect(() => {
    if (editing) inputRef.current?.select();
  }, [editing]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.clearTimeout(copiedTimer.current);
      copiedTimer.current = window.setTimeout(() => setCopied(false), COPIED_MS);
    } catch {
      setError("couldn't copy the address");
    }
  };

  const startEditing = () => {
    setDraft(url);
    setError(null);
    setEditing(true);
  };

  const cancel = () => {
    setEditing(false);
    setDraft(url);
    setError(null);
  };

  const save = async () => {
    if (!onUrlSave || saving) return;
    const next = normalizeWebAddress(draft);
    if (!next) {
      setError("that doesn't look like a web address");
      inputRef.current?.focus();
      return;
    }
    if (next === url) {
      cancel();
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await onUrlSave(next);
      setEditing(false);
    } catch {
      setError("couldn't save the address. try again");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <div className="flex items-stretch border border-ink bg-white">
        {editing ? (
          <input
            ref={inputRef}
            type="url"
            value={draft}
            aria-label="Source address"
            aria-invalid={Boolean(error)}
            spellCheck={false}
            autoComplete="off"
            onChange={(event) => {
              setDraft(event.target.value);
              if (error) setError(null);
            }}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                event.preventDefault();
                void save();
              } else if (event.key === 'Escape') {
                event.preventDefault();
                cancel();
              }
            }}
            className="min-w-0 flex-1 bg-white px-3 py-2 font-code text-[12.5px] text-ink outline-none [font-variant-ligatures:none] focus:bg-fill"
          />
        ) : (
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            title={url}
            className="flex min-w-0 flex-1 items-center gap-2.5 px-3 py-2 transition-colors hover:bg-fill focus-visible:bg-fill focus-visible:outline-none"
          >
            {domain && !faviconFailed && (
              <img
                src={`https://www.google.com/s2/favicons?domain=${domain}&sz=32`}
                alt=""
                aria-hidden
                className="h-3.5 w-3.5 flex-none [image-rendering:pixelated]"
                onError={() => setFaviconFailed(true)}
              />
            )}
            <span className="min-w-0 flex-1 truncate font-code text-[12.5px] text-ink underline decoration-ink/30 underline-offset-[3px] [font-variant-ligatures:none]">
              {url}
            </span>
          </a>
        )}

        {!editing && (
          <Tooltip open={copied ? true : undefined}>
            <TooltipTrigger asChild>
              <button type="button" onClick={() => void copy()} aria-label={copied ? 'Copied' : 'Copy address'} className={cell}>
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
              </button>
            </TooltipTrigger>
            <TooltipContent side="bottom">{copied ? 'copied' : 'copy address'}</TooltipContent>
          </Tooltip>
        )}

        {editing && (
          <Tooltip>
            <TooltipTrigger asChild>
              <button
                type="button"
                onClick={cancel}
                disabled={saving}
                aria-label="Cancel editing"
                className={cancelCell}
              >
                <X className="h-4 w-4" strokeWidth={2.5} />
              </button>
            </TooltipTrigger>
            <TooltipContent side="bottom">cancel</TooltipContent>
          </Tooltip>
        )}

        {onUrlSave && (
          <Tooltip>
            <TooltipTrigger asChild>
              <button
                type="button"
                onClick={editing ? () => void save() : startEditing}
                disabled={saving}
                aria-label={editing ? 'Save address' : 'Edit address'}
                className={editing ? `${cell} bg-spot text-spot-on hover:bg-spot hover:text-spot-on focus-visible:bg-spot focus-visible:text-spot-on` : cell}
              >
                {saving ? <Spinner className="font-pixel text-pixel-md leading-none" /> : editing ? <Check className="h-4 w-4" strokeWidth={2.5} /> : <Pencil className="h-4 w-4" />}
              </button>
            </TooltipTrigger>
            <TooltipContent side="bottom">{editing ? 'save address' : 'edit address'}</TooltipContent>
          </Tooltip>
        )}

        {!editing && (
          <Tooltip>
            <TooltipTrigger asChild>
              <a href={url} target="_blank" rel="noopener noreferrer" aria-label="Open link" className={cell}>
                <ArrowUpRight className="h-4 w-4" />
              </a>
            </TooltipTrigger>
            <TooltipContent side="bottom">open</TooltipContent>
          </Tooltip>
        )}
      </div>
      {editing && !error && (
        <p className="mt-1.5 font-pixel text-pixel text-muted-foreground">enter saves · esc cancels</p>
      )}
      {error && (
        <p role="alert" className="mt-1.5 font-pixel text-pixel text-error">
          <span aria-hidden>✕ </span>
          {error}
        </p>
      )}
    </div>
  );
};

export default EditItemLinkSection;
