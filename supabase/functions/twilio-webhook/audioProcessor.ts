
export async function processAudio(audioUrl: string, openaiApiKey: string): Promise<string> {
  if (!openaiApiKey) {
    return 'Audio received but transcription is not available.';
  }

  try {
    console.log('Processing audio from URL:', audioUrl);

    // Download the audio file
    const audioResponse = await fetch(audioUrl);
    if (!audioResponse.ok) {
      throw new Error(`Failed to download audio: ${audioResponse.status}`);
    }

    const audioArrayBuffer = await audioResponse.arrayBuffer();
    const audioBlob = new Blob([audioArrayBuffer]);
    
    console.log('Audio file downloaded, size:', audioBlob.size);

    // Prepare form data for Whisper API
    const formData = new FormData();
    formData.append('file', audioBlob, 'audio.webm');
    formData.append('model', 'whisper-1');
    formData.append('response_format', 'text');

    // Send to OpenAI Whisper API
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
      throw new Error(`Whisper API error: ${transcriptionResponse.status}`);
    }

    const transcriptionResult = await transcriptionResponse.text();
    console.log('Transcription result:', transcriptionResult);

    if (!transcriptionResult || transcriptionResult.trim() === '') {
      return 'Audio was processed but no speech was detected.';
    }

    return `Audio transcription: "${transcriptionResult.trim()}"`;

  } catch (error) {
    console.error('Error processing audio:', error);
    return 'Audio received but transcription failed. Please try again.';
  }
}
