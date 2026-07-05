import React from 'react';
import { Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { colors, spacing, typography } from '../theme';

type Props = { children: React.ReactNode };
type State = { error: Error | null };

const ENV_KEYS_TO_CHECK = [
  'EXPO_PUBLIC_SUPABASE_URL',
  'EXPO_PUBLIC_SUPABASE_ANON_KEY',
  'EXPO_PUBLIC_GOOGLE_PLACES_API_KEY',
  'EXPO_PUBLIC_POSTHOG_API_KEY',
];

const envPresence = () =>
  ENV_KEYS_TO_CHECK.map((k) => `${k}: ${process.env[k] ? 'set' : 'missing'}`).join('\n');

export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    // eslint-disable-next-line no-console
    console.error('[ErrorBoundary]', error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;

    return (
      <View style={styles.root}>
        <ScrollView contentContainerStyle={styles.content}>
          <Text style={styles.title}>Something went wrong</Text>
          <Text style={styles.subtitle}>The app hit an error while starting up.</Text>

          <Text style={styles.sectionLabel}>Error</Text>
          <Text style={styles.mono}>{error.message || String(error)}</Text>

          {error.stack ? (
            <>
              <Text style={styles.sectionLabel}>Stack</Text>
              <Text style={styles.mono}>{error.stack}</Text>
            </>
          ) : null}

          <Text style={styles.sectionLabel}>Environment</Text>
          <Text style={styles.mono}>{envPresence()}</Text>

          <Text style={styles.sectionLabel}>Runtime</Text>
          <Text style={styles.mono}>
            {`Platform: ${Platform.OS} ${Platform.Version}\n__DEV__: ${__DEV__ ? 'true' : 'false'}`}
          </Text>
        </ScrollView>
      </View>
    );
  }
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: spacing.lg,
    paddingTop: spacing.xl * 2,
  },
  title: {
    fontSize: typography.title,
    fontWeight: '800',
    color: colors.text,
    marginBottom: spacing.xs,
  },
  subtitle: {
    fontSize: typography.small,
    color: colors.muted,
    marginBottom: spacing.lg,
  },
  sectionLabel: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    color: colors.muted,
    marginTop: spacing.lg,
    marginBottom: spacing.xs,
  },
  mono: {
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    fontSize: 12,
    color: colors.text,
    backgroundColor: colors.card,
    padding: spacing.sm,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
  },
});
