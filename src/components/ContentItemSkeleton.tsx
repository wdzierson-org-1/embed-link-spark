
import React from 'react';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Progress } from '@/components/ui/progress';

interface ContentItemSkeletonProps {
  showProgress?: boolean;
}

const ContentItemSkeleton = ({ showProgress = false }: ContentItemSkeletonProps) => {
  return (
    <Card className="group flex flex-col h-full">
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div className="flex-1 min-w-0 pr-2">
            <Skeleton className="h-6 w-3/4 mb-2" />
          </div>
          <Skeleton className="h-8 w-8 rounded" />
        </div>
      </CardHeader>
      <CardContent className="flex flex-col flex-1">
        <div className="flex-1">
          <Skeleton className="w-full h-32 rounded-md mb-3" />
          
          {/* Progress indicator for large files */}
          {showProgress && (
            <div className="mb-3">
              <Progress value={undefined} className="h-2" />
              <div className="text-xs text-muted-foreground mt-1">
                Processing...
              </div>
            </div>
          )}
          
          <Skeleton className="h-4 w-full mb-2" />
          <Skeleton className="h-4 w-2/3 mb-2" />
          <div className="mb-2">
            <div className="flex flex-wrap gap-1">
              <Skeleton className="h-6 w-16 rounded-full" />
              <Skeleton className="h-6 w-20 rounded-full" />
            </div>
          </div>
        </div>
        
        <div className="flex items-center justify-between mt-auto pt-2">
          <Skeleton className="h-6 w-20 rounded-full" />
          <Skeleton className="h-4 w-20" />
        </div>
      </CardContent>
    </Card>
  );
};

export default ContentItemSkeleton;
