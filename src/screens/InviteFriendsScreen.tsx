import React, { useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, typography } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useRounds } from '../hooks/useRounds';
import { useData } from '../context/DataContext';
import { useFriendships } from '../hooks/useFriendships';
import { useStoreReview } from '../hooks/useStoreReview';
import { useRoundResponses } from '../hooks/useRoundResponses';
import { getProfileHandle, getProfileName } from '../utils/profile';

type Props = NativeStackScreenProps<RootStackParamList, 'InviteFriends'>;

export const InviteFriendsScreen: React.FC<Props> = ({ route, navigation }) => {
  const { rounds, refresh, loading: roundsLoading } = useRounds();
  const { accepted, loading: friendsLoading } = useFriendships();
  const { inviteFriendToRound } = useData();
  const { trackFriendsInvited } = useStoreReview();
  const { responses, refresh: refreshResponses } = useRoundResponses(route.params.roundId);
  const round = useMemo(
    () => route.params.initialRound ?? rounds.find((r) => r.id === route.params.roundId),
    [rounds, route.params.roundId, route.params.initialRound]
  );
  const [search, setSearch] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [sending, setSending] = useState(false);

  const invitedIds = useMemo(() => {
    if (!round) return new Set<string>();
    if (responses.length) {
      return new Set(responses.map((resp) => resp.userId));
    }
    return new Set(round.invites.map((p) => p.id));
  }, [round, responses]);

  const filteredFriends = useMemo(() => {
    return accepted.filter((friend) => {
      if (!friend.profile) return false;
      // Don't show already invited friends
      if (invitedIds.has(friend.otherUserId)) return false;
      const username = friend.profile?.username ?? '';
      const fullName = friend.profile?.full_name ?? '';
      const searchLower = search.toLowerCase();
      return (
        username.toLowerCase().includes(searchLower) ||
        fullName.toLowerCase().includes(searchLower)
      );
    });
  }, [accepted, search, invitedIds]);

  const toggleSelection = (friendId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(friendId)) {
        next.delete(friendId);
      } else {
        next.add(friendId);
      }
      return next;
    });
  };

  const selectAll = () => {
    const allIds = filteredFriends.map((f) => f.otherUserId);
    setSelectedIds(new Set(allIds));
  };

  const sendInvites = async () => {
    if (!round || selectedIds.size === 0 || sending) return;
    setSending(true);

    for (const friendId of selectedIds) {
      await inviteFriendToRound(round.id, friendId);
    }

    await refreshResponses();
    await refresh();
    setSending(false);
    setSelectedIds(new Set());
    trackFriendsInvited();
    navigation.goBack();
  };

  if ((!route.params.initialRound && roundsLoading) || friendsLoading) {
    return (
      <View style={styles.container}>
        <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
          <View style={styles.header}>
            <Pressable onPress={() => navigation.goBack()} style={styles.backButton}>
              <Text style={styles.backIcon}>‹</Text>
            </Pressable>
            <Text style={styles.headerTitle}>Invite Friends</Text>
            <View style={styles.headerRight} />
          </View>
        </SafeAreaView>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      </View>
    );
  }

  if (!round) {
    return (
      <View style={styles.container}>
        <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
          <View style={styles.header}>
            <Pressable onPress={() => navigation.goBack()} style={styles.backButton}>
              <Text style={styles.backIcon}>‹</Text>
            </Pressable>
            <Text style={styles.headerTitle}>Invite Friends</Text>
            <View style={styles.headerRight} />
          </View>
        </SafeAreaView>
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyTitle}>Round not found</Text>
          <Text style={styles.emptyMessage}>This round may have been deleted.</Text>
        </View>
      </View>
    );
  }

  const dateTimeLabel = `${round.date} · ${round.time}`;

  return (
    <View style={styles.container}>
      {/* Header */}
      <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
        <View style={styles.header}>
          <Pressable onPress={() => navigation.goBack()} style={styles.backButton}>
            <Text style={styles.backIcon}>‹</Text>
          </Pressable>
          <Text style={styles.headerTitle}>Invite Friends</Text>
          <Pressable onPress={selectAll} style={styles.headerRight}>
            <Text style={styles.selectAllText}>Select All</Text>
          </Pressable>
        </View>
      </SafeAreaView>

      {/* Search Bar */}
      <View style={styles.searchContainer}>
        <View style={styles.searchWrapper}>
          <Ionicons name="search" size={18} color={colors.muted} style={styles.searchIcon} />
          <TextInput
            style={styles.searchInput}
            placeholder="Search by name..."
            placeholderTextColor={colors.muted}
            value={search}
            onChangeText={setSearch}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </View>
      </View>

      {/* List */}
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Already Invited Section */}
        {invitedIds.size > 0 && (
          <>
            <Text style={styles.sectionHeader}>Already Invited</Text>
            {accepted
              .filter((f) => f.profile && invitedIds.has(f.otherUserId))
              .map((friend) => {
                if (!friend.profile) return null;
                const name = getProfileName(friend.profile);
                const handle = getProfileHandle(friend.profile);
                return (
                  <View key={friend.id} style={[styles.listItem, styles.listItemInvited]}>
                    <View style={styles.checkboxContainer}>
                      <View style={[styles.checkbox, styles.checkboxChecked]}>
                        <Ionicons name="checkmark" size={14} color={colors.text} />
                      </View>
                    </View>
                    <View style={styles.friendInfo}>
                      <Text style={styles.friendName}>{name || handle}</Text>
                      <Text style={styles.friendMeta}>Invited</Text>
                    </View>
                  </View>
                );
              })}
          </>
        )}

        {/* All Friends Section */}
        {filteredFriends.length > 0 && (
          <>
            <Text style={styles.sectionHeader}>All Friends</Text>
            {filteredFriends.map((friend) => {
              if (!friend.profile) return null;
              const name = getProfileName(friend.profile);
              const handle = getProfileHandle(friend.profile);
              const isSelected = selectedIds.has(friend.otherUserId);

              return (
                <Pressable
                  key={friend.id}
                  style={[styles.listItem, isSelected && styles.listItemSelected]}
                  onPress={() => toggleSelection(friend.otherUserId)}
                >
                  <View style={styles.checkboxContainer}>
                    <View style={[styles.checkbox, isSelected && styles.checkboxChecked]}>
                      {isSelected && <Ionicons name="checkmark" size={14} color={colors.text} />}
                    </View>
                  </View>
                  <View style={styles.friendInfo}>
                    <Text style={styles.friendName}>{name || handle}</Text>
                    {handle && name && <Text style={styles.friendMeta}>{handle}</Text>}
                  </View>
                </Pressable>
              );
            })}
          </>
        )}

        {filteredFriends.length === 0 && invitedIds.size === 0 && (
          <View style={styles.emptyState}>
            <Text style={styles.emptyStateText}>
              {search ? 'No friends match your search.' : 'No friends to invite yet.'}
            </Text>
          </View>
        )}

        <View style={styles.bottomSpacer} />
      </ScrollView>

      {/* Sticky Footer */}
      {selectedIds.size > 0 && (
        <SafeAreaView edges={['bottom']} style={styles.footerSafeArea}>
          <View style={styles.footer}>
            <View style={styles.footerPill}>
              <View style={styles.footerInfo}>
                <Text style={styles.footerCount}>{selectedIds.size} Selected</Text>
                <Text style={styles.footerDate}>{dateTimeLabel}</Text>
              </View>
              <Pressable
                style={({ pressed }) => [
                  styles.sendButton,
                  pressed && styles.sendButtonPressed,
                  sending && styles.sendButtonDisabled,
                ]}
                onPress={sendInvites}
                disabled={sending}
              >
                <Text style={styles.sendButtonText}>
                  {sending ? 'Sending...' : 'Send Invites'}
                </Text>
                {!sending && <Ionicons name="paper-plane" size={14} color={colors.text} />}
              </Pressable>
            </View>
          </View>
        </SafeAreaView>
      )}
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
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingTop: 24,
    paddingBottom: 8,
  },
  backButton: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 20,
  },
  backIcon: {
    fontSize: 32,
    fontWeight: '300',
    color: colors.text,
    marginTop: -4,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
    flex: 1,
    textAlign: 'center',
  },
  headerRight: {
    minWidth: 80,
    alignItems: 'flex-end',
  },
  selectAllText: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.primary,
  },
  searchContainer: {
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  searchWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 48,
    backgroundColor: colors.card,
    borderRadius: 24,
    paddingHorizontal: 16,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  searchIcon: {
    fontSize: 18,
    marginRight: 12,
    opacity: 0.5,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: colors.text,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  sectionHeader: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginTop: 16,
    marginBottom: 8,
    marginLeft: 8,
  },
  listItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
    backgroundColor: colors.card,
    paddingHorizontal: 16,
    paddingVertical: 12,
    marginBottom: 8,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'transparent',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  listItemSelected: {
    borderColor: 'rgba(19, 236, 91, 0.3)',
  },
  listItemInvited: {
    borderColor: 'rgba(19, 236, 91, 0.3)',
    opacity: 0.7,
  },
  checkboxContainer: {
    width: 24,
    height: 24,
  },
  checkbox: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#D1D5DB',
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkboxChecked: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  checkmark: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.text,
  },
  friendInfo: {
    flex: 1,
  },
  friendName: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.text,
  },
  friendMeta: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.muted,
    marginTop: 2,
  },
  emptyState: {
    paddingVertical: 48,
    alignItems: 'center',
  },
  emptyStateText: {
    color: colors.muted,
    fontSize: 16,
    textAlign: 'center',
  },
  bottomSpacer: {
    height: 120,
  },
  footerSafeArea: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
  },
  footer: {
    padding: 16,
    paddingBottom: 24,
    alignItems: 'center',
  },
  footerPill: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
    maxWidth: 480,
    backgroundColor: colors.card,
    borderRadius: 9999,
    borderWidth: 1,
    borderColor: colors.border,
    paddingLeft: 24,
    paddingRight: 8,
    paddingVertical: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.12,
    shadowRadius: 30,
    elevation: 8,
  },
  footerInfo: {
    flex: 1,
  },
  footerCount: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.text,
  },
  footerDate: {
    fontSize: 12,
    fontWeight: '500',
    color: colors.muted,
  },
  sendButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    height: 40,
    paddingHorizontal: 24,
    backgroundColor: colors.primary,
    borderRadius: 9999,
    gap: 8,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 12,
    elevation: 2,
  },
  sendButtonPressed: {
    opacity: 0.9,
    transform: [{ scale: 0.95 }],
  },
  sendButtonDisabled: {
    opacity: 0.7,
  },
  sendButtonText: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.text,
  },
  sendIcon: {
    fontSize: 14,
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
    paddingHorizontal: 24,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
    marginBottom: 8,
  },
  emptyMessage: {
    fontSize: 16,
    color: colors.muted,
    textAlign: 'center',
  },
});
