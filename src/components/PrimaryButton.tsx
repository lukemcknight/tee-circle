import React from 'react';
import { Pressable, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { colors, radii, spacing, typography } from '../theme';

type Props = {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  style?: ViewStyle;
  variant?: 'primary' | 'secondary' | 'danger';
};

export const PrimaryButton: React.FC<Props> = ({ label, onPress, disabled, style, variant = 'primary' }) => {
  const isPrimary = variant === 'primary';
  const isDanger = variant === 'danger';

  return (
    <View style={[styles.wrapper, style, disabled && styles.disabledWrapper]}>
      <Pressable
        onPress={onPress}
        disabled={disabled}
        accessibilityRole="button"
        accessibilityLabel={label}
        accessibilityState={{ disabled }}
        style={({ pressed }) => [
          styles.button,
          isPrimary ? styles.primaryButton : isDanger ? styles.dangerButton : styles.secondaryButton,
          pressed && !disabled && styles.pressed,
          disabled && styles.disabled,
        ]}
      >
        <Text
          style={[
            styles.label,
            isPrimary ? styles.primaryLabel : isDanger ? styles.dangerLabel : styles.secondaryLabel,
            disabled && styles.disabledLabel,
          ]}
          numberOfLines={1}
          ellipsizeMode="tail"
        >
          {label}
        </Text>
      </Pressable>
    </View>
  );
};

const styles = StyleSheet.create({
  wrapper: {
    borderRadius: radii.md,
    overflow: 'hidden',
  },
  disabledWrapper: {
    opacity: 0.5,
  },
  button: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 48,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    borderRadius: radii.md,
  },
  primaryButton: {
    backgroundColor: colors.primary,
  },
  dangerButton: {
    backgroundColor: colors.error,
  },
  secondaryButton: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  disabled: {
    backgroundColor: colors.border,
  },
  pressed: {
    opacity: 0.9,
  },
  label: {
    fontSize: typography.body,
    fontWeight: '600',
    textAlign: 'center',
    flexShrink: 1,
  },
  primaryLabel: {
    color: '#FFFFFF',
  },
  dangerLabel: {
    color: '#FFFFFF',
  },
  secondaryLabel: {
    color: colors.text,
  },
  disabledLabel: {
    color: colors.muted,
  },
});
