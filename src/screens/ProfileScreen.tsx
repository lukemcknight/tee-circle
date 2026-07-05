import React, { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { LinearGradient } from 'expo-linear-gradient';
import { RootStackParamList } from '../navigation/types';
import { BottomNavBar } from '../components/BottomNavBar';
import { cardShadow, colors, radii, spacing, typography } from '../theme';
import { useAuth } from '../context/AuthContext';
import { useRounds } from '../hooks/useRounds';
import { useFriendships } from '../hooks/useFriendships';
import { useHandicap } from '../hooks/useHandicap';
import { getProfileHandle, getProfileName } from '../utils/profile';

type Props = NativeStackScreenProps<RootStackParamList, 'Profile'>;

const getInitials = (name: string | null | undefined) => {
  if (!name) return '?';
  const parts = name.trim().split(/\s+/).slice(0, 2);
  return parts.map((p) => p[0]).join('').toUpperCase() || '?';
};

export const ProfileScreen: React.FC<Props> = ({ navigation }) => {
  const { user, profile, signOut, deleteProfile } = useAuth();
  const { rounds } = useRounds();
  const { accepted } = useFriendships();
  const { profile: handicapProfile, differentials } = useHandicap();
  const [deleting, setDeleting] = useState(false);
  const insets = useSafeAreaInsets();
  const bottomPadding = Math.max(insets.bottom, spacing.md);
  const handle = getProfileHandle(profile) ?? '@Golfer';
  const displayName = getProfileName(profile);
  const initials = getInitials(displayName || handle);
  const memberSinceYear = user?.created_at ? new Date(user.created_at).getFullYear() : null;
  const memberSinceLabel = memberSinceYear ? `Member since ${memberSinceYear}` : 'Member since 2024';

  const handleSignOut = async () => {
    await signOut();
  };

  const handleDeleteProfile = async () => {
    if (deleting) return;
    setDeleting(true);
    const success = await deleteProfile();
    if (!success) {
      setDeleting(false);
      Alert.alert('Unable to delete account', 'Something went wrong. Please try again.');
    }
  };

  const confirmDeleteProfile = () => {
    Alert.alert(
      'Delete account?',
      'This will permanently delete your profile, friendships, groups, and rounds. This action cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: handleDeleteProfile },
      ],
    );
  };

  return (
    <SafeAreaView style={styles.safe} edges={['top', 'left', 'right']}>
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title} numberOfLines={1}>
            Profile
          </Text>
        </View>

        <ScrollView
          contentContainerStyle={[styles.scrollContent, { paddingBottom: 96 + bottomPadding + spacing.xl }]}
        >
          <View style={styles.content}>
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
              <Text style={styles.handleText} numberOfLines={1}>
                {handle}
              </Text>
              <Text style={styles.memberText}>{memberSinceLabel}</Text>
            </View>

            {/* Stats row */}
            <View style={styles.statsRow}>
              <View style={styles.statCard}>
                <Text style={styles.statNumber}>{rounds.length}</Text>
                <Text style={styles.statLabel}>Rounds</Text>
              </View>
              <View style={styles.statCard}>
                <Text style={styles.statNumber}>{accepted.length}</Text>
                <Text style={styles.statLabel}>Friends</Text>
              </View>
            </View>

            <View style={styles.spacer} />

            <View style={styles.panel}>
              <View style={styles.panelHeader}>
                <Text style={styles.panelTitle}>Handicap Snapshot</Text>
                <Text style={styles.handicapValue}>
                  {handicapProfile?.handicapIndex !== null && handicapProfile?.handicapIndex !== undefined
                    ? handicapProfile.handicapIndex.toFixed(1)
                    : '--'}
                </Text>
              </View>
              <Text style={styles.panelSubtitle}>
                {handicapProfile?.roundsCount
                  ? `${handicapProfile.roundsCount} posted round${handicapProfile.roundsCount === 1 ? '' : 's'}`
                  : 'Post your first score to establish a TeeCircle handicap.'}
              </Text>
              {differentials.length > 0 && (
                <Text style={styles.handicapTrend}>
                  Recent differentials: {differentials.slice(0, 3).map((item) => item.differential.toFixed(1)).join(' · ')}
                </Text>
              )}
            </View>

            <View style={styles.spacer} />

            <View style={styles.panel}>
              <View style={styles.panelRow}>
                <View style={styles.panelIcon}>
                  <Text style={styles.panelIconText}>✎</Text>
                </View>
                <View style={styles.panelText}>
                  <Text style={styles.panelTitle}>Edit Username</Text>
                  <Text style={styles.panelSubtitle}>Change your display name</Text>
                </View>
                <Pressable
                  style={({ pressed }) => [styles.panelButton, pressed && styles.panelButtonPressed]}
                  onPress={() => navigation.navigate('Username')}
                  disabled={deleting}
                  accessibilityRole="button"
                  accessibilityLabel="Edit username"
                >
                  <Text style={styles.panelButtonText}>Edit</Text>
                </Pressable>
              </View>
            </View>

            <View style={styles.spacer} />

            <Pressable
              style={({ pressed }) => [styles.logoutButton, pressed && styles.logoutButtonPressed]}
              onPress={handleSignOut}
              disabled={deleting}
              accessibilityRole="button"
              accessibilityLabel="Log out"
            >
              <View style={styles.logoutContent}>
                <Text style={styles.logoutIcon}>⎋</Text>
                <Text style={styles.logoutText}>Log Out</Text>
              </View>
              <Text style={styles.logoutChevron}>›</Text>
            </Pressable>

            <View style={styles.footer}>
              <Pressable
                style={({ pressed }) => [styles.deleteButton, pressed && styles.deleteButtonPressed]}
                onPress={confirmDeleteProfile}
                disabled={deleting}
                accessibilityRole="button"
                accessibilityLabel="Delete account"
              >
                <Text style={styles.deleteIcon}>⌫</Text>
                <Text style={styles.deleteText}>
                  {deleting ? 'Deleting account...' : 'Delete Account'}
                </Text>
              </Pressable>
              <Text style={styles.versionText}>TeeCircle v1.0</Text>
            </View>
          </View>
        </ScrollView>

        <BottomNavBar
          activeTab="Profile"
          onNavigate={(tab) => {
            if (tab === 'Schedule') navigation.navigate('Home');
            else if (tab === 'Friends') navigation.navigate('Friends');
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
    paddingBottom: spacing.sm,
  },
  title: {
    fontSize: typography.subtitle,
    fontWeight: '700',
    color: colors.text,
  },
  scrollContent: {
    paddingHorizontal: spacing.lg,
    flexGrow: 1,
  },
  content: {
    flexGrow: 1,
    paddingTop: spacing.md,
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
  handleText: {
    fontSize: 26,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: -0.4,
    textAlign: 'center',
  },
  memberText: {
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
  panelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  panelHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.md,
    marginBottom: spacing.xs,
  },
  panelIcon: {
    width: 40,
    height: 40,
    borderRadius: 999,
    backgroundColor: 'rgba(19, 236, 91, 0.16)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  panelIconText: {
    fontSize: 18,
    color: colors.secondary,
  },
  panelText: {
    flex: 1,
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
  handicapTrend: {
    marginTop: spacing.sm,
    fontSize: typography.small,
    color: colors.muted,
  },
  panelButton: {
    height: 36,
    paddingHorizontal: spacing.md,
    borderRadius: radii.sm,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  panelButtonPressed: {
    backgroundColor: colors.primaryDark,
  },
  panelButtonText: {
    fontSize: typography.small,
    fontWeight: '700',
    color: colors.text,
  },
  logoutButton: {
    height: 56,
    borderRadius: radii.lg,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.surfaceGreen,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  logoutButtonPressed: {
    backgroundColor: colors.surfaceGreenPressed,
  },
  logoutContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  logoutIcon: {
    fontSize: 18,
    color: colors.textSecondary,
  },
  logoutText: {
    fontSize: typography.body,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: 0.2,
  },
  logoutChevron: {
    fontSize: 18,
    color: colors.textSecondary,
  },
  footer: {
    marginTop: 'auto',
    alignItems: 'center',
    paddingTop: spacing.xl,
    paddingBottom: spacing.lg,
  },
  deleteButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderRadius: radii.sm,
  },
  deleteButtonPressed: {
    backgroundColor: 'rgba(220, 38, 38, 0.08)',
  },
  deleteIcon: {
    fontSize: 18,
    color: colors.error,
  },
  deleteText: {
    fontSize: typography.small,
    fontWeight: '700',
    color: colors.error,
  },
  versionText: {
    marginTop: spacing.md,
    fontSize: 12,
    color: colors.muted,
    fontWeight: '600',
  },
});
