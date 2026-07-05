import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { BackButton } from '../components/BackButton';
import { PrimaryButton } from '../components/PrimaryButton';
import { colors, radii, spacing, typography } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { supabase } from '../lib/supabase';
import { getProfileHandle, getProfileName } from '../utils/profile';

type Props = NativeStackScreenProps<RootStackParamList, 'GroupMembers'>;

type MemberRow = {
  user_id: string;
  profiles: {
    full_name: string | null;
    username: string | null;
  } | null;
};

export const GroupMembersScreen: React.FC<Props> = ({ navigation, route }) => {
  const { groupId } = route.params;
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [username, setUsername] = useState('');
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const fetchMembers = useCallback(async () => {
    setLoading(true);
    setError(null);

    const { data, error: fetchError } = await supabase
      .from('group_members')
      .select('user_id, profiles(full_name, username)')
      .eq('group_id', groupId);

    if (fetchError) {
      setError('Could not load members.');
      setLoading(false);
      return;
    }

    setMembers((data as unknown as MemberRow[]) ?? []);
    setLoading(false);
  }, [groupId]);

  useEffect(() => {
    fetchMembers();
  }, [fetchMembers]);

  const onAddMember = async () => {
    const normalized = username.trim().toLowerCase();
    if (!normalized) {
      setError('Enter a username.');
      setStatus(null);
      return;
    }
    setError(null);
    setStatus(null);

    const { data, error: rpcError } = await supabase.rpc('add_member_to_group_by_username', {
      p_group_id: groupId,
      p_username: normalized,
    });

    if (rpcError) {
      setError('Could not add member.');
      return;
    }

    if (!data) {
      setError('User not found.');
      return;
    }

    setStatus('Member added.');
    setUsername('');
    await fetchMembers();
  };

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
        <View style={styles.headerRow}>
          <BackButton onPress={() => navigation.goBack()} />
          <Text style={styles.title}>Members</Text>
        </View>

        {loading ? (
          <ActivityIndicator />
        ) : (
          <View style={styles.list}>
            {members.map((member) => {
              const name = getProfileName(member.profiles);
              const handle = getProfileHandle(member.profiles);
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
            })}
            {members.length === 0 && <Text style={styles.helper}>No members yet.</Text>}
          </View>
        )}

        <View style={styles.field}>
          <Text style={styles.label}>Enter username</Text>
          <TextInput
            value={username}
            onChangeText={setUsername}
            placeholder="golfer123"
            autoCapitalize="none"
            autoCorrect={false}
            style={styles.input}
            placeholderTextColor={colors.muted}
          />
        </View>
        {error && <Text style={styles.error}>{error}</Text>}
        {status && <Text style={styles.success}>{status}</Text>}

        <PrimaryButton label="Add member" onPress={onAddMember} />
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
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  title: {
    fontSize: typography.title,
    fontWeight: '700',
    color: colors.text,
  },
  list: {
    gap: spacing.sm,
  },
  memberRow: {
    padding: spacing.md,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.background,
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
    marginTop: spacing.xs / 2,
  },
  helper: {
    color: colors.muted,
    fontSize: typography.small,
  },
  field: {
    gap: spacing.sm,
  },
  label: {
    color: colors.muted,
    fontSize: typography.body,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radii.md,
    padding: spacing.md,
    fontSize: typography.body,
    color: colors.text,
    backgroundColor: colors.card,
  },
  error: {
    color: colors.error,
    fontSize: typography.small,
  },
  success: {
    color: colors.secondary,
    fontSize: typography.small,
  },
  memberContent: {
    gap: spacing.xs / 2,
    minWidth: 0,
  },
});
