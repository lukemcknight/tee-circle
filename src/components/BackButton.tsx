import React from 'react';
import { Pressable, StyleSheet, Text, ViewStyle } from 'react-native';
import { colors, spacing, typography } from '../theme';

type Props = {
  onPress: () => void;
  style?: ViewStyle;
};

export const BackButton: React.FC<Props> = ({ onPress, style }) => {
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel="Go back"
      style={({ pressed }) => [styles.button, pressed && styles.pressed, style]}
    >
      <Text style={styles.icon} numberOfLines={1}>
        ←
      </Text>
    </Pressable>
  );
};

const styles = StyleSheet.create({
  button: {
    width: 40,
    height: 40,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.card,
    alignItems: 'center',
    justifyContent: 'center',
    alignSelf: 'flex-start',
  },
  pressed: {
    opacity: 0.8,
  },
  icon: {
    color: colors.text,
    fontSize: typography.subtitle,
    fontWeight: '600',
  },
});
