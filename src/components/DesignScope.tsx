import { useLayoutEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { isV2Route } from '@/utils/designScope';

/** Lime is the default spot; `?spot=violet` (or `?spot=lime`) switches it and is remembered. */
const SPOT_KEY = 'stash_spot';
const readSpot = (): 'lime' | 'violet' => {
  try {
    const fromUrl = new URLSearchParams(window.location.search).get('spot');
    if (fromUrl === 'lime' || fromUrl === 'violet') {
      localStorage.setItem(SPOT_KEY, fromUrl);
      return fromUrl;
    }
    return localStorage.getItem(SPOT_KEY) === 'violet' ? 'violet' : 'lime';
  } catch {
    return 'lime';
  }
};

/**
 * Sets `<html data-ui="v2">` on the routes that run DESIGN-v2 (see `isV2Route`) and the spot
 * colour everywhere. The flag lives on <html> so Radix portals (sheets, menus, dialogs,
 * toasts) are inside the scope too.
 */
const DesignScope = () => {
  const { pathname, search } = useLocation();

  useLayoutEffect(() => {
    const root = document.documentElement;
    if (isV2Route(pathname)) root.dataset.ui = 'v2';
    else delete root.dataset.ui;

    if (readSpot() === 'violet') root.dataset.spot = 'violet';
    else delete root.dataset.spot;
  }, [pathname, search]);

  return null;
};

export default DesignScope;
