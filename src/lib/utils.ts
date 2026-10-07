import { clsx, type ClassValue } from "clsx"
import { extendTailwindMerge } from "tailwind-merge"

// tailwind-merge only knows Tailwind's default scale. Without these, DESIGN-v2's custom sizes
// (`text-pixel`, `text-object-title`…) read as text *colours*, so `cn('text-pixel', 'text-white')`
// would silently drop the size; the shadows and radius need the same introduction.
const twMerge = extendTailwindMerge({
  extend: {
    classGroups: {
      "font-size": [{ text: ["pixel", "pixel-md", "pixel-lg", "screen-title", "section-title", "object-title", "body", "label"] }],
      shadow: [{ shadow: ["object", "print", "print-sm", "drawing"] }],
      rounded: [{ rounded: ["object"] }],
    },
  },
})

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
