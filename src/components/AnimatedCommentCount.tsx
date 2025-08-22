import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { MessageCircle } from 'lucide-react';

interface AnimatedCommentCountProps {
  count: number;
  onCommentClick: () => void;
  className?: string;
}

export const AnimatedCommentCount = ({ 
  count, 
  onCommentClick, 
  className = "" 
}: AnimatedCommentCountProps) => {
  const [displayCount, setDisplayCount] = useState(count);
  const [animationKey, setAnimationKey] = useState(0);
  const [pulseKey, setPulseKey] = useState(0);

  useEffect(() => {
    if (count !== displayCount && count > displayCount) {
      // Trigger animations when count increases
      setAnimationKey(prev => prev + 1);
      setPulseKey(prev => prev + 1);
      
      // Update display count after a brief delay to show animation
      const timeout = setTimeout(() => {
        setDisplayCount(count);
      }, 200);
      
      return () => clearTimeout(timeout);
    } else {
      setDisplayCount(count);
    }
  }, [count, displayCount]);

  return (
    <div className="relative">
      <Button
        variant="ghost"
        size="sm"
        onClick={onCommentClick}
        className={`h-8 px-2 text-muted-foreground hover:text-foreground transition-all duration-200 ${className}`}
      >
        <MessageCircle 
          className={`h-4 w-4 mr-1 transition-all duration-200 ${pulseKey > 0 ? 'comment-pulse' : ''}`}
          key={`icon-${pulseKey}`}
        />
        <span 
          className={`text-sm font-medium transition-all duration-200 ${animationKey > 0 ? 'count-increment' : ''}`}
          key={`count-${animationKey}`}
        >
          {displayCount}
        </span>
      </Button>
    </div>
  );
};