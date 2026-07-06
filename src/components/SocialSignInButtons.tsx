import React, { useEffect, useState } from 'react';
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import * as AppleAuthentication from 'expo-apple-authentication';
import { Ionicons } from '@expo/vector-icons';

type Props = {
  onApple: () => void;
  onGoogle: () => void;
  disabled?: boolean;
};

export const SocialSignInButtons: React.FC<Props> = ({ onApple, onGoogle, disabled }) => {
  const [appleAvailable, setAppleAvailable] = useState(false);

  useEffect(() => {
    let isMounted = true;
    if (Platform.OS === 'ios') {
      AppleAuthentication.isAvailableAsync()
        .then((available) => {
          if (isMounted) setAppleAvailable(available);
        })
        .catch(() => {});
    }
    return () => {
      isMounted = false;
    };
  }, []);

  return (
    <View style={styles.container} pointerEvents={disabled ? 'none' : 'auto'}>
      {appleAvailable && (
        <AppleAuthentication.AppleAuthenticationButton
          buttonType={AppleAuthentication.AppleAuthenticationButtonType.SIGN_IN}
          buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.WHITE}
          cornerRadius={9999}
          style={styles.appleButton}
          onPress={onApple}
        />
      )}
      <Pressable
        style={({ pressed }) => [
          styles.googleButton,
          pressed && styles.googleButtonPressed,
          disabled && styles.buttonDisabled,
        ]}
        onPress={onGoogle}
        disabled={disabled}
        accessibilityRole="button"
        accessibilityLabel="Continue with Google"
      >
        <Ionicons name="logo-google" size={20} color="#1f1f1f" />
        <Text style={styles.googleButtonText}>Continue with Google</Text>
      </Pressable>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  appleButton: {
    height: 52,
    width: '100%',
  },
  googleButton: {
    height: 52,
    borderRadius: 9999,
    backgroundColor: '#ffffff',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
  },
  googleButtonPressed: {
    opacity: 0.85,
  },
  buttonDisabled: {
    opacity: 0.7,
  },
  googleButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1f1f1f',
  },
});
