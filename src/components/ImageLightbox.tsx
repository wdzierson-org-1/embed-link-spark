import React from 'react';
import { Button } from '@/components/ui/button';
import { X, Download } from 'lucide-react';

interface ImageLightboxProps {
  src: string;
  fileName: string;
  isOpen: boolean;
  onClose: () => void;
}

const ImageLightbox = ({ src, fileName, isOpen, onClose }: ImageLightboxProps) => {
  if (!isOpen) return null;

  const handleBackdropClick = (e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  const handleDownload = () => {
    const link = document.createElement('a');
    link.href = src;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <div 
      className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center p-4"
      onClick={handleBackdropClick}
    >
      <div className="relative max-w-7xl w-full max-h-full">
        <div className="absolute -top-12 right-0 flex gap-2 z-10">
          <Button
            variant="ghost"
            size="sm"
            onClick={handleDownload}
            className="text-white hover:text-gray-300 hover:bg-white/10 h-10 w-10 p-0"
          >
            <Download className="h-5 w-5" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={onClose}
            className="text-white hover:text-gray-300 hover:bg-white/10 h-10 w-10 p-0"
          >
            <X className="h-6 w-6" />
          </Button>
        </div>
        
        <div className="bg-black rounded-lg overflow-hidden shadow-2xl">
          <img
            src={src}
            alt={fileName}
            className="w-full max-h-[85vh] object-contain"
          />
          
          <div className="p-4 bg-gray-900 text-white border-t border-gray-700">
            <p className="text-sm font-medium truncate">{fileName}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ImageLightbox;