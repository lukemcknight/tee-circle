import React, { useEffect, useState } from 'react';
import { StyleSheet, Text, TextInput, View } from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { RootStackParamList } from '../navigation/types';
import { colors, radii, spacing, typography } from '../theme';
import { PrimaryButton } from '../components/PrimaryButton';
import { BackButton } from '../components/BackButton';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import { isValidUsername, normalizeUsername } from '../utils/username';

type Props = NativeStackScreenProps<RootStackParamList, 'Username'>;

export const UsernameScreen: React.FC<Props> = ({ navigation }) => {
  const { session, profile, refreshProfile } = useAuth();
  const [username, setUsername] = useState(profile?.username ?? '');
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setUsername(profile?.username ?? '');
  }, [profile?.username]);

  const onSave = async () => {
    setError(null);
    const normalized = normalizeUsername(username);
    if (!session?.user) {
      setError('Sign in to continue.');
      return;
    }
    if (!isValidUsername(normalized)) {
      setError('Pick a username to continue.');
      return;
    }
    setSaving(true);
    const { error: updateError } = await supabase
      .from('profiles')
      .update({ username: normalized })
      .eq('id', session.user.id);

    if (updateError) {
      const isUnique = (updateError as { code?: string }).code === '23505' || updateError.message?.toLowerCase().includes('duplicate');
      if (isUnique) {
        setError('That username is taken. Try another.');
      } else {
        setError('Could not save username. Please try again.');
      }
      setSaving(false);
      return;
    }

    await refreshProfile();
    setSaving(false);
    navigation.replace('Home');
  };

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.container}>
        <BackButton onPress={() => navigation.goBack()} />
        <Text style={styles.title} numberOfLines={1}>
          Claim your username
        </Text>
        <Text style={styles.subtitle} numberOfLines={2} ellipsizeMode="tail">
          Pick a handle your friends can search for.
        </Text>

        <View style={styles.card}>
          <TextInput
            style={styles.input}
            placeholder="golfer123"
            placeholderTextColor={colors.muted}
            value={username}
            onChangeText={(value) => {
              setUsername(value);
              setError(null);
            }}
            autoCapitalize="none"
            autoCorrect={false}
          />
          {error && (
            <Text style={styles.error} numberOfLines={2}>
              {error}
            </Text>
          )}
        </View>

        <PrimaryButton label={saving ? 'Saving...' : 'Save username'} onPress={onSave} disabled={saving} />
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
    padding: spacing.lg,
    gap: spacing.md,
    flex: 1,
  },
  title: {
    fontSize: typography.title,
    fontWeight: '700',
    color: colors.text,
  },
  subtitle: {
    fontSize: typography.body,
    color: colors.muted,
  },
  card: {
    backgroundColor: colors.card,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.md,
    gap: spacing.sm,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radii.md,
    padding: spacing.md,
    fontSize: typography.body,
    color: colors.text,
    backgroundColor: colors.background,
  },
  error: {
    color: colors.error,
    fontWeight: '600',
    fontSize: typography.small,
  },
});
