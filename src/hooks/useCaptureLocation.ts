import { useCallback, useRef, useState } from 'react';
import { useToast } from '@/hooks/use-toast';
import type { CapturedLocation } from '@/types/itemAttributes';

export type CaptureLocationStatus = 'idle' | 'locating' | 'ready' | 'error';

const LOCATION_CACHE_MS = 5 * 60 * 1000;
const GEO_TIMEOUT_MS = 10_000;
/** How long a submit will wait on an in-flight location lookup */
const SUBMIT_WAIT_MS = 2_500;

interface ReverseGeocodeResponse {
  city?: string;
  locality?: string;
  principalSubdivision?: string;
  countryName?: string;
}

const resolvePosition = () =>
  new Promise<GeolocationPosition>((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: false,
      timeout: GEO_TIMEOUT_MS,
      maximumAge: LOCATION_CACHE_MS,
    });
  });

// Free, key-less, CORS-friendly endpoint that returns locality-level data
const reverseGeocode = async (latitude: number, longitude: number): Promise<ReverseGeocodeResponse | null> => {
  const response = await fetch(
    `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${latitude}&longitude=${longitude}&localityLanguage=en`
  );
  if (!response.ok) return null;
  return response.json();
};

const buildLabel = (geo: ReverseGeocodeResponse): string | null => {
  const place = geo.city?.trim() || geo.locality?.trim();
  const region = geo.principalSubdivision?.trim();

  if (place && region && place !== region) return `${place}, ${region}`;
  if (place) return place;
  if (region) return region;
  return geo.countryName?.trim() || null;
};

/**
 * Powers the pin toggle in the capture panel. When enabled, resolves the
 * browser's position into a full CapturedLocation — coordinates for future
 * map views plus a friendly "Brooklyn, New York"-style label for display —
 * which the panel stores under items.attributes.location.
 */
export const useCaptureLocation = () => {
  const [enabled, setEnabled] = useState(false);
  const [status, setStatus] = useState<CaptureLocationStatus>('idle');
  const [location, setLocation] = useState<CapturedLocation | null>(null);
  const { toast } = useToast();

  const cacheRef = useRef<{ location: CapturedLocation; at: number } | null>(null);
  const inFlightRef = useRef<Promise<CapturedLocation | null> | null>(null);

  const resolveLocation = useCallback(async (): Promise<CapturedLocation | null> => {
    if (inFlightRef.current) return inFlightRef.current;

    const request = (async (): Promise<CapturedLocation | null> => {
      if (!('geolocation' in navigator)) {
        throw new Error('Geolocation unsupported');
      }
      const position = await resolvePosition();
      const { latitude, longitude, accuracy } = position.coords;

      const geo = await reverseGeocode(latitude, longitude);
      const label = geo ? buildLabel(geo) : null;
      if (!label) return null;

      return {
        label,
        latitude,
        longitude,
        accuracy_m: typeof accuracy === 'number' ? Math.round(accuracy) : undefined,
        city: geo?.city?.trim() || geo?.locality?.trim() || undefined,
        region: geo?.principalSubdivision?.trim() || undefined,
        country: geo?.countryName?.trim() || undefined,
        source: 'browser-geolocation',
        captured_at: new Date().toISOString(),
      };
    })();

    inFlightRef.current = request
      .then((resolved) => {
        if (resolved) {
          cacheRef.current = { location: resolved, at: Date.now() };
          setLocation(resolved);
          setStatus('ready');
        } else {
          setStatus('error');
          setEnabled(false);
          toast({
            title: "Couldn't find your location",
            description: 'No place name came back for your position. Posting without it.',
            variant: 'destructive',
          });
        }
        return resolved;
      })
      .catch(() => {
        setStatus('error');
        setEnabled(false);
        toast({
          title: 'Location unavailable',
          description: 'Allow location access in your browser to tag posts with a place.',
          variant: 'destructive',
        });
        return null;
      })
      .finally(() => {
        inFlightRef.current = null;
      });

    return inFlightRef.current;
  }, [toast]);

  const toggle = useCallback(() => {
    if (enabled) {
      setEnabled(false);
      setStatus('idle');
      return;
    }

    setEnabled(true);
    const cached = cacheRef.current;
    if (cached && Date.now() - cached.at < LOCATION_CACHE_MS) {
      setLocation(cached.location);
      setStatus('ready');
      return;
    }
    setStatus('locating');
    void resolveLocation();
  }, [enabled, resolveLocation]);

  /** Location to stamp on a submit right now — waits briefly on an in-flight lookup */
  const getLocationForSubmit = useCallback(async (): Promise<CapturedLocation | null> => {
    if (!enabled) return null;

    const cached = cacheRef.current;
    if (cached && Date.now() - cached.at < LOCATION_CACHE_MS) return cached.location;

    const pending = inFlightRef.current;
    if (!pending) return null;

    const timeout = new Promise<CapturedLocation | null>((resolve) =>
      window.setTimeout(() => resolve(null), SUBMIT_WAIT_MS)
    );
    return Promise.race([pending, timeout]);
  }, [enabled]);

  return { enabled, status, label: location?.label ?? null, toggle, getLocationForSubmit };
};
