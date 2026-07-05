import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../theme';
import { CourseSelection } from '../types';
import { useDeviceLocation } from '../lib/useDeviceLocation';
import {
  GolfCoursePrediction,
  autocompleteGolfCourses,
  createSessionToken,
  getPlaceDetails,
  isPlacesApiConfigured,
} from '../lib/placesApi';

type Props = {
  value: CourseSelection | null;
  onChange: (value: CourseSelection | null) => void;
};

const DEBOUNCE_MS = 250;
const MIN_QUERY = 2;
const MAX_SUGGESTIONS = 5;

export const CourseSearchInput: React.FC<Props> = ({ value, onChange }) => {
  const [query, setQuery] = useState(value?.name ?? '');
  const [predictions, setPredictions] = useState<GolfCoursePrediction[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sessionToken, setSessionToken] = useState(() => createSessionToken());
  const location = useDeviceLocation();
  const abortRef = useRef<AbortController | null>(null);

  const placesReady = isPlacesApiConfigured();
  const hasSelection = !!value?.placeId || (!!value && value.name === query);

  useEffect(() => {
    if (!placesReady) return;

    const trimmed = query.trim();
    if (trimmed.length < MIN_QUERY) {
      setPredictions([]);
      setLoading(false);
      setError(null);
      return;
    }

    if (value && value.name === trimmed && value.placeId) {
      setPredictions([]);
      return;
    }

    const handle = setTimeout(async () => {
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;
      setLoading(true);
      setError(null);
      try {
        const results = await autocompleteGolfCourses(
          trimmed,
          sessionToken,
          location.coords
            ? { latitude: location.coords.latitude, longitude: location.coords.longitude }
            : null,
          controller.signal,
        );
        if (controller.signal.aborted) return;
        setPredictions(results.slice(0, MAX_SUGGESTIONS));
      } catch (err) {
        if ((err as { name?: string })?.name === 'AbortError') return;
        console.warn('Course autocomplete failed', err);
        setError('Course search unavailable');
        setPredictions([]);
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }, DEBOUNCE_MS);

    return () => clearTimeout(handle);
  }, [query, sessionToken, location.coords, placesReady, value]);

  const handleChangeText = (text: string) => {
    setQuery(text);
    if (value) onChange(null);
  };

  const handlePick = async (prediction: GolfCoursePrediction) => {
    setLoading(true);
    try {
      const details = await getPlaceDetails(prediction.placeId, sessionToken);
      onChange({
        name: details.name || prediction.mainText,
        placeId: details.placeId,
        address: details.address,
        lat: details.lat,
        lng: details.lng,
      });
      setQuery(details.name || prediction.mainText);
      setPredictions([]);
      setSessionToken(createSessionToken());
    } catch (err) {
      console.warn('Place details failed', err);
      onChange({ name: prediction.mainText });
      setQuery(prediction.mainText);
      setPredictions([]);
      setSessionToken(createSessionToken());
    } finally {
      setLoading(false);
    }
  };

  const handleUseAnyway = () => {
    const trimmed = query.trim();
    if (!trimmed) return;
    onChange({ name: trimmed });
    setPredictions([]);
  };

  const showUseAnyway = useMemo(() => {
    if (hasSelection) return false;
    const trimmed = query.trim();
    if (trimmed.length < MIN_QUERY) return false;
    if (loading) return false;
    return predictions.length === 0;
  }, [hasSelection, query, loading, predictions.length]);

  return (
    <View>
      <View style={styles.inputWrapper}>
        <Ionicons name="search" size={18} color={colors.muted} />
        <TextInput
          style={styles.input}
          placeholder="Search golf course name..."
          placeholderTextColor={colors.placeholder}
          value={query}
          onChangeText={handleChangeText}
          returnKeyType="done"
          autoCorrect={false}
          autoCapitalize="words"
        />
        {loading && <ActivityIndicator size="small" color={colors.muted} />}
        {!loading && hasSelection && (
          <Ionicons name="checkmark-circle" size={18} color={colors.primary} />
        )}
      </View>

      {value?.address && hasSelection && (
        <Text style={styles.selectedAddress}>{value.address}</Text>
      )}

      {predictions.length > 0 && !hasSelection && (
        <View style={styles.suggestionsCard}>
          {predictions.map((p, idx) => (
            <Pressable
              key={p.placeId}
              style={({ pressed }) => [
                styles.suggestionRow,
                idx !== predictions.length - 1 && styles.suggestionDivider,
                pressed && styles.suggestionPressed,
              ]}
              onPress={() => handlePick(p)}
            >
              <Ionicons name="golf-outline" size={18} color={colors.secondary} />
              <View style={styles.suggestionText}>
                <Text style={styles.suggestionMain} numberOfLines={1}>
                  {p.mainText}
                </Text>
                {!!p.secondaryText && (
                  <Text style={styles.suggestionSecondary} numberOfLines={1}>
                    {p.secondaryText}
                  </Text>
                )}
              </View>
            </Pressable>
          ))}
        </View>
      )}

      {showUseAnyway && (
        <Pressable style={styles.useAnyway} onPress={handleUseAnyway}>
          <Ionicons name="add-circle-outline" size={18} color={colors.muted} />
          <Text style={styles.useAnywayText} numberOfLines={1}>
            Use &ldquo;{query.trim()}&rdquo; anyway
          </Text>
        </Pressable>
      )}

      {!placesReady && (
        <Text style={styles.hint}>
          Course search unavailable. Type a name to save manually.
        </Text>
      )}
      {placesReady && error && <Text style={styles.hint}>{error}</Text>}
    </View>
  );
};

const styles = StyleSheet.create({
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 48,
    backgroundColor: colors.card,
    borderRadius: 12,
    paddingHorizontal: 16,
    gap: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  input: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: colors.text,
  },
  selectedAddress: {
    fontSize: 12,
    color: colors.muted,
    marginTop: 6,
    marginLeft: 4,
  },
  suggestionsCard: {
    marginTop: 8,
    backgroundColor: colors.card,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  suggestionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  suggestionPressed: {
    backgroundColor: colors.surfaceGreen,
  },
  suggestionDivider: {
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  suggestionText: {
    flex: 1,
  },
  suggestionMain: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
  },
  suggestionSecondary: {
    fontSize: 12,
    color: colors.muted,
    marginTop: 2,
  },
  useAnyway: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 8,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: colors.border,
  },
  useAnywayText: {
    flex: 1,
    fontSize: 14,
    fontWeight: '600',
    color: colors.muted,
  },
  hint: {
    marginTop: 6,
    marginLeft: 4,
    fontSize: 12,
    color: colors.muted,
  },
});
