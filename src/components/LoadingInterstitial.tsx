import React from 'react';

/**
 * Loading interstitial for /home: a conventional arc spinner, done carefully —
 * hairline grey track, violet rounded-cap arc, quiet grey wash. It's on screen
 * for a split second, so nothing here demands attention (DESIGN.md: Motion).
 * Honors prefers-reduced-motion via the motion-reduce utility (static arc).
 */
const LoadingInterstitial = () => (
  <div className="flex min-h-screen items-center justify-center bg-[#f7f7f9] font-montreal">
    <svg
      viewBox="0 0 40 40"
      className="h-9 w-9 animate-spin [animation-duration:0.9s] motion-reduce:animate-none"
      role="img"
      aria-label="Loading"
    >
      <circle cx="20" cy="20" r="16" fill="none" stroke="rgba(20,22,30,0.08)" strokeWidth="3.5" />
      <circle
        cx="20"
        cy="20"
        r="16"
        fill="none"
        stroke="#6d5bd0"
        strokeWidth="3.5"
        strokeLinecap="round"
        strokeDasharray="26 75"
      />
    </svg>
  </div>
);

export default LoadingInterstitial;
