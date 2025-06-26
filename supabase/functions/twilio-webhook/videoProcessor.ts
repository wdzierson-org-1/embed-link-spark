
export async function processVideo(videoUrl: string, openaiApiKey: string): Promise<string> {
  console.log('Processing video with OpenAI:', videoUrl);
  
  if (!openaiApiKey) {
    console.log('No OpenAI API key provided');
    return 'Video file received but could not be processed (missing API key).';
  }
  
  try {
    // Download the video file to get basic info first
    const videoResponse = await fetch(videoUrl, { method: 'HEAD' });
    const contentLength = videoResponse.headers.get('content-length');
    const fileSizeKB = contentLength ? Math.round(parseInt(contentLength) / 1024) : 'unknown';
    
    // For now, we'll extract audio and transcribe it using Whisper
    // In the future, we could also use GPT-4o for visual analysis
    console.log('Attempting to extract audio and transcribe video');
    
    // Download the full video file
    const fullVideoResponse = await fetch(videoUrl);
    if (!fullVideoResponse.ok) {
      throw new Error(`Failed to download video: ${fullVideoResponse.status}`);
    }
    
    const videoArrayBuffer = await fullVideoResponse.arrayBuffer();
    const videoBlob = new Blob([videoArrayBuffer], { type: 'video/mp4' });
    
    // Create form data for Whisper API
    const formData = new FormData();
    formData.append('file', videoBlob, 'video.mp4');
    formData.append('model', 'whisper-1');
    formData.append('response_format', 'text');
    
    // Send to OpenAI Whisper for audio transcription
    const transcriptionResponse = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
      },
      body: formData,
    });
    
    if (!transcriptionResponse.ok) {
      const errorText = await transcriptionResponse.text();
      console.error('Whisper API error:', errorText);
      // Fall back to basic info if transcription fails
      return `Video file received (${fileSizeKB}KB). Audio transcription failed, but video is saved.`;
    }
    
    const transcriptionText = await transcriptionResponse.text();
    console.log('Video transcription successful, length:', transcriptionText.length);
    
    if (transcriptionText.trim()) {
      return `Video (${fileSizeKB}KB) - Transcription: ${transcriptionText.trim()}`;
    } else {
      return `Video file received (${fileSizeKB}KB). No speech detected in video.`;
    }
    
  } catch (error) {
    console.error('Error processing video:', error);
    
    // Try to get basic file info as fallback
    try {
      const videoResponse = await fetch(videoUrl, { method: 'HEAD' });
      const contentLength = videoResponse.headers.get('content-length');
      const fileSizeKB = contentLength ? Math.round(parseInt(contentLength) / 1024) : 'unknown';
      return `Video file received (${fileSizeKB}KB). Processing failed but video is saved.`;
    } catch (fallbackError) {
      console.error('Error getting video info:', fallbackError);
      return 'Video file received but could not be processed.';
    }
  }
}
