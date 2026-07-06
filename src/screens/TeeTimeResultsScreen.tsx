import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import * as WebBrowser from 'expo-web-browser';
import { colors, spacing } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { supabase } from '../lib/supabase';
import { useDeviceLocation } from '../lib/useDeviceLocation';

type Props = NativeStackScreenProps<RootStackParamList, 'TeeTimeResults'>;

/**
 * Mirrors the search-tee-times Edge Function response types
 * (supabase/functions/_shared/types.ts) — keep the two in sync.
 */
type TeeTimeSlot = {
  courseId: string;
  courseName: string;
  facilityId: number;
  alias: string;
  /** ISO 8601 timestamp in course-local time, e.g. "2026-07-05T08:10:00-04:00". */
  teetimeIso: string;
  holes: 9 | 18;
  backNine: boolean;
  minPlayers: number;
  maxPlayers: number;
  priceUsd: number | null;
  bookingUrl: string;
  lat: number | null;
  lng: number | null;
  address: string | null;
};

type SearchResponse =
  | { kind: 'bookable'; slots: TeeTimeSlot[] }
  | { kind: 'unbookable'; name: string; externalUrl: string; reason: string }
  | { kind: 'unknown'; courseQuery: string }
  | { kind: 'error'; message: string };

const formatSlotTime = (teetimeIso: string): string => {
  // teetimeIso is course-local time; read HH:MM straight from the string so
  // the device timezone can't shift it.
  const hhmm = teetimeIso.slice(11, 16);
  const [h, m] = hhmm.split(':').map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return hhmm;
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
};

const formatPrice = (priceUsd: number | null): string =>
  priceUsd === null ? 'Price at course' : `$${priceUsd % 1 === 0 ? priceUsd : priceUsd.toFixed(2)}`;

const formatPlayers = (slot: TeeTimeSlot): string =>
  slot.minPlayers === slot.maxPlayers
    ? `${slot.maxPlayers} players`
    : `${slot.minPlayers}–${slot.maxPlayers} players`;

const formatDateHeading = (iso: string): string => {
  const [y, m, d] = iso.split('-').map(Number);
  const date = new Date();
  date.setFullYear(y || date.getFullYear(), (m || 1) - 1, d || 1);
  date.setHours(0, 0, 0, 0);
  return date.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
};

export const TeeTimeResultsScreen: React.FC<Props> = ({ navigation, route }) => {
  const { intent } = route.params;
  const location = useDeviceLocation();
  const [loading, setLoading] = useState(true);
  const [response, setResponse] = useState<SearchResponse | null>(null);

  const locationSettled = location.status !== 'unasked';

  const runSearch = useCallback(async () => {
    setLoading(true);
    setResponse(null);
    const coords = location.coords
      ? { lat: location.coords.latitude, lng: location.coords.longitude }
      : null;
    const { data, error } = await supabase.functions.invoke<SearchResponse>('search-tee-times', {
      body: { intent, coords },
    });
    if (error || !data) {
      setResponse({ kind: 'error', message: 'Search failed. Check your connection and try again.' });
    } else {
      setResponse(data);
    }
    setLoading(false);
  }, [intent, location.coords]);

  useEffect(() => {
    // Wait for the location prompt to resolve so generic "near me" searches
    // can be distance-filtered on the first request.
    if (!locationSettled) return;
    runSearch();
    // Run once when location settles; retry re-runs manually.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locationSettled]);

  const slotsByCourse = useMemo(() => {
    if (response?.kind !== 'bookable') return [];
    const groups = new Map<string, TeeTimeSlot[]>();
    for (const slot of response.slots) {
      const group = groups.get(slot.courseName) ?? [];
      group.push(slot);
      groups.set(slot.courseName, group);
    }
    return [...groups.entries()]
      .map(([courseName, slots]) => ({
        courseName,
        slots: slots.slice().sort((a, b) => a.teetimeIso.localeCompare(b.teetimeIso)),
      }))
      .sort((a, b) => a.courseName.localeCompare(b.courseName));
  }, [response]);

  const openExternal = (url: string) => {
    WebBrowser.openBrowserAsync(url).catch(() => {});
  };

  const renderBody = () => {
    if (loading || !response) {
      return (
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.accent} />
          <Text style={styles.centerText}>Searching live tee times…</Text>
        </View>
      );
    }

    switch (response.kind) {
      case 'bookable': {
        if (slotsByCourse.length === 0) {
          return (
            <View style={styles.centerContainer}>
              <Ionicons name="golf-outline" size={48} color={colors.primaryLight} />
              <Text style={styles.centerTitle}>No tee times found</Text>
              <Text style={styles.centerText}>
                Nothing matched your time window. Try a wider window or another date.
              </Text>
              <Pressable style={styles.secondaryButton} onPress={() => navigation.goBack()}>
                <Text style={styles.secondaryButtonText}>Adjust search</Text>
              </Pressable>
            </View>
          );
        }
        return (
          <View style={styles.resultsList}>
            {slotsByCourse.map(({ courseName, slots }) => (
              <View key={courseName} style={styles.courseGroup}>
                <View style={styles.courseHeader}>
                  <Ionicons name="golf-outline" size={18} color={colors.secondary} />
                  <Text style={styles.courseName} numberOfLines={1}>
                    {courseName}
                  </Text>
                </View>
                {slots.map((slot) => (
                  <View
                    key={`${slot.courseId}-${slot.teetimeIso}-${slot.holes}-${slot.backNine}`}
                    style={styles.slotCard}
                  >
                    <View style={styles.slotInfo}>
                      <Text style={styles.slotTime}>{formatSlotTime(slot.teetimeIso)}</Text>
                      <Text style={styles.slotMeta}>
                        {formatPrice(slot.priceUsd)} · {formatPlayers(slot)} · {slot.holes} holes
                      </Text>
                    </View>
                    {/* Booking ships in B5 — present but disabled for now. */}
                    <Pressable style={[styles.bookButton, styles.bookButtonDisabled]} disabled>
                      <Text style={styles.bookButtonText}>Book</Text>
                    </Pressable>
                  </View>
                ))}
              </View>
            ))}
            <Text style={styles.footnote}>Booking from Tee Circle is coming soon.</Text>
          </View>
        );
      }

      case 'unbookable':
        return (
          <View style={styles.centerContainer}>
            <View style={styles.messageCard}>
              <Ionicons name="golf-outline" size={32} color={colors.secondary} />
              <Text style={styles.messageTitle}>{response.name}</Text>
              <Text style={styles.messageText}>{response.reason}</Text>
              <Pressable
                style={({ pressed }) => [styles.primaryButton, pressed && styles.primaryButtonPressed]}
                onPress={() => openExternal(response.externalUrl)}
              >
                <Ionicons name="open-outline" size={16} color={colors.text} />
                <Text style={styles.primaryButtonText}>Book on their site</Text>
              </Pressable>
              <Pressable style={styles.secondaryButton} onPress={() => navigation.navigate('CreateRound')}>
                <Text style={styles.secondaryButtonText}>Create round manually</Text>
              </Pressable>
            </View>
          </View>
        );

      case 'unknown':
        return (
          <View style={styles.centerContainer}>
            <View style={styles.messageCard}>
              <Ionicons name="help-circle-outline" size={32} color={colors.muted} />
              <Text style={styles.messageTitle}>
                We can&apos;t search &ldquo;{response.courseQuery}&rdquo; automatically
              </Text>
              <Text style={styles.messageText}>
                That course isn&apos;t connected to live availability yet — you can still add the
                round manually.
              </Text>
              <Pressable
                style={({ pressed }) => [styles.primaryButton, pressed && styles.primaryButtonPressed]}
                onPress={() => navigation.navigate('CreateRound')}
              >
                <Ionicons name="add" size={16} color={colors.text} />
                <Text style={styles.primaryButtonText}>Add it manually</Text>
              </Pressable>
            </View>
          </View>
        );

      case 'error':
        return (
          <View style={styles.centerContainer}>
            <Ionicons name="cloud-offline-outline" size={48} color={colors.muted} />
            <Text style={styles.centerTitle}>Search failed</Text>
            <Text style={styles.centerText}>{response.message}</Text>
            <Pressable
              style={({ pressed }) => [styles.primaryButton, pressed && styles.primaryButtonPressed]}
              onPress={runSearch}
            >
              <Ionicons name="refresh" size={16} color={colors.text} />
              <Text style={styles.primaryButtonText}>Retry</Text>
            </Pressable>
          </View>
        );
    }
  };

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
        <View style={styles.header}>
          <Pressable onPress={() => navigation.goBack()} style={styles.headerButton}>
            <Ionicons name="chevron-back" size={24} color={colors.text} />
          </Pressable>
          <View style={styles.headerCenter}>
            <Text style={styles.headerTitle}>Tee Times</Text>
            <Text style={styles.headerSubtitle} numberOfLines={1}>
              {formatDateHeading(intent.date)}
            </Text>
          </View>
          <View style={styles.headerButton} />
        </View>
      </SafeAreaView>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {renderBody()}
      </ScrollView>
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
    minWidth: 40,
  },
  headerCenter: {
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
  },
  headerSubtitle: {
    fontSize: 12,
    color: colors.muted,
    marginTop: 2,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: 16,
    paddingVertical: 24,
  },
  centerContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
  },
  centerTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
    textAlign: 'center',
  },
  centerText: {
    fontSize: 14,
    color: colors.muted,
    textAlign: 'center',
  },
  resultsList: {
    gap: 24,
  },
  courseGroup: {
    gap: 12,
  },
  courseHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginLeft: 4,
  },
  courseName: {
    flex: 1,
    fontSize: 17,
    fontWeight: '700',
    color: colors.text,
  },
  slotCard: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 14,
    backgroundColor: colors.card,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  slotInfo: {
    flex: 1,
    gap: 4,
  },
  slotTime: {
    fontSize: 17,
    fontWeight: '700',
    color: colors.text,
  },
  slotMeta: {
    fontSize: 13,
    color: colors.muted,
  },
  bookButton: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 999,
    backgroundColor: colors.primary,
  },
  bookButtonDisabled: {
    opacity: 0.4,
  },
  bookButtonText: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.text,
  },
  footnote: {
    fontSize: 12,
    color: colors.inactive,
    textAlign: 'center',
    paddingVertical: spacing.sm,
  },
  messageCard: {
    alignItems: 'center',
    gap: spacing.sm,
    padding: spacing.lg,
    backgroundColor: colors.card,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.border,
    alignSelf: 'stretch',
  },
  messageTitle: {
    fontSize: 17,
    fontWeight: '700',
    color: colors.text,
    textAlign: 'center',
  },
  messageText: {
    fontSize: 14,
    color: colors.muted,
    textAlign: 'center',
  },
  primaryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 12,
    backgroundColor: colors.primary,
    marginTop: spacing.xs,
  },
  primaryButtonPressed: {
    backgroundColor: colors.primaryDark,
  },
  primaryButtonText: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.text,
  },
  secondaryButton: {
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  secondaryButtonText: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
  },
});
