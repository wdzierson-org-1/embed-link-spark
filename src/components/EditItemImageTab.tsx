
import React from 'react';
import { TabsContent } from '@/components/ui/tabs';
import EditItemImageSection from '@/components/EditItemImageSection';

interface EditItemImageTabProps {
  item: { id: string } | null;
  hasImage: boolean;
  imageUrl: string;
  onImageStateChange: (hasImage: boolean, imageUrl: string) => void;
}

const EditItemImageTab = ({ item, hasImage, imageUrl, onImageStateChange }: EditItemImageTabProps) => {
  return (
    <TabsContent value="image" className="px-6 pb-6 mt-0">
      <div className="pt-6">
        {hasImage && (
          <div className="relative inline-block">
            <img
              src={imageUrl}
              alt="Item image"
              className="w-full max-w-md rounded-lg border"
            />
            <EditItemImageSection
              itemId={item?.id || ''}
              hasImage={hasImage}
              imageUrl={imageUrl}
              onImageStateChange={onImageStateChange}
              asLink={true}
            />
          </div>
        )}
      </div>
    </TabsContent>
  );
};

export default EditItemImageTab;
