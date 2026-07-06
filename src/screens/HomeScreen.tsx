import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useFocusEffect } from '@react-navigation/native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { RoundCard } from '../components/RoundCard';
import { BottomNavBar } from '../components/BottomNavBar';
import { colors, spacing, typography } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useRounds } from '../hooks/useRounds';
import { useData } from '../context/DataContext';
import { useAuth } from '../context/AuthContext';

type Props = NativeStackScreenProps<RootStackParamList, 'Home'>;

export const HomeScreen: React.FC<Props> = ({ navigation }) => {
  const { user, profile, initializing } = useAuth();
  const { rounds, loading: roundsLoading, refresh } = useRounds();
  const { respondToRound } = useData();
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState<'upcoming' | 'past'>('upcoming');

  const isLoading = roundsLoading || initializing;
  const isInitialLoading = isLoading && rounds.length === 0;

  const { upcomingRounds, pastRounds } = useMemo(() => {
    const now = new Date();
    const upcoming: typeof rounds = [];
    const past: typeof rounds = [];

    rounds.forEach((round) => {
      const teeTime = new Date(round.teeTime);
      if (!Number.isNaN(teeTime.valueOf()) && teeTime < now) {
        past.push(round);
      } else {
        upcoming.push(round);
      }
    });

    upcoming.sort((a, b) => new Date(a.teeTime).valueOf() - new Date(b.teeTime).valueOf());
    past.sort((a, b) => new Date(b.teeTime).valueOf() - new Date(a.teeTime).valueOf());

    return { upcomingRounds: upcoming, pastRounds: past };
  }, [rounds]);

  const handleRespond = async (roundId: string, status: 'yes' | 'no') => {
    const success = await respondToRound(roundId, status);
    await refresh();
    if (!success) {
      Alert.alert('Could not update response', 'Something went wrong. Please try again.');
    }
  };

  // Refresh rounds when screen comes into focus (e.g., navigating back)
  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  useEffect(() => {
    if (initializing) return;
    if (user && profile && !profile.username) {
      navigation.replace('Username');
    }
  }, [initializing, user, profile?.username, navigation]);

  const currentUserId = user?.id;
  const bottomNavPadding = Math.max(insets.bottom, spacing.md);
  const fabBottom = 96 + bottomNavPadding;
  const showUpcoming = tab === 'upcoming';
  const showPast = tab === 'past' || (tab === 'upcoming' && pastRounds.length > 0);

  return (
    <SafeAreaView style={styles.safe} edges={['top', 'left', 'right']}>
      <View style={styles.container}>
        <View style={styles.header}>
          <View style={styles.headerRow}>
            <View>
              <Text style={styles.welcomeText}>Welcome back,</Text>
              <Text style={styles.titleText}>Your Schedule</Text>
            </View>
          </View>
          <View style={styles.segmented}>
            <Pressable
              onPress={() => setTab('upcoming')}
              style={[styles.segmentButton, tab === 'upcoming' && styles.segmentActive]}
              accessibilityRole="button"
              accessibilityLabel="Upcoming rounds"
              accessibilityState={{ selected: tab === 'upcoming' }}
            >
              <Text style={[styles.segmentText, tab === 'upcoming' && styles.segmentTextActive]}>Upcoming</Text>
            </Pressable>
            <Pressable
              onPress={() => setTab('past')}
              style={[styles.segmentButton, tab === 'past' && styles.segmentActive]}
              accessibilityRole="button"
              accessibilityLabel="Past rounds"
              accessibilityState={{ selected: tab === 'past' }}
            >
              <Text style={[styles.segmentText, tab === 'past' && styles.segmentTextActive]}>Past Rounds</Text>
            </Pressable>
          </View>
        </View>

        <ScrollView contentContainerStyle={[styles.content, { paddingBottom: fabBottom + spacing.xl }]}>
        {isInitialLoading && (
          <View style={styles.loadingContainer}>
            <ActivityIndicator size="large" color={colors.accent} />
          </View>
        )}

        {!isInitialLoading && user && rounds.length === 0 && (
          <View style={styles.emptyContainer}>
            <Ionicons name="flag" size={48} color={colors.primaryLight} style={styles.emptyIcon} />
            <Text style={styles.emptyTitle} numberOfLines={1}>
              No tee times yet
            </Text>
            <Text style={styles.emptyMessage} numberOfLines={2}>
              Create your first round and invite friends to play.
            </Text>
          </View>
        )}

        {!isInitialLoading &&
          user &&
          showUpcoming &&
          upcomingRounds.map((round) => {
            const isCreator = round.createdBy === currentUserId;
            const isInvitee = round.invites.some((p) => p.id === currentUserId);
            const canRespond = !round.locked && (isInvitee || isCreator);
            const myInvite = round.invites.find((p) => p.id === currentUserId);
            const myStatus = myInvite?.status ?? (isCreator ? 'yes' : 'pending');

            return (
              <RoundCard
                key={round.id}
                round={round}
                onPress={() => navigation.navigate('RoundDetail', { roundId: round.id, initialRound: round })}
                onRespondYes={canRespond ? () => handleRespond(round.id, 'yes') : undefined}
                onRespondNo={canRespond ? () => handleRespond(round.id, 'no') : undefined}
                myStatus={myStatus}
              />
            );
          })}

        {!isInitialLoading && user && showPast && pastRounds.length > 0 && (
          <View style={styles.sectionDivider}>
            <View style={styles.sectionLine} />
            <Text style={styles.sectionLabel}>Previous Rounds</Text>
            <View style={styles.sectionLine} />
          </View>
        )}

        {!isInitialLoading &&
          user &&
          showPast &&
          pastRounds.map((round) => {
            const isCreator = round.createdBy === currentUserId;
            const myInvite = round.invites.find((p) => p.id === currentUserId);
            const myStatus = myInvite?.status ?? (isCreator ? 'yes' : 'pending');

            return (
              <RoundCard
                key={round.id}
                round={round}
                onPress={() => navigation.navigate('RoundDetail', { roundId: round.id, initialRound: round })}
                myStatus={myStatus}
              />
            );
          })}
        </ScrollView>

        <Pressable
          style={[styles.fab, styles.micFab, { bottom: fabBottom + 68 }]}
          onPress={() => {
            if (!user) {
              navigation.replace('Auth');
              return;
            }
            navigation.navigate('VoiceSearch');
          }}
          accessibilityRole="button"
          accessibilityLabel="Search tee times by voice"
        >
          <Ionicons name="mic" size={26} color={colors.card} />
        </Pressable>

        <Pressable
          style={[styles.fab, { bottom: fabBottom }]}
          onPress={() => {
            if (!user) {
              navigation.replace('Auth');
              return;
            }
            navigation.navigate('CreateRound');
          }}
          accessibilityRole="button"
          accessibilityLabel="Create round"
        >
          <Text style={styles.fabIcon}>+</Text>
        </Pressable>

        <BottomNavBar
          activeTab="Schedule"
          onNavigate={(tab) => {
            if (tab === 'Friends') navigation.navigate('Friends');
            else if (tab === 'Profile') navigation.navigate('Profile');
          }}
        />
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
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.md,
    gap: spacing.lg,
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  welcomeText: {
    fontSize: 13,
    color: colors.muted,
    fontWeight: '600',
  },
  titleText: {
    fontSize: 26,
    fontWeight: '800',
    color: colors.text,
    letterSpacing: -0.4,
  },
  segmented: {
    flexDirection: 'row',
    padding: 4,
    backgroundColor: colors.border,
    borderRadius: 999,
  },
  segmentButton: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 999,
    alignItems: 'center',
  },
  segmentActive: {
    backgroundColor: colors.primary,
  },
  segmentText: {
    fontSize: typography.small,
    fontWeight: '600',
    color: colors.muted,
  },
  segmentTextActive: {
    color: colors.text,
    fontWeight: '700',
  },
  content: {
    paddingHorizontal: spacing.lg,
    flexGrow: 1,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: spacing.xl * 2,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: spacing.xl * 2,
    paddingHorizontal: spacing.lg,
  },
  emptyIcon: {
    marginBottom: spacing.md,
  },
  emptyTitle: {
    fontSize: typography.subtitle,
    fontWeight: '600',
    color: colors.text,
    marginBottom: spacing.xs,
  },
  emptyMessage: {
    fontSize: typography.body,
    color: colors.muted,
    textAlign: 'center',
  },
  sectionDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.md,
  },
  sectionLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  sectionLabel: {
    fontSize: 11,
    fontWeight: '700',
    color: colors.inactive,
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  fab: {
    position: 'absolute',
    right: spacing.lg,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: colors.primary,
    shadowOpacity: 0.35,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 10 },
    elevation: 4,
  },
  micFab: {
    backgroundColor: colors.secondary,
    shadowColor: colors.secondary,
  },
  fabIcon: {
    fontSize: 28,
    fontWeight: '700',
    color: colors.text,
  },
});
