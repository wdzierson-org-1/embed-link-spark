// Gradient placeholder images for items without images
import gradient1 from '@/assets/gradients/gradient-1.jpg';
import gradient2 from '@/assets/gradients/gradient-2.jpg';
import gradient3 from '@/assets/gradients/gradient-3.jpg';
import gradient4 from '@/assets/gradients/gradient-4.jpg';
import gradient5 from '@/assets/gradients/gradient-5.jpg';
import gradient6 from '@/assets/gradients/gradient-6.jpg';
import gradient7 from '@/assets/gradients/gradient-7.jpg';
import gradient8 from '@/assets/gradients/gradient-8.jpg';
import gradient9 from '@/assets/gradients/gradient-9.jpg';
import gradient10 from '@/assets/gradients/gradient-10.jpg';

const gradients = [
  gradient1,
  gradient2,
  gradient3,
  gradient4,
  gradient5,
  gradient6,
  gradient7,
  gradient8,
  gradient9,
  gradient10,
];

/**
 * Get a consistent gradient placeholder for an item
 * Uses the item ID to ensure the same item always gets the same gradient
 */
export const getGradientPlaceholder = (itemId: string): string => {
  // Create a simple hash from the item ID
  let hash = 0;
  for (let i = 0; i < itemId.length; i++) {
    const char = itemId.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  
  // Use absolute value and modulo to get a consistent index
  const index = Math.abs(hash) % gradients.length;
  return gradients[index];
};