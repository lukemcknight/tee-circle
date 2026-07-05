import React, { useCallback, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useFocusEffect } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import { BackButton } from '../components/BackButton';
import { PrimaryButton } from '../components/PrimaryButton';
import { StatusBadge } from '../components/StatusBadge';
import { cardShadow, colors, radii, spacing, typography } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useRoundResponses } from '../hooks/useRoundResponses';
import { useScorecards } from '../hooks/useScorecards';
import { useData } from '../context/DataContext';
import { useAuth } from '../context/AuthContext';
import { getProfileHandle, getProfileName } from '../utils/profile';

type Props = NativeStackScreenProps<RootStackParamList, 'RoundDetail'>;

const getInitials = (name: string | null | undefined) => {
  if (!name) return '?';
  const parts = name.trim().split(/\s+/).slice(0, 2);
  return parts.map((p) => p[0]).join('').toUpperCase() || '?';
};

const InitialsAvatar: React.FC<{ name: string | null | undefined; muted?: boolean }> = ({ name, muted }) => (
  <View style={styles.avatar}>
    <LinearGradient
      colors={muted ? [colors.surfaceGreen, colors.borderGreen] : [colors.primary, colors.primaryDark]}
      style={StyleSheet.absoluteFillObject}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
    />
    <Text style={styles.avatarText}>{getInitials(name)}</Text>
  </View>
);

export const RoundDetailScreen: React.FC<Props> = ({ navigation, route }) => {
  const { user, profile } = useAuth();
  const { responses, loading: responsesLoading, refresh: refreshResponses } = useRoundResponses(route.params.roundId);
  const {
    scorecards,
    loading: scorecardsLoading,
    error: scorecardsError,
    refresh: refreshScorecards,
  } = useScorecards(route.params.roundId);
  const { respondToRound, deleteRound } = useData();
  const [deleting, setDeleting] = useState(false);
  const [localStatus, setLocalStatus] = useState<'yes' | 'no' | null>(null);

  useFocusEffect(
    useCallback(() => {
      refreshResponses();
      refreshScorecards();
    }, [refreshResponses, refreshScorecards]),
  );

  const round = route.params.initialRound ?? null;
  const showLoader = responsesLoading && !round;

  const displayInvites = useMemo(() => {
    const baseInvites =
      responses.length > 0
        ? responses
            .filter((resp) => resp.profile && (resp.profile.full_name || resp.profile.username))
            .map((resp) => ({
              id: resp.userId,
              name: getProfileName(resp.profile),
              handle: getProfileHandle(resp.profile),
              status: resp.status,
            }))
        : (round?.invites ?? []).filter((inv) => inv.name || inv.handle);

    const isCreator = !!(round && user && round.createdBy === user.id);
    if (isCreator && !baseInvites.some((p) => p.id === user?.id)) {
      const creatorName = profile ? getProfileName(profile) : null;
      const creatorHandle = profile ? getProfileHandle(profile) : null;
      if (creatorName || creatorHandle) {
        return [{ id: user!.id, name: creatorName, handle: creatorHandle, status: 'yes' as const }, ...baseInvites];
      }
    }

    return baseInvites;
  }, [profile, responses, round, user]);

  if (showLoader) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.accent} />
        </View>
      </SafeAreaView>
    );
  }

  if (!round) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.container}>
          <BackButton onPress={() => navigation.goBack()} />
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyTitle} numberOfLines={1}>
              Round not found
            </Text>
            <Text style={styles.emptyMessage} numberOfLines={2}>
              This round may have been deleted.
            </Text>
          </View>
        </View>
      </SafeAreaView>
    );
  }

  const isCreator = round.createdBy === user?.id;
  const serverStatus = displayInvites.find((p) => p.id === user?.id)?.status ?? (isCreator ? 'yes' : 'pending');
  const myStatus = localStatus ?? serverStatus;
  const isInvitee = displayInvites.some((p) => p.id === user?.id);
  const canRespond = !!user && !round.locked && (isInvitee || isCreator);
  const committedCount = displayInvites.filter((p) => p.status === 'yes').length;
  const isYesActive = myStatus === 'yes';
  const isNoActive = myStatus === 'no';
  const myScorecard = scorecards.find((scorecard) => scorecard.playerId === user?.id) ?? null;

  const handleResponse = async (status: 'yes' | 'no') => {
    if (!user) return;
    setLocalStatus(status);
    const success = await respondToRound(round.id, status);
    await refreshResponses();

    if (!success) {
      setLocalStatus(null);
      Alert.alert('Could not update response', 'Something went wrong. Please try again.');
    }
  };

  const confirmDelete = () => {
    if (!round) return;
    Alert.alert(
      'Delete this round?',
      'This will remove the round and its invites for everyone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            setDeleting(true);
            const success = await deleteRound(round.id);
            if (success) {
              navigation.replace('Home');
            } else {
              Alert.alert('Unable to delete', 'Something went wrong. Please try again.');
              setDeleting(false);
            }
          },
        },
      ],
    );
  };

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <BackButton onPress={() => navigation.goBack()} />

        {round.locked && (
          <View style={styles.lockedBanner}>
            <Text style={styles.lockedTitle} numberOfLines={1}>
              Round Locked
            </Text>
            <Text style={styles.lockedMessage} numberOfLines={2}>
              Commitments reached. Details are fixed.
            </Text>
          </View>
        )}

        <View style={styles.headerRow}>
          <View style={styles.titleWrapper}>
            <Text style={styles.title} numberOfLines={2} ellipsizeMode="tail">
              {round.course}
            </Text>
          </View>
          <View style={styles.badgeWrapper}>
            <StatusBadge status={round.locked ? 'Locked' : 'Open'} />
          </View>
        </View>

        {/* Details Card */}
        <View style={styles.card}>
          <View style={styles.detailRow}>
            <Text style={styles.detailLabel} numberOfLines={1}>
              Date & Time
            </Text>
            <Text style={styles.detailValue} numberOfLines={1} ellipsizeMode="tail">
              {round.date} · {round.time}
            </Text>
          </View>
          <View style={styles.detailRow}>
            <Text style={styles.detailLabel} numberOfLines={1}>
              Format
            </Text>
            <Text style={styles.detailValue} numberOfLines={1}>
              {round.holes} holes · {round.walking ? 'Walking' : 'Riding'}
            </Text>
          </View>
          <View style={styles.detailRow}>
            <Text style={styles.detailLabel} numberOfLines={1}>
              Committed
            </Text>
            <Text style={[styles.detailValue, styles.committedValue]} numberOfLines={1}>
              {committedCount} player{committedCount !== 1 ? 's' : ''}
            </Text>
          </View>
        </View>

        {/* Commitment Card */}
        <View style={styles.card}>
          <Text style={styles.cardTitle} numberOfLines={1}>
            Your commitment
          </Text>
          <View style={styles.commitRow}>
            <Pressable
              onPress={() => handleResponse('yes')}
              disabled={!canRespond}
              style={[
                styles.commitButton,
                styles.commitYes,
                isYesActive && styles.commitYesActive,
                !canRespond && styles.commitDisabled,
              ]}
            >
              <Text
                style={[
                  styles.commitText,
                  isYesActive && styles.commitYesText,
                  !canRespond && styles.commitDisabledText,
                ]}
                numberOfLines={1}
              >
                I'm in
              </Text>
            </Pressable>
            <Pressable
              onPress={() => handleResponse('no')}
              disabled={!canRespond}
              style={[
                styles.commitButton,
                styles.commitNo,
                isNoActive && styles.commitNoActive,
                !canRespond && styles.commitDisabled,
              ]}
            >
              <Text
                style={[
                  styles.commitText,
                  isNoActive && styles.commitNoText,
                  !canRespond && styles.commitDisabledText,
                ]}
                numberOfLines={1}
              >
                Can't make it
              </Text>
            </Pressable>
          </View>
          {round.locked && (
            <Text style={styles.helperText} numberOfLines={1}>
              Responses are disabled after locking.
            </Text>
          )}
          {!isInvitee && !isCreator && (
            <Text style={styles.helperText} numberOfLines={1}>
              Only invitees can respond to this round.
            </Text>
          )}
        </View>

        {/* Invited Players Card */}
        <View style={styles.card}>
          <Text style={styles.cardTitle} numberOfLines={1}>
            Invited players
          </Text>
          {displayInvites.length === 0 && (
            <Text style={styles.helperText} numberOfLines={1}>
              No players invited yet.
            </Text>
          )}
          <View style={styles.playerList}>
            {displayInvites.map((player) => {
              if (!player.name && !player.handle) return null;
              const displayName = player.name || player.handle;
              const isMuted = player.status !== 'yes';
              return (
                <View key={player.id} style={styles.playerRow}>
                  <InitialsAvatar name={displayName} muted={isMuted} />
                  <View style={styles.playerInfo}>
                    <Text style={styles.playerName} numberOfLines={1} ellipsizeMode="tail">
                      {displayName}
                    </Text>
                    {player.handle && player.name && player.handle !== player.name && (
                      <Text style={styles.playerHandle} numberOfLines={1} ellipsizeMode="tail">
                        {player.handle}
                      </Text>
                    )}
                  </View>
                  <View style={[styles.statusPill, getStatusStyle(player.status)]}>
                    <Text style={[styles.statusText, getStatusTextStyle(player.status)]} numberOfLines={1}>
                      {player.status === 'pending' ? 'Pending' : player.status === 'yes' ? 'Yes' : 'No'}
                    </Text>
                  </View>
                </View>
              );
            })}
          </View>
        </View>

        {/* Scorecards Card */}
        <View style={styles.card}>
          <View style={styles.cardHeaderRow}>
            <Text style={styles.cardTitle} numberOfLines={1}>
              Scorecards
            </Text>
            <Pressable
              onPress={() => navigation.navigate('RoundScore', { roundId: round.id, initialRound: round })}
              style={styles.inlineAction}
            >
              <Text style={styles.inlineActionText}>{myScorecard ? 'Edit score' : 'Enter score'}</Text>
            </Pressable>
          </View>
          {scorecardsLoading && (
            <Text style={styles.helperText} numberOfLines={1}>
              Loading scorecards...
            </Text>
          )}
          {!scorecardsLoading && !!scorecardsError && (
            <Text style={styles.errorHelperText}>{scorecardsError}</Text>
          )}
          {!scorecardsLoading && scorecards.length === 0 && (
            <Text style={styles.helperText}>
              No scores posted yet. Add your score to start tracking handicap and net scoring.
            </Text>
          )}
          <View style={styles.playerList}>
            {scorecards.map((scorecard) => {
              const scoreName = getProfileName(scorecard.profile) || getProfileHandle(scorecard.profile) || 'Player';
              return (
                <View key={scorecard.id} style={styles.playerRow}>
                  <InitialsAvatar name={scoreName} />
                  <View style={styles.playerInfo}>
                    <Text style={styles.playerName} numberOfLines={1}>
                      {scoreName}
                    </Text>
                    <Text style={styles.playerHandle} numberOfLines={1}>
                      Gross {scorecard.grossScore ?? '--'} · Net {scorecard.netScore ?? '--'}
                    </Text>
                  </View>
                  <View style={styles.scorePill}>
                    <Text style={styles.scorePillText}>
                      {scorecard.handicapIndexAtRound !== null
                        ? `HI ${scorecard.handicapIndexAtRound.toFixed(1)}`
                        : 'New'}
                    </Text>
                  </View>
                </View>
              );
            })}
          </View>
        </View>

        <PrimaryButton
          label="Invite friends"
          onPress={() => navigation.navigate('InviteFriends', { roundId: round.id, initialRound: round })}
          disabled={round.locked || !user}
        />

        {isCreator && (
          <Pressable
            onPress={confirmDelete}
            disabled={deleting}
            style={styles.deleteLink}
          >
            <Text style={[styles.deleteText, deleting && styles.deleteTextDisabled]} numberOfLines={1}>
              {deleting ? 'Deleting...' : 'Delete round'}
            </Text>
          </Pressable>
        )}
      </ScrollView>
    </SafeAreaView>
  );
};

const getStatusStyle = (status: string) => {
  switch (status) {
    case 'yes':
      return { backgroundColor: 'rgba(124, 203, 138, 0.15)', borderColor: colors.primary };
    case 'no':
      return { backgroundColor: colors.errorLight, borderColor: colors.error };
    default:
      return { backgroundColor: 'rgba(107, 114, 128, 0.1)', borderColor: colors.border };
  }
};

const getStatusTextStyle = (status: string) => {
  switch (status) {
    case 'yes':
      return { color: colors.secondary };
    case 'no':
      return { color: colors.error };
    default:
      return { color: colors.muted };
  }
};

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    padding: spacing.lg,
    gap: spacing.md,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: spacing.xl * 2,
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
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    minWidth: 0,
    gap: spacing.md,
  },
  titleWrapper: {
    flex: 1,
    minWidth: 0,
  },
  title: {
    fontSize: typography.title,
    fontWeight: '700',
    color: colors.text,
  },
  badgeWrapper: {
    flexShrink: 0,
  },
  // Shared card style
  card: {
    backgroundColor: colors.card,
    borderRadius: radii.xl,
    padding: spacing.md,
    gap: spacing.sm,
    ...cardShadow,
  },
  cardTitle: {
    fontSize: typography.subtitle,
    fontWeight: '600',
    color: colors.text,
  },
  cardHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.sm,
  },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: spacing.md,
  },
  detailLabel: {
    fontSize: typography.small,
    color: colors.muted,
    flexShrink: 0,
  },
  detailValue: {
    fontSize: typography.body,
    color: colors.text,
    fontWeight: '500',
    flex: 1,
    textAlign: 'right',
  },
  committedValue: {
    color: colors.secondary,
    fontWeight: '600',
  },
  inlineAction: {
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: radii.lg,
    backgroundColor: colors.surfaceGreen,
  },
  inlineActionText: {
    color: colors.secondary,
    fontSize: typography.small,
    fontWeight: '700',
  },
  commitRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  commitButton: {
    flex: 1,
    paddingVertical: spacing.md,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
  },
  commitYes: {
    borderColor: colors.border,
    backgroundColor: colors.background,
  },
  commitYesActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  commitNo: {
    borderColor: colors.border,
    backgroundColor: colors.background,
  },
  commitNoActive: {
    backgroundColor: colors.error,
    borderColor: colors.error,
  },
  commitText: {
    fontWeight: '600',
    fontSize: typography.body,
    color: colors.muted,
  },
  commitYesText: {
    color: colors.card,
  },
  commitNoText: {
    color: colors.card,
  },
  commitDisabled: {
    opacity: 0.5,
  },
  commitDisabledText: {
    color: colors.muted,
  },
  helperText: {
    color: colors.muted,
    fontSize: typography.small,
  },
  errorHelperText: {
    color: colors.error,
    fontSize: typography.small,
  },
  // Player list
  playerList: {
    gap: spacing.xs,
  },
  playerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.xs,
  },
  avatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: colors.text,
    fontWeight: '700',
    fontSize: 13,
  },
  playerInfo: {
    flex: 1,
    minWidth: 0,
    gap: 2,
  },
  playerName: {
    fontSize: typography.body,
    color: colors.text,
    fontWeight: '600',
  },
  playerHandle: {
    fontSize: typography.small,
    color: colors.muted,
  },
  statusPill: {
    paddingVertical: spacing.xs / 2,
    paddingHorizontal: spacing.sm,
    borderRadius: radii.lg,
    borderWidth: 1,
    flexShrink: 0,
  },
  statusText: {
    fontWeight: '600',
    fontSize: typography.small,
  },
  scorePill: {
    paddingVertical: spacing.xs / 2,
    paddingHorizontal: spacing.sm,
    borderRadius: radii.lg,
    backgroundColor: colors.surfaceGreen,
    borderWidth: 1,
    borderColor: colors.borderGreen,
  },
  scorePillText: {
    color: colors.secondary,
    fontSize: typography.small,
    fontWeight: '700',
  },
  lockedBanner: {
    backgroundColor: 'rgba(124, 203, 138, 0.15)',
    borderRadius: radii.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.primary,
    gap: spacing.xs / 2,
  },
  lockedTitle: {
    fontSize: typography.body,
    fontWeight: '600',
    color: colors.secondary,
  },
  lockedMessage: {
    color: colors.text,
    fontSize: typography.small,
  },
  deleteLink: {
    alignItems: 'center',
    paddingVertical: spacing.sm,
  },
  deleteText: {
    color: colors.error,
    fontWeight: '600',
    fontSize: typography.small,
  },
  deleteTextDisabled: {
    color: colors.muted,
  },
});
