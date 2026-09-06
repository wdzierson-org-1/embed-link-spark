import React, { createContext, useContext, useEffect, useState } from 'react';

// One ticking clock per grid so every card derives reminder state from the
// same instant, and crossing remind_at / remind_at + 24h (which produce no
// realtime event) re-renders without a per-card timer.
const NowContext = createContext<Date | null>(null);

export const NowProvider = ({ children, tickMs = 60_000 }: { children: React.ReactNode; tickMs?: number }) => {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const tick = () => setNow(new Date());
    const id = setInterval(tick, tickMs);
    const onVisible = () => { if (document.visibilityState === 'visible') tick(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(id);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [tickMs]);
  return <NowContext.Provider value={now}>{children}</NowContext.Provider>;
};

export const useNow = (): Date => useContext(NowContext) ?? new Date();
