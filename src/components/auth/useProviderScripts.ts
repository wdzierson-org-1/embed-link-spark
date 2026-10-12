import { useEffect, useState } from 'react';
import { APPLE_JS_SRC, GIS_SRC } from '@/integrations/auth/providers';

// The provider SDKs are third-party scripts; they load only on the way in, once per page session.
// A blocked script (privacy extensions) fails quietly: its button slot collapses and the email form
// is never affected (spec §6.1). A blocked script's tag is removed so the next mount can try again.
const cache = new Map<string, Promise<void>>();

export function loadScript(src: string): Promise<void> {
  const cached = cache.get(src);
  if (cached) return cached;
  const promise = new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${src}"]`);
    const el = existing ?? document.createElement('script');
    el.addEventListener('load', () => resolve(), { once: true });
    el.addEventListener('error', () => { el.remove(); reject(new Error(`script failed: ${src}`)); }, { once: true });
    if (!existing) {
      el.src = src;
      el.async = true;
      document.head.appendChild(el);
    }
  });
  cache.set(src, promise);
  promise.catch(() => cache.delete(src)); // a blocked script can be tried again on the next mount
  return promise;
}

export const resetScriptCacheForTests = () => cache.clear();

export type ScriptStatus = 'loading' | 'ready' | 'failed';

export function useProviderScripts(): { google: ScriptStatus; apple: ScriptStatus } {
  const [google, setGoogle] = useState<ScriptStatus>('loading');
  const [apple, setApple] = useState<ScriptStatus>('loading');
  useEffect(() => {
    let mounted = true;
    loadScript(GIS_SRC).then(() => mounted && setGoogle('ready'), () => mounted && setGoogle('failed'));
    loadScript(APPLE_JS_SRC).then(() => mounted && setApple('ready'), () => mounted && setApple('failed'));
    return () => { mounted = false; };
  }, []);
  return { google, apple };
}
