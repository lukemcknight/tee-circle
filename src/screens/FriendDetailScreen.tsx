import React, { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { RootStackParamList } from '../navigation/types';
import { cardShadow, colors, radii, spacing, typography } from '../theme';
import { supabase } from '../lib/supabase';
import { useHandicap } from '../hooks/useHandicap';
import { useFriendCount } from '../hooks/useFriendCount';

type Props = NativeStackScreenProps<RootStackParamList, 'FriendDetail'>;

const getInitials = (name: string | null | undefined) => {
  if (!name) return '?';
  const parts = name.trim().split(/\s+/).slice(0, 2);
  return parts.map((p) => p[0]).join('').toUpperCase() || '?';
};

export const FriendDetailScreen: React.FC<Props> = ({ route, navigation }) => {
  const { friendId, friendName, friendHandle } = route.params;

  const [fetchedName, setFetchedName] = useState<string | null>(null);
  const [fetchedHandle, setFetchedHandle] = useState<string | null>(null);

  const { profile: handicapProfile, loading: handicapLoading } = useHandicap(friendId);
  const { count: friendCount, loading: countLoading } = useFriendCount(friendId);

  useEffect(() => {
    if (friendName && friendHandle) return;

    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('profiles')
        .select('full_name, username')
        .eq('id', friendId)
        .maybeSingle();
      if (cancelled || !data) return;
      if (!friendName && data.full_name) setFetchedName(data.full_name);
      if (!friendHandle && data.username) setFetchedHandle(`@${data.username}`);
    })();

    return () => {
      cancelled = true;
    };
  }, [friendId, friendName, friendHandle]);

  const displayName = friendName || fetchedName || 'Friend';
  const handle = friendHandle || fetchedHandle || '';
  const initials = getInitials(displayName);

  const isHidden = handicapProfile?.isHidden === true;
  const handicapLabel = (() => {
    if (handicapLoading) return '--';
    if (!handicapProfile) return '--';
    if (isHidden) return '—';
    const idx = handicapProfile.handicapIndex;
    return idx !== null && idx !== undefined ? idx.toFixed(1) : '--';
  })();

  const roundsCount = handicapProfile?.roundsCount ?? 0;

  return (
    <SafeAreaView style={styles.safe} edges={['top', 'left', 'right']}>
      <View style={styles.container}>
        <View style={styles.header}>
          <Pressable
            onPress={() => navigation.goBack()}
            style={styles.backButton}
            accessibilityRole="button"
            accessibilityLabel="Go back"
            hitSlop={8}
          >
            <Ionicons name="chevron-back" size={24} color={colors.text} />
          </Pressable>
          <Text style={styles.title} numberOfLines={1}>
            Friend
          </Text>
          <View style={styles.backButton} />
        </View>

        <ScrollView contentContainerStyle={styles.scrollContent}>
          <View style={styles.identity}>
            <View style={styles.avatarOuter}>
              <LinearGradient
                colors={[colors.primary, colors.primaryDark]}
                style={StyleSheet.absoluteFillObject}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 1 }}
              />
              <Text style={styles.avatarInitials}>{initials}</Text>
            </View>
            <Text style={styles.nameText} numberOfLines={1}>
              {displayName}
            </Text>
            {!!handle && (
              <Text style={styles.handleText} numberOfLines={1}>
                {handle}
              </Text>
            )}
          </View>

          <View style={styles.statsRow}>
            <View style={styles.statCard}>
              <Text style={styles.statNumber}>{roundsCount}</Text>
              <Text style={styles.statLabel}>Rounds played</Text>
            </View>
            <View style={styles.statCard}>
              <Text style={styles.statNumber}>
                {countLoading ? '…' : friendCount ?? '—'}
              </Text>
              <Text style={styles.statLabel}>Friends</Text>
            </View>
          </View>

          <View style={styles.spacer} />

          <View style={styles.panel}>
            <View style={styles.panelHeader}>
              <Text style={styles.panelTitle}>Handicap</Text>
              <Text style={styles.handicapValue}>{handicapLabel}</Text>
            </View>
            <Text style={styles.panelSubtitle}>
              {handicapLoading
                ? 'Loading…'
                : isHidden
                  ? 'This player has hidden their handicap.'
                  : handicapProfile?.handicapIndex !== null && handicapProfile?.handicapIndex !== undefined
                    ? roundsCount
                      ? `${roundsCount} posted round${roundsCount === 1 ? '' : 's'}`
                      : 'Established handicap.'
                    : 'No handicap established yet.'}
            </Text>
          </View>

          {(handicapLoading || countLoading) && (
            <View style={styles.inlineSpinner}>
              <ActivityIndicator size="small" color={colors.accent} />
            </View>
          )}
        </ScrollView>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.sm,
  },
  backButton: {
    width: 40,
    height: 40,
    alignItems: 'flex-start',
    justifyContent: 'center',
  },
  title: {
    fontSize: typography.subtitle,
    fontWeight: '700',
    color: colors.text,
  },
  scrollContent: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.xl,
  },
  identity: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.md,
  },
  avatarOuter: {
    width: 80,
    height: 80,
    borderRadius: 40,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.md,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 12,
    elevation: 4,
  },
  avatarInitials: {
    fontSize: 28,
    fontWeight: '800',
    color: colors.card,
  },
  nameText: {
    fontSize: 26,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: -0.4,
    textAlign: 'center',
  },
  handleText: {
    marginTop: spacing.xs,
    fontSize: typography.body,
    fontWeight: '500',
    color: colors.textSecondary,
    textAlign: 'center',
  },
  statsRow: {
    flexDirection: 'row',
    gap: spacing.md,
    marginTop: spacing.md,
  },
  statCard: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: spacing.md,
    backgroundColor: colors.surfaceGreen,
    borderRadius: radii.md,
  },
  statNumber: {
    fontSize: 22,
    fontWeight: '800',
    color: colors.text,
  },
  statLabel: {
    fontSize: typography.small,
    fontWeight: '600',
    color: colors.textSecondary,
    marginTop: 2,
  },
  spacer: {
    height: spacing.md,
  },
  panel: {
    borderWidth: 1,
    borderColor: colors.borderGreen,
    borderRadius: radii.xl,
    backgroundColor: colors.card,
    padding: spacing.md,
    ...cardShadow,
  },
  panelHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.md,
    marginBottom: spacing.xs,
  },
  panelTitle: {
    fontSize: typography.body,
    fontWeight: '700',
    color: colors.text,
  },
  panelSubtitle: {
    marginTop: 4,
    fontSize: typography.small,
    color: colors.textSecondary,
  },
  handicapValue: {
    fontSize: 28,
    fontWeight: '800',
    color: colors.secondary,
  },
  inlineSpinner: {
    marginTop: spacing.md,
    alignItems: 'center',
  },
});
