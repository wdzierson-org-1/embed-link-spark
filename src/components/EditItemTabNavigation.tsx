
import React from 'react';
import { TabsList, TabsTrigger } from '@/components/ui/tabs';

interface EditItemTabNavigationProps {
  hasImage: boolean;
}

const EditItemTabNavigation = ({ hasImage }: EditItemTabNavigationProps) => {
  return (
    <div className="px-6 mt-4 flex-shrink-0">
      <TabsList className="w-fit">
        <TabsTrigger value="details">Note Details</TabsTrigger>
        {hasImage && <TabsTrigger value="image">Image</TabsTrigger>}
      </TabsList>
    </div>
  );
};

export default EditItemTabNavigation;
