
import React from 'react';
import { TabsList, TabsTrigger } from '@/components/ui/tabs';

interface EditItemTabNavigationProps {
  hasImage: boolean;
}

const EditItemTabNavigation = ({ hasImage }: EditItemTabNavigationProps) => {
  return (
    <TabsList className="w-fit">
      <TabsTrigger value="details">Note Details</TabsTrigger>
      {hasImage && <TabsTrigger value="image">Image</TabsTrigger>}
    </TabsList>
  );
};

export default EditItemTabNavigation;
