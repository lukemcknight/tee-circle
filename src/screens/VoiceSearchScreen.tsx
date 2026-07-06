import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import {
  ExpoSpeechRecognitionModule,
  useSpeechRecognitionEvent,
} from 'expo-speech-recognition';
import { colors, spacing } from '../theme';
import { ParsedIntent, RootStackParamList } from '../navigation/types';
import { supabase } from '../lib/supabase';
import { useDeviceLocation } from '../lib/useDeviceLocation';

type Props = NativeStackScreenProps<RootStackParamList, 'VoiceSearch'>;

type VoiceState = 'idle' | 'listening' | 'parsing' | 'error';

const EXAMPLE_PROMPT = '"Find me a tee time tomorrow morning for two at Keney Park"';

export const VoiceSearchScreen: React.FC<Props> = ({ navigation }) => {
  const [state, setState] = useState<VoiceState>('idle');
  const [transcript, setTranscript] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  // The event handlers below close over stale state, so mirror what they need in refs.
  const transcriptRef = useRef('');
  const stateRef = useRef<VoiceState>('idle');
  const location = useDeviceLocation();

  stateRef.current = state;

  useEffect(() => {
    return () => {
      // Don't leave the recognizer running if the user backs out mid-listen.
      ExpoSpeechRecognitionModule.abort();
    };
  }, []);

  // stateRef is also written synchronously below: the recognizer can fire
  // result(isFinal) and end back-to-back, before React re-renders, and only
  // the first should trigger a parse.
  const fail = useCallback((message: string) => {
    stateRef.current = 'error';
    setErrorMessage(message);
    setState('error');
  }, []);

  const parseTranscript = useCallback(
    async (finalTranscript: string) => {
      const trimmed = finalTranscript.trim();
      if (!trimmed) {
        fail("We didn't catch that. Try again?");
        return;
      }
      stateRef.current = 'parsing';
      setState('parsing');
      const { data, error } = await supabase.functions.invoke<ParsedIntent>('parse-intent', {
        body: { transcript: trimmed },
      });
      if (error || !data) {
        fail("We couldn't understand that request. Try again?");
        return;
      }
      navigation.replace('TeeTimeReview', { intent: data, transcript: trimmed });
    },
    [fail, navigation],
  );

  useSpeechRecognitionEvent('result', (event) => {
    const text = event.results[0]?.transcript ?? '';
    transcriptRef.current = text;
    setTranscript(text);
    if (event.isFinal && stateRef.current === 'listening') {
      parseTranscript(text);
    }
  });

  useSpeechRecognitionEvent('error', (event) => {
    if (event.error === 'aborted') return;
    if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
      fail('Speech recognition is not allowed. Enable microphone and speech recognition in Settings.');
    } else if (event.error === 'no-speech' || event.error === 'speech-timeout') {
      fail("We didn't hear anything. Try again?");
    } else {
      fail('Something went wrong with speech recognition. Try again?');
    }
  });

  useSpeechRecognitionEvent('end', () => {
    // iOS may end the session (silence timeout) without an isFinal result.
    // If we heard something and aren't already parsing, use what we have.
    if (stateRef.current === 'listening') {
      parseTranscript(transcriptRef.current);
    }
  });

  const startListening = async () => {
    setErrorMessage(null);
    setTranscript('');
    transcriptRef.current = '';
    const permission = await ExpoSpeechRecognitionModule.requestPermissionsAsync();
    if (!permission.granted) {
      fail('Microphone access is required for voice search. Enable it in Settings.');
      return;
    }
    stateRef.current = 'listening';
    setState('listening');
    ExpoSpeechRecognitionModule.start({
      lang: 'en-US',
      interimResults: true,
      continuous: false,
    });
  };

  const stopListening = () => {
    // stop() lets the recognizer deliver its final result (then 'end').
    ExpoSpeechRecognitionModule.stop();
  };

  const onMicPress = () => {
    if (state === 'listening') {
      stopListening();
    } else if (state !== 'parsing') {
      startListening();
    }
  };

  const statusText =
    state === 'listening'
      ? 'Listening… tap when done'
      : state === 'parsing'
        ? 'Got it — figuring out what you need…'
        : state === 'error'
          ? errorMessage ?? 'Something went wrong.'
          : 'Tap the mic and say what you’re looking for';

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
        <View style={styles.header}>
          <Pressable onPress={() => navigation.goBack()} style={styles.headerButton}>
            <Text style={styles.cancelText}>Cancel</Text>
          </Pressable>
          <Text style={styles.headerTitle}>Voice Search</Text>
          <View style={styles.headerButton} />
        </View>
      </SafeAreaView>

      <View style={styles.body}>
        <View style={styles.statusBlock}>
          <Text style={[styles.statusText, state === 'error' && styles.errorText]}>
            {statusText}
          </Text>
          {state === 'idle' && <Text style={styles.exampleText}>{EXAMPLE_PROMPT}</Text>}
        </View>

        <View style={styles.transcriptBlock}>
          {transcript.length > 0 && (
            <Text style={styles.transcriptText}>&ldquo;{transcript}&rdquo;</Text>
          )}
        </View>

        <View style={styles.micBlock}>
          {state === 'parsing' ? (
            <View style={[styles.micButton, styles.micButtonParsing]}>
              <ActivityIndicator size="large" color={colors.text} />
            </View>
          ) : (
            <Pressable
              style={({ pressed }) => [
                styles.micButton,
                state === 'listening' && styles.micButtonListening,
                pressed && styles.micButtonPressed,
              ]}
              onPress={onMicPress}
              accessibilityRole="button"
              accessibilityLabel={state === 'listening' ? 'Stop listening' : 'Start voice search'}
            >
              <Ionicons
                name={state === 'listening' ? 'stop' : 'mic'}
                size={44}
                color={colors.text}
              />
            </Pressable>
          )}

          {state === 'error' && (
            <Pressable style={styles.retryButton} onPress={startListening}>
              <Ionicons name="refresh" size={16} color={colors.text} />
              <Text style={styles.retryText}>Try again</Text>
            </Pressable>
          )}

          {state === 'idle' && location.status === 'denied' && (
            <Text style={styles.locationHint}>
              Tip: allow location access to search courses near you.
            </Text>
          )}
        </View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  headerSafeArea: {
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  headerButton: {
    minWidth: 60,
  },
  cancelText: {
    fontSize: 16,
    fontWeight: '500',
    color: colors.muted,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
  },
  body: {
    flex: 1,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.xl,
    justifyContent: 'space-between',
  },
  statusBlock: {
    alignItems: 'center',
    gap: spacing.sm,
    paddingTop: spacing.xl,
  },
  statusText: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.text,
    textAlign: 'center',
  },
  errorText: {
    color: colors.error,
  },
  exampleText: {
    fontSize: 15,
    color: colors.muted,
    textAlign: 'center',
    fontStyle: 'italic',
  },
  transcriptBlock: {
    flex: 1,
    justifyContent: 'center',
    paddingVertical: spacing.lg,
  },
  transcriptText: {
    fontSize: 22,
    fontWeight: '600',
    color: colors.text,
    textAlign: 'center',
  },
  micBlock: {
    alignItems: 'center',
    gap: spacing.md,
    paddingBottom: spacing.xl,
  },
  micButton: {
    width: 96,
    height: 96,
    borderRadius: 48,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: colors.primary,
    shadowOpacity: 0.35,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 10 },
    elevation: 4,
  },
  micButtonListening: {
    backgroundColor: colors.error,
    shadowColor: colors.error,
  },
  micButtonParsing: {
    opacity: 0.7,
  },
  micButtonPressed: {
    transform: [{ scale: 0.96 }],
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 999,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  retryText: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.text,
  },
  locationHint: {
    fontSize: 13,
    color: colors.muted,
    textAlign: 'center',
  },
});
