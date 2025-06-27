
import React from 'react';
import { TabsList, TabsTrigger } from '@/components/ui/tabs';

interface EditItemTabNavigationProps {
  hasImage: boolean;
}

const EditItemTabNavigation = ({ hasImage }: EditItemTabNavigationProps) => {
  // Don't render tab navigation if there's no image
  if (!hasImage) {
    return null;
  }

  return (
    <TabsList className="w-fit">
      <TabsTrigger value="details">Note Details</TabsTrigger>
      <TabsTrigger value="image">Image</TabsTrigger>
    </TabsList>
  );
};

export default EditItemTabNavigation;
