import React, { useState } from 'react';
import { StyleSheet, Text, TextInput, TextInputProps, View } from 'react-native';
import { colors, darkColors } from '../theme';

type Props = TextInputProps & {
  label: string;
  rightIcon?: React.ReactNode;
};

// Glassy labeled text input for the dark auth flow.
export const GlassInput: React.FC<Props> = ({
  label,
  rightIcon,
  style,
  onFocus,
  onBlur,
  ...inputProps
}) => {
  const [focused, setFocused] = useState(false);

  return (
    <View style={styles.group}>
      <Text style={styles.label}>{label}</Text>
      <View style={styles.wrapper}>
        <TextInput
          style={[styles.input, rightIcon != null && styles.inputWithIcon, focused && styles.inputFocused, style]}
          placeholderTextColor={darkColors.placeholder}
          selectionColor={colors.primary}
          keyboardAppearance="dark"
          onFocus={(e) => {
            setFocused(true);
            onFocus?.(e);
          }}
          onBlur={(e) => {
            setFocused(false);
            onBlur?.(e);
          }}
          {...inputProps}
        />
        {rightIcon != null && <View style={styles.rightIcon}>{rightIcon}</View>}
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  group: {
    gap: 8,
  },
  label: {
    fontSize: 11,
    fontWeight: '600',
    color: darkColors.textSecondary,
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginLeft: 4,
  },
  wrapper: {
    position: 'relative',
  },
  input: {
    height: 56,
    backgroundColor: darkColors.glassSurface,
    borderWidth: 1,
    borderColor: darkColors.glassBorder,
    borderRadius: 16,
    paddingHorizontal: 16,
    fontSize: 16,
    fontWeight: '500',
    color: darkColors.text,
  },
  inputFocused: {
    borderColor: darkColors.glassBorderFocused,
  },
  inputWithIcon: {
    paddingRight: 50,
  },
  rightIcon: {
    position: 'absolute',
    right: 16,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
  },
});
