import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { colors, radii, spacing, typography } from '../theme';

type Props = {
  status: 'Open' | 'Locked';
};

export const StatusBadge: React.FC<Props> = ({ status }) => {
  const isLocked = status === 'Locked';
  return (
    <View style={[styles.container, isLocked ? styles.locked : styles.open]}>
      <Text style={[styles.text, isLocked ? styles.lockedText : styles.openText]} numberOfLines={1}>
        {status}
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    paddingVertical: spacing.xs / 2,
    paddingHorizontal: spacing.sm,
    borderRadius: radii.lg,
    borderWidth: 1,
  },
  open: {
    backgroundColor: 'rgba(124, 203, 138, 0.15)',
    borderColor: colors.primary,
  },
  locked: {
    backgroundColor: 'rgba(107, 114, 128, 0.1)',
    borderColor: colors.muted,
  },
  text: {
    fontWeight: '600',
    fontSize: typography.small,
  },
  openText: {
    color: colors.secondary,
  },
  lockedText: {
    color: colors.muted,
  },
});
