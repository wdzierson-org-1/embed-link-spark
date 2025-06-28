
interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
  links?: any[];
  files?: any[];
}

interface LinkPreview {
  id: string;
  url: string;
  title?: string;
  description?: string;
  image?: string;
  siteName?: string;
}

interface FilePreview {
  id: string;
  file: File;
  preview?: string;
}

export const extractPrimaryImage = (item: ContentItem): string | null => {
  // First check if there's a file_path (main image)
  if (item.file_path) {
    return item.file_path;
  }

  // Then check for images in uploaded files
  if (item.files && item.files.length > 0) {
    const imageFile = item.files.find((file: FilePreview) => file.preview);
    if (imageFile?.preview) {
      return imageFile.preview;
    }
  }

  // Then check for images in links
  if (item.links && item.links.length > 0) {
    const linkWithImage = item.links.find((link: LinkPreview) => link.image);
    if (linkWithImage?.image) {
      return linkWithImage.image;
    }
  }

  // Finally check content for embedded images (from editor)
  if (item.content) {
    try {
      const contentObj = JSON.parse(item.content);
      const images = extractImagesFromContent(contentObj);
      if (images.length > 0) {
        return images[0];
      }
    } catch (error) {
      // Content is not JSON, skip
    }
  }

  return null;
};

const extractImagesFromContent = (content: any): string[] => {
  const images: string[] = [];
  
  const extractImages = (node: any) => {
    if (node.type === 'image' && node.attrs?.src) {
      images.push(node.attrs.src);
    }
    if (node.content) {
      node.content.forEach(extractImages);
    }
  };
  
  if (content.content) {
    content.content.forEach(extractImages);
  }
  
  return images;
};
