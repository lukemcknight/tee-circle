import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { RootStackParamList } from '../navigation/types';
import { BottomNavBar } from '../components/BottomNavBar';
import { cardShadow, colors, radii, spacing, typography } from '../theme';
import { useFriendships } from '../hooks/useFriendships';
import { supabase } from '../lib/supabase';
import { normalizeUsername, isValidUsername } from '../utils/username';
import { PrimaryButton } from '../components/PrimaryButton';
import { getProfileHandle, getProfileName } from '../utils/profile';

type Props = NativeStackScreenProps<RootStackParamList, 'Friends'>;

const PulsingDot: React.FC<{ style: object }> = ({ style }) => {
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    const animation = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0.4, duration: 800, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 1, duration: 800, useNativeDriver: true }),
      ]),
    );
    animation.start();
    return () => animation.stop();
  }, [opacity]);

  return <Animated.View style={[style, { opacity }]} />;
};

const GradientAvatar: React.FC<{ initials: string; muted?: boolean }> = ({ initials, muted }) => (
  <View style={styles.avatar}>
    <LinearGradient
      colors={muted ? [colors.surfaceGreen, colors.borderGreen] : [colors.primary, colors.primaryDark]}
      style={StyleSheet.absoluteFillObject}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
    />
    <Text style={styles.avatarText}>{initials}</Text>
  </View>
);

export const FriendsScreen: React.FC<Props> = ({ navigation }) => {
  const { incoming, outgoing, accepted, loading, refresh } = useFriendships();
  const [usernameInput, setUsernameInput] = useState('');
  const [feedback, setFeedback] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [accepting, setAccepting] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const insets = useSafeAreaInsets();
  const bottomNavPadding = Math.max(insets.bottom, spacing.md);

  const sortedAccepted = useMemo(
    () =>
      [...accepted].sort((a, b) => (a.profile?.username || '').localeCompare(b.profile?.username || '')),
    [accepted],
  );

  const filteredAccepted = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) return sortedAccepted;
    return sortedAccepted.filter((friend) => {
      const name = getProfileName(friend.profile || {});
      const handle = getProfileHandle(friend.profile || {});
      return `${name ?? ''} ${handle ?? ''}`.toLowerCase().includes(query);
    });
  }, [searchQuery, sortedAccepted]);

  const recentAccepted = filteredAccepted.slice(0, 3);
  const remainingAccepted = filteredAccepted.slice(3);

  const getInitials = (displayName: string) => {
    const parts = displayName.trim().split(/\s+/).slice(0, 2);
    const initials = parts.map((part) => part[0]).join('');
    return initials.toUpperCase();
  };

  const handleSend = async () => {
    setFeedback(null);
    setError(null);
    const normalized = normalizeUsername(usernameInput);
    if (!isValidUsername(normalized)) {
      setError('Enter a valid username.');
      return;
    }
    setSending(true);
    const { data, error: rpcError } = await supabase.rpc('send_friend_request_by_username', {
      p_username: normalized,
    });
    setSending(false);

    if (rpcError) {
      setError('Could not send request. Try again.');
      return;
    }

    if (!data) {
      setError('User not found.');
      return;
    }

    setFeedback('Request sent.');
    setUsernameInput('');
    await refresh();
  };

  const handleAccept = async (friendshipId: string) => {
    setAccepting(friendshipId);
    setFeedback(null);
    setError(null);
    const { data, error: rpcError } = await supabase.rpc('accept_friend_request', {
      p_friendship_id: friendshipId,
    });
    setAccepting(null);

    if (rpcError || !data) {
      setError('Could not accept right now.');
      return;
    }

    await refresh();
    setFeedback('Friend added.');
  };

  return (
    <SafeAreaView style={styles.safe} edges={['top', 'left', 'right']}>
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title} numberOfLines={1}>
            My Golfers
          </Text>
        </View>

        <View style={styles.searchBar}>
          <TextInput
            style={styles.searchInput}
            placeholder="Search by name..."
            placeholderTextColor={colors.muted}
            value={searchQuery}
            onChangeText={setSearchQuery}
            autoCapitalize="words"
            autoCorrect={false}
          />
        </View>

        <ScrollView contentContainerStyle={[styles.scrollContent, { paddingBottom: 96 + bottomNavPadding + spacing.xl }]} keyboardShouldPersistTaps="handled">
          <View style={styles.card}>
            <Text style={styles.sectionTitle} numberOfLines={1}>
              Add friend
            </Text>
            <Text style={styles.helper} numberOfLines={2}>
              Search by username. Requests are pending until accepted.
            </Text>
            <TextInput
              style={styles.input}
              placeholder="golfer123"
              placeholderTextColor={colors.muted}
              value={usernameInput}
              onChangeText={(value) => {
                setUsernameInput(value);
                setError(null);
                setFeedback(null);
              }}
              autoCapitalize="none"
              autoCorrect={false}
            />
            <PrimaryButton label={sending ? 'Sending...' : 'Send request'} onPress={handleSend} disabled={sending} />
            {feedback && (
              <Text style={styles.success} numberOfLines={1}>
                {feedback}
              </Text>
            )}
            {error && (
              <Text style={styles.error} numberOfLines={2}>
                {error}
              </Text>
            )}
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionLabel} numberOfLines={1}>
              Requests
            </Text>
          </View>
          <View style={styles.listGroup}>
            {loading && (
              <View style={styles.loadingRow}>
                <ActivityIndicator size="small" color={colors.accent} />
              </View>
            )}
            {!loading && incoming.length === 0 && outgoing.length === 0 && (
              <Text style={styles.helper} numberOfLines={1}>
                No pending requests.
              </Text>
            )}
            {!loading &&
              incoming.map((req) => {
                if (!req.profile) return null;
                const handle = getProfileHandle(req.profile);
                const name = getProfileName(req.profile);
                const displayName = name || handle;
                if (!displayName) return null;
                const secondary = handle && handle !== displayName ? handle : null;
                const initials = getInitials(displayName);
                return (
                  <View key={req.id} style={styles.friendCard}>
                    <View style={styles.avatarWrap}>
                      <GradientAvatar initials={initials} />
                      <PulsingDot style={[styles.statusDot, styles.statusPending]} />
                    </View>
                    <View style={styles.userInfo}>
                      <Text style={styles.userName} numberOfLines={1} ellipsizeMode="tail">
                        {displayName}
                      </Text>
                      {secondary && (
                        <Text style={styles.userHandle} numberOfLines={1} ellipsizeMode="tail">
                          {secondary}
                        </Text>
                      )}
                    </View>
                    <Pressable
                      onPress={() => handleAccept(req.id)}
                      disabled={accepting === req.id}
                      style={[styles.acceptButton, accepting === req.id && styles.acceptButtonDisabled]}
                    >
                      <Text style={styles.acceptText} numberOfLines={1}>
                        {accepting === req.id ? 'Accepting...' : 'Accept'}
                      </Text>
                    </Pressable>
                  </View>
                );
              })}
            {!loading && outgoing.length > 0 && (
              <View style={styles.outgoingSection}>
                <Text style={styles.helper} numberOfLines={1}>
                  Sent requests
                </Text>
                {outgoing.map((req) => {
                  if (!req.profile) return null;
                  const handle = getProfileHandle(req.profile);
                  const name = getProfileName(req.profile);
                  const displayName = name || handle;
                  if (!displayName) return null;
                  const secondary = handle && handle !== displayName ? handle : null;
                  const initials = getInitials(displayName);
                  return (
                    <View key={req.id} style={styles.friendCard}>
                      <View style={styles.avatarWrap}>
                        <GradientAvatar initials={initials} muted />
                        <View style={[styles.statusDot, styles.statusMuted]} />
                      </View>
                      <View style={styles.userInfo}>
                        <Text style={styles.userName} numberOfLines={1} ellipsizeMode="tail">
                          {displayName}
                        </Text>
                        {secondary && (
                          <Text style={styles.userHandle} numberOfLines={1} ellipsizeMode="tail">
                            {secondary}
                          </Text>
                        )}
                      </View>
                      <View style={styles.statusBadge}>
                        <Text style={styles.statusText} numberOfLines={1}>
                          Pending
                        </Text>
                      </View>
                    </View>
                  );
                })}
              </View>
            )}
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionLabel} numberOfLines={1}>
              Recently active
            </Text>
          </View>
          <View style={styles.listGroup}>
            {loading && (
              <View style={styles.loadingRow}>
                <ActivityIndicator size="small" color={colors.accent} />
              </View>
            )}
            {!loading && recentAccepted.length === 0 && (
              <View style={styles.emptyContainer}>
                <Ionicons name="people-outline" size={48} color={colors.primaryLight} style={styles.emptyIcon} />
                <Text style={styles.emptyTitle} numberOfLines={1}>
                  Your circle is empty
                </Text>
                <Text style={styles.helper} numberOfLines={2}>
                  Add friends by username to start planning rounds together.
                </Text>
              </View>
            )}
            {!loading &&
              recentAccepted.map((friend) => {
                if (!friend.profile) return null;
                const handle = getProfileHandle(friend.profile);
                const name = getProfileName(friend.profile);
                const displayName = name || handle;
                if (!displayName) return null;
                const secondary = handle && handle !== displayName ? handle : null;
                const initials = getInitials(displayName);
                return (
                  <Pressable
                    key={friend.id}
                    style={({ pressed }) => [styles.friendCard, pressed && styles.friendCardPressed]}
                    onPress={() =>
                      navigation.navigate('FriendDetail', {
                        friendId: friend.otherUserId,
                        friendName: displayName,
                        friendHandle: secondary ?? undefined,
                      })
                    }
                    accessibilityRole="button"
                    accessibilityLabel={`View ${displayName}'s stats`}
                  >
                    <View style={styles.avatarWrap}>
                      <GradientAvatar initials={initials} />
                      <View style={[styles.statusDot, styles.statusActive]} />
                    </View>
                    <View style={styles.userInfo}>
                      <Text style={styles.userName} numberOfLines={1} ellipsizeMode="tail">
                        {displayName}
                      </Text>
                      {secondary && (
                        <Text style={styles.userHandle} numberOfLines={1} ellipsizeMode="tail">
                          {secondary}
                        </Text>
                      )}
                    </View>
                    <Text style={styles.chevron} numberOfLines={1}>
                      &gt;
                    </Text>
                  </Pressable>
                );
              })}
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionLabel} numberOfLines={1}>
              All friends
            </Text>
          </View>
          <View style={styles.listGroup}>
            {loading && (
              <View style={styles.loadingRow}>
                <ActivityIndicator size="small" color={colors.accent} />
              </View>
            )}
            {!loading && remainingAccepted.length === 0 && filteredAccepted.length > 0 && (
              <Text style={styles.helper} numberOfLines={1}>
                No more friends to show.
              </Text>
            )}
            {!loading &&
              remainingAccepted.map((friend) => {
                if (!friend.profile) return null;
                const handle = getProfileHandle(friend.profile);
                const name = getProfileName(friend.profile);
                const displayName = name || handle;
                if (!displayName) return null;
                const secondary = handle && handle !== displayName ? handle : null;
                const initials = getInitials(displayName);
                return (
                  <Pressable
                    key={friend.id}
                    style={({ pressed }) => [styles.friendCard, pressed && styles.friendCardPressed]}
                    onPress={() =>
                      navigation.navigate('FriendDetail', {
                        friendId: friend.otherUserId,
                        friendName: displayName,
                        friendHandle: secondary ?? undefined,
                      })
                    }
                    accessibilityRole="button"
                    accessibilityLabel={`View ${displayName}'s stats`}
                  >
                    <View style={styles.avatarWrap}>
                      <GradientAvatar initials={initials} muted />
                    </View>
                    <View style={styles.userInfo}>
                      <Text style={styles.userName} numberOfLines={1} ellipsizeMode="tail">
                        {displayName}
                      </Text>
                      {secondary && (
                        <Text style={styles.userHandle} numberOfLines={1} ellipsizeMode="tail">
                          {secondary}
                        </Text>
                      )}
                    </View>
                    <Text style={styles.chevron} numberOfLines={1}>
                      &gt;
                    </Text>
                  </Pressable>
                );
              })}
          </View>
        </ScrollView>

        <BottomNavBar
          activeTab="Friends"
          onNavigate={(tab) => {
            if (tab === 'Schedule') navigation.navigate('Home');
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
    backgroundColor: colors.background,
  },
  header: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.sm,
  },
  title: {
    fontSize: typography.title,
    fontWeight: '800',
    color: colors.text,
  },
  searchBar: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
  },
  searchInput: {
    borderRadius: 999,
    backgroundColor: colors.card,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    fontSize: typography.body,
    color: colors.text,
    ...cardShadow,
  },
  scrollContent: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xl,
    gap: spacing.lg,
  },
  card: {
    borderRadius: radii.xl,
    backgroundColor: colors.card,
    padding: spacing.md,
    gap: spacing.sm,
    ...cardShadow,
  },
  helper: {
    color: colors.muted,
    fontSize: typography.small,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 16,
    padding: spacing.md,
    fontSize: typography.body,
    color: colors.text,
    backgroundColor: colors.background,
  },
  success: {
    color: colors.secondary,
    fontWeight: '600',
    fontSize: typography.small,
  },
  error: {
    color: colors.error,
    fontWeight: '600',
    fontSize: typography.small,
  },
  sectionTitle: {
    fontSize: typography.subtitle,
    fontWeight: '600',
    color: colors.text,
  },
  sectionHeader: {
    marginTop: spacing.sm,
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  listGroup: {
    gap: spacing.sm,
  },
  friendCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radii.xl,
    backgroundColor: colors.card,
    ...cardShadow,
  },
  friendCardPressed: {
    opacity: 0.7,
  },
  avatarWrap: {
    width: 56,
    height: 56,
  },
  avatar: {
    width: 56,
    height: 56,
    borderRadius: 28,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: colors.text,
    fontWeight: '700',
    fontSize: typography.body,
  },
  emptyContainer: {
    alignItems: 'center',
    paddingVertical: spacing.xl,
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
  statusDot: {
    position: 'absolute',
    width: 12,
    height: 12,
    borderRadius: 6,
    bottom: 2,
    right: 2,
    borderWidth: 2,
    borderColor: colors.card,
  },
  statusActive: {
    backgroundColor: '#22C55E',
  },
  statusPending: {
    backgroundColor: '#F59E0B',
  },
  statusMuted: {
    backgroundColor: '#9CA3AF',
  },
  userInfo: {
    flex: 1,
    minWidth: 0,
    gap: 4,
  },
  userName: {
    fontSize: typography.body,
    color: colors.text,
    fontWeight: '700',
  },
  userHandle: {
    fontSize: typography.small,
    color: colors.muted,
  },
  acceptButton: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.md,
    borderRadius: 999,
    backgroundColor: colors.primary,
  },
  acceptButtonDisabled: {
    opacity: 0.6,
  },
  acceptText: {
    color: colors.text,
    fontWeight: '600',
    fontSize: typography.small,
  },
  statusBadge: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.md,
    borderRadius: 999,
    backgroundColor: 'rgba(107, 114, 128, 0.12)',
  },
  statusText: {
    color: colors.muted,
    fontWeight: '600',
    fontSize: typography.small,
  },
  outgoingSection: {
    gap: spacing.xs,
    marginTop: spacing.sm,
  },
  loadingRow: {
    paddingVertical: spacing.md,
    alignItems: 'center',
  },
  chevron: {
    color: colors.border,
    fontSize: 20,
    fontWeight: '700',
  },
});
