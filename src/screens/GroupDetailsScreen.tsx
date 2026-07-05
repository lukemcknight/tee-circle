import React, { useMemo } from 'react';
import { ActivityIndicator, ScrollView, StyleSheet, Text, View } from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { BackButton } from '../components/BackButton';
import { PrimaryButton } from '../components/PrimaryButton';
import { colors, radii, spacing, typography } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useGroups } from '../hooks/useGroups';
import { getProfileHandle, getProfileName } from '../utils/profile';

type Props = NativeStackScreenProps<RootStackParamList, 'GroupDetails'>;

export const GroupDetailsScreen: React.FC<Props> = ({ navigation, route }) => {
  const { groupId } = route.params;
  const { groups, loading } = useGroups();

  const group = useMemo(() => groups.find((g) => g.id === groupId), [groups, groupId]);

  if (loading) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.centered}>
          <ActivityIndicator size="large" color={colors.accent} />
        </View>
      </SafeAreaView>
    );
  }

  if (!group) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.container}>
          <BackButton onPress={() => navigation.goBack()} />
          <Text style={styles.title}>Group not found</Text>
        </View>
      </SafeAreaView>
    );
  }

  const memberCount = group.members.length;

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <BackButton onPress={() => navigation.goBack()} />
        <Text style={styles.title} numberOfLines={2} ellipsizeMode="tail">
          {group.name}
        </Text>
        <Text style={styles.subtitle} numberOfLines={1} ellipsizeMode="tail">
          {memberCount} {memberCount === 1 ? 'member' : 'members'}
        </Text>

        <View style={styles.card}>
          <Text style={styles.sectionTitle}>Members</Text>
          {group.members.length === 0 ? (
            <Text style={styles.helper}>No members yet.</Text>
          ) : (
            group.members.map((member) => {
              const name = getProfileName(member.profile);
              const handle = getProfileHandle(member.profile);
              const displayName = name || handle || 'Member';
              const secondary = handle && handle !== displayName ? handle : null;
              return (
                <View key={member.user_id} style={styles.memberRow}>
                  <View style={styles.memberContent}>
                    <Text style={styles.memberName} numberOfLines={1} ellipsizeMode="tail">
                      {displayName}
                    </Text>
                    {secondary && (
                      <Text style={styles.memberUsername} numberOfLines={1} ellipsizeMode="tail">
                        {secondary}
                      </Text>
                    )}
                  </View>
                </View>
              );
            })
          )}
        </View>

        <PrimaryButton label="Manage members" onPress={() => navigation.navigate('GroupMembers', { groupId })} />
      </ScrollView>
    </SafeAreaView>
  );
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
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
  title: {
    fontSize: typography.title,
    fontWeight: '700',
    color: colors.text,
  },
  subtitle: {
    fontSize: typography.subtitle,
    color: colors.muted,
  },
  card: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radii.md,
    backgroundColor: colors.card,
    padding: spacing.md,
    gap: spacing.sm,
  },
  sectionTitle: {
    fontSize: typography.subtitle,
    fontWeight: '700',
    color: colors.text,
  },
  helper: {
    color: colors.muted,
    fontSize: typography.small,
  },
  memberRow: {
    paddingVertical: spacing.xs,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    minWidth: 0,
  },
  memberName: {
    fontSize: typography.body,
    color: colors.text,
    fontWeight: '600',
  },
  memberUsername: {
    fontSize: typography.small,
    color: colors.muted,
  },
  memberContent: {
    gap: spacing.xs / 2,
    minWidth: 0,
  },
});
