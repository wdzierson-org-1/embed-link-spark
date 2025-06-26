
export async function saveMediaToStorage(
  mediaUrl: string,
  mediaContentType: string,
  userId: string,
  supabase: any
): Promise<string | null> {
  try {
    console.log('Downloading media from Twilio:', mediaUrl);
    
    // Download the media file from Twilio
    const mediaResponse = await fetch(mediaUrl);
    if (!mediaResponse.ok) {
      throw new Error(`Failed to download media: ${mediaResponse.status}`);
    }

    const mediaArrayBuffer = await mediaResponse.arrayBuffer();
    const mediaBlob = new Blob([mediaArrayBuffer], { type: mediaContentType });
    
    console.log('Media downloaded, size:', mediaBlob.size);

    // Generate file path
    const fileExt = getFileExtension(mediaContentType);
    const fileName = `${Date.now()}.${fileExt}`;
    const filePath = `${userId}/${fileName}`;

    console.log('Uploading to storage path:', filePath);

    // Upload to Supabase storage
    const { error: uploadError } = await supabase.storage
      .from('stash-media')
      .upload(filePath, mediaBlob, {
        contentType: mediaContentType,
        cacheControl: '3600'
      });

    if (uploadError) {
      console.error('Storage upload error:', uploadError);
      throw uploadError;
    }

    console.log('Media uploaded successfully to:', filePath);
    return filePath;

  } catch (error) {
    console.error('Error saving media to storage:', error);
    return null;
  }
}

function getFileExtension(contentType: string): string {
  const typeMap: { [key: string]: string } = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'audio/ogg': 'ogg',
    'audio/mpeg': 'mp3',
    'audio/wav': 'wav',
    'audio/webm': 'webm',
    'video/mp4': 'mp4',
    'video/webm': 'webm'
  };
  
  return typeMap[contentType] || 'bin';
}
