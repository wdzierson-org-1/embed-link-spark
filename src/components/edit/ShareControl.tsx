import React, { useEffect, useRef, useState } from 'react';
import { Check, Copy, Share } from 'lucide-react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { Spinner } from '@/components/machine/Machine';
import { mintShareToken, shareUrlFor } from '@/utils/shareToken';

export type ShareUpdates = { share_token: string | null; shared_at: string | null };

/**
 * The share cell in the panel's window bar (DESIGN-v2 §12.8; docs/ui-changes.md 2026-10-09).
 * Not yet shared: one click mints the link, copies it, and opens the share window. Shared: the
 * cell wears the spot and the click opens the window, where the address can be copied again or
 * the link stopped. The link is unlisted and separate from the public feed.
 */
const ShareControl = ({
  shareToken,
  onChange,
}: {
  shareToken: string | null | undefined;
  onChange: (updates: ShareUpdates) => Promise<void>;
}) => {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);
  // The minted token, until the live row carries it
  const [minted, setMinted] = useState<string | null>(null);
  const copiedTimer = useRef<number | null>(null);
  const token = shareToken || minted;
  const url = token ? shareUrlFor(token) : '';

  useEffect(() => () => { if (copiedTimer.current) window.clearTimeout(copiedTimer.current); }, []);
  useEffect(() => { if (!shareToken) setMinted(null); }, [shareToken]);

  const copy = async () => {
    if (!url) return;
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      if (copiedTimer.current) window.clearTimeout(copiedTimer.current);
      copiedTimer.current = window.setTimeout(() => setCopied(false), 2000);
    } catch {
      /* the address is on screen to copy by hand */
    }
  };

  const share = async () => {
    if (token) {
      setOpen(true);
      return;
    }
    setBusy(true);
    setFailed(false);
    const next = mintShareToken();
    try {
      await onChange({ share_token: next, shared_at: new Date().toISOString() });
      setMinted(next);
      setOpen(true);
      await navigator.clipboard.writeText(shareUrlFor(next)).then(() => {
        setCopied(true);
        copiedTimer.current = window.setTimeout(() => setCopied(false), 2000);
      }).catch(() => {});
    } catch {
      setFailed(true);
      setOpen(true);
    } finally {
      setBusy(false);
    }
  };

  const stop = async () => {
    setBusy(true);
    setFailed(false);
    try {
      await onChange({ share_token: null, shared_at: null });
      setMinted(null);
      setOpen(false);
    } catch {
      setFailed(true);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <Tooltip>
        <TooltipTrigger asChild>
          <PopoverTrigger asChild>
            <button
              type="button"
              onClick={(event) => { event.preventDefault(); void share(); }}
              disabled={busy}
              aria-label={token ? 'Shared — open the share window' : 'Share'}
              className={`grid h-8 w-8 place-items-center transition-colors hover:bg-white hover:text-ink ${token ? 'text-spot-on-ink' : 'text-white'}`}
            >
              {busy && !open ? <Spinner className="font-pixel text-pixel-md leading-none" /> : <Share className="h-4 w-4" />}
            </button>
          </PopoverTrigger>
        </TooltipTrigger>
        <TooltipContent side="bottom">{token ? 'shared · anyone with the link' : 'share'}</TooltipContent>
      </Tooltip>
      <PopoverContent align="end" sideOffset={6} className="w-[380px] rounded-none border-ink bg-white p-0 shadow-print-sm">
        <div className="flex h-[22px] items-center bg-ink px-2 font-pixel text-pixel leading-none text-white">share</div>
        <div className="p-3">
          <div className="mb-2 font-pixel text-pixel leading-none text-muted-foreground" role="status">
            {failed ? <span className="text-error">✕ couldn't update the link. try again</span> : copied ? '✓ link copied · anyone with it can view' : token ? 'anyone with the link can view' : 'creating the link…'}
          </div>
          {url && (
            <div className="flex items-stretch border border-ink bg-white">
              <span className="min-w-0 flex-1 truncate px-3 py-2 font-code text-[12.5px] text-ink [font-variant-ligatures:none]" title={url}>{url}</span>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    type="button"
                    onClick={() => void copy()}
                    aria-label={copied ? 'Copied' : 'Copy link'}
                    className="grid w-10 flex-none place-items-center border-l border-ink text-ink transition-colors hover:bg-ink hover:text-white focus-visible:bg-ink focus-visible:text-white focus-visible:outline-none"
                  >
                    {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  </button>
                </TooltipTrigger>
                <TooltipContent side="top">{copied ? 'copied' : 'copy link'}</TooltipContent>
              </Tooltip>
            </div>
          )}
          {token && (
            <div className="mt-3 flex items-center justify-between">
              <span className="font-pixel text-pixel leading-none text-muted-foreground">not on your feed · read only</span>
              <button
                type="button"
                onClick={() => void stop()}
                disabled={busy}
                className="-mr-2 h-8 px-2 text-[13px] text-error transition-colors hover:bg-error hover:text-white disabled:opacity-60"
              >
                Stop sharing
              </button>
            </div>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
};

export default ShareControl;
