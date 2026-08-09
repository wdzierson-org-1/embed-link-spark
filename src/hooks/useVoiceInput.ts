import { useCallback, useEffect, useRef, useState } from 'react';

interface UseVoiceInputOptions {
  onFinalTranscript: (text: string) => void;
}

// Live voice input via the Web Speech API (Chrome/Safari/Edge). Browsers
// without SpeechRecognition (Firefox) report isSupported=false and the mic
// affordance hides — a MediaRecorder→Whisper fallback can slot in here later
// without changing consumers.
export const useVoiceInput = ({ onFinalTranscript }: UseVoiceInputOptions) => {
  const [isListening, setIsListening] = useState(false);
  const [interimTranscript, setInterimTranscript] = useState('');
  const recognitionRef = useRef<any>(null);
  const finalRef = useRef('');
  const cancelledRef = useRef(false);
  const onFinalRef = useRef(onFinalTranscript);
  onFinalRef.current = onFinalTranscript;

  const SpeechRecognitionImpl =
    typeof window !== 'undefined'
      ? (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
      : undefined;
  const isSupported = Boolean(SpeechRecognitionImpl);

  const stopInternal = useCallback(() => {
    recognitionRef.current?.stop();
  }, []);

  const start = useCallback(() => {
    if (!SpeechRecognitionImpl || isListening) return;

    const recognition = new SpeechRecognitionImpl();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = navigator.language || 'en-US';

    finalRef.current = '';
    cancelledRef.current = false;
    setInterimTranscript('');

    recognition.onresult = (event: any) => {
      let interim = '';
      let final = '';
      for (let i = 0; i < event.results.length; i++) {
        const result = event.results[i];
        if (result.isFinal) {
          final += result[0].transcript;
        } else {
          interim += result[0].transcript;
        }
      }
      finalRef.current = final;
      setInterimTranscript(final + interim);
    };

    recognition.onerror = () => {
      cancelledRef.current = true;
    };

    recognition.onend = () => {
      setIsListening(false);
      const text = (finalRef.current || '').trim();
      setInterimTranscript('');
      if (!cancelledRef.current && text) {
        onFinalRef.current(text);
      }
      recognitionRef.current = null;
    };

    recognitionRef.current = recognition;
    setIsListening(true);
    recognition.start();
  }, [SpeechRecognitionImpl, isListening]);

  const stop = useCallback(() => {
    stopInternal();
  }, [stopInternal]);

  const cancel = useCallback(() => {
    cancelledRef.current = true;
    stopInternal();
  }, [stopInternal]);

  useEffect(() => () => {
    cancelledRef.current = true;
    recognitionRef.current?.stop();
  }, []);

  return { isSupported, isListening, interimTranscript, start, stop, cancel };
};
