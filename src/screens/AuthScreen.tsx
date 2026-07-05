import React, { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { colors, darkColors } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import { isValidEmail } from '../utils/validation';
import { getUsernameError } from '../utils/username';
import { AuthBackground } from '../components/AuthBackground';
import { GlassInput } from '../components/GlassInput';

type Props = NativeStackScreenProps<RootStackParamList, 'Auth'>;

export const AuthScreen: React.FC<Props> = ({ navigation, route }) => {
  const { signIn, signUp, initializing } = useAuth();
  const [authMode, setAuthMode] = useState<'login' | 'signup'>(route.params?.mode ?? 'login');
  const [identifier, setIdentifier] = useState('');
  const [loginPassword, setLoginPassword] = useState('');
  const [name, setName] = useState('');
  const [username, setUsername] = useState('');
  const [signupEmail, setSignupEmail] = useState('');
  const [signupPassword, setSignupPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [resetSent, setResetSent] = useState(false);

  // Only sync from route params when they change, not when authMode changes
  useEffect(() => {
    if (route.params?.mode) {
      setAuthMode(route.params.mode);
    }
  }, [route.params?.mode]);

  const handleLogin = async () => {
    setSubmitting(true);
    setAuthError(null);
    const email = identifier.trim();
    if (!isValidEmail(email)) {
      setAuthError('Please enter a valid email address.');
      setSubmitting(false);
      return;
    }
    const success = await signIn(email, loginPassword);
    setSubmitting(false);
    if (!success) {
      setAuthError('Could not sign in. Check your details and try again.');
    }
  };

  const handleSignup = async () => {
    setSubmitting(true);
    setAuthError(null);

    if (!isValidEmail(signupEmail)) {
      setAuthError('Please enter a valid email address.');
      setSubmitting(false);
      return;
    }

    const usernameError = getUsernameError(username);
    if (usernameError) {
      setAuthError(usernameError);
      setSubmitting(false);
      return;
    }

    if (signupPassword.length < 6) {
      setAuthError('Password must be at least 6 characters.');
      setSubmitting(false);
      return;
    }

    const success = await signUp({ name, username, email: signupEmail, password: signupPassword });
    setSubmitting(false);
    if (!success) {
      setAuthError('Could not create account. Please try again.');
    }
  };

  const handleForgotPassword = async () => {
    const email = identifier.trim();
    if (!isValidEmail(email)) {
      setAuthError('Enter your email above, then tap Forgot Password.');
      return;
    }
    setSubmitting(true);
    setAuthError(null);
    await supabase.auth.resetPasswordForEmail(email);
    setSubmitting(false);
    setResetSent(true);
  };

  const eyeToggle = (
    <Pressable onPress={() => setShowPassword(!showPassword)} hitSlop={8}>
      <Ionicons
        name={showPassword ? 'eye-off' : 'eye'}
        size={20}
        color={darkColors.textSecondary}
      />
    </Pressable>
  );

  if (initializing) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <AuthBackground>
      <StatusBar style="light" />
      <SafeAreaView edges={['top']} style={styles.flex}>
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          style={styles.flex}
        >
          <ScrollView
            contentContainerStyle={styles.scrollContent}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            {/* Brand */}
            <View style={styles.brandContainer}>
              <View style={styles.logoContainer}>
                <View style={styles.logoGlow} />
                <Image source={require('../../assets/icon.png')} style={styles.logoImage} />
              </View>
              <Text style={styles.brandName}>TeeCircle</Text>
            </View>

            {/* Headline */}
            <Text style={styles.headline}>Welcome to the Club</Text>

            {/* Toggle */}
            <View style={styles.toggleContainer}>
              <Pressable
                style={[styles.toggleButton, authMode === 'login' && styles.toggleButtonActive]}
                onPress={() => {
                  setAuthMode('login');
                  setAuthError(null);
                }}
              >
                <Text style={[styles.toggleText, authMode === 'login' && styles.toggleTextActive]}>
                  Log In
                </Text>
              </Pressable>
              <Pressable
                style={[styles.toggleButton, authMode === 'signup' && styles.toggleButtonActive]}
                onPress={() => {
                  setAuthMode('signup');
                  setAuthError(null);
                }}
              >
                <Text style={[styles.toggleText, authMode === 'signup' && styles.toggleTextActive]}>
                  Sign Up
                </Text>
              </Pressable>
            </View>

            {/* Form */}
            <View style={styles.form}>
              {authMode === 'login' ? (
                <>
                  <GlassInput
                    label="Email"
                    placeholder="birdie_king@example.com"
                    value={identifier}
                    onChangeText={(v) => {
                      setIdentifier(v);
                      setAuthError(null);
                    }}
                    autoCapitalize="none"
                    keyboardType="email-address"
                    autoComplete="email"
                  />

                  <GlassInput
                    label="Password"
                    placeholder="••••••••"
                    value={loginPassword}
                    onChangeText={(v) => {
                      setLoginPassword(v);
                      setAuthError(null);
                    }}
                    secureTextEntry={!showPassword}
                    autoComplete="password"
                    rightIcon={eyeToggle}
                  />

                  <Pressable style={styles.forgotButton} onPress={handleForgotPassword}>
                    <Text style={styles.forgotText}>Forgot Password?</Text>
                  </Pressable>
                </>
              ) : (
                <>
                  <GlassInput
                    label="Full Name"
                    placeholder="Tiger Woods"
                    value={name}
                    onChangeText={(v) => {
                      setName(v);
                      setAuthError(null);
                    }}
                    autoComplete="name"
                  />

                  <GlassInput
                    label="Username"
                    placeholder="birdie_king"
                    value={username}
                    onChangeText={(v) => {
                      setUsername(v);
                      setAuthError(null);
                    }}
                    autoCapitalize="none"
                    autoComplete="username"
                  />

                  <GlassInput
                    label="Email"
                    placeholder="birdie_king@example.com"
                    value={signupEmail}
                    onChangeText={(v) => {
                      setSignupEmail(v);
                      setAuthError(null);
                    }}
                    autoCapitalize="none"
                    keyboardType="email-address"
                    autoComplete="email"
                  />

                  <GlassInput
                    label="Password"
                    placeholder="••••••••"
                    value={signupPassword}
                    onChangeText={(v) => {
                      setSignupPassword(v);
                      setAuthError(null);
                    }}
                    secureTextEntry={!showPassword}
                    autoComplete="new-password"
                    rightIcon={eyeToggle}
                  />
                </>
              )}

              {authError && <Text style={styles.errorText}>{authError}</Text>}
              {resetSent && !authError && (
                <Text style={styles.resetSentText}>Check your email for a reset link.</Text>
              )}
            </View>

            {/* Primary Button */}
            <Pressable
              style={({ pressed }) => [
                styles.primaryButton,
                pressed && styles.primaryButtonPressed,
                submitting && styles.primaryButtonDisabled,
              ]}
              onPress={authMode === 'login' ? handleLogin : handleSignup}
              disabled={submitting}
            >
              <Text style={styles.primaryButtonText}>
                {submitting
                  ? authMode === 'login'
                    ? 'Signing in...'
                    : 'Creating account...'
                  : authMode === 'login'
                    ? 'Log In'
                    : 'Create Account'}
              </Text>
              {!submitting && <Text style={styles.buttonArrow}>→</Text>}
            </Pressable>

            {/* Social sign-in slot */}
            <View style={styles.dividerRow}>
              <View style={styles.dividerLine} />
              <Text style={styles.dividerText}>or continue with</Text>
              <View style={styles.dividerLine} />
            </View>
            <View style={styles.socialSlot}>
              {/* B3: SocialSignInButtons mount here */}
            </View>

            <Text style={styles.legalText}>
              By continuing, you agree to our Terms and Privacy Policy.
            </Text>

            <View style={styles.bottomSpacer} />
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </AuthBackground>
  );
};

const styles = StyleSheet.create({
  flex: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: darkColors.background,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: 24,
  },

  // Brand
  brandContainer: {
    alignItems: 'center',
    gap: 12,
    paddingTop: 24,
    marginBottom: 24,
  },
  logoContainer: {
    width: 64,
    height: 64,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoGlow: {
    position: 'absolute',
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: darkColors.glow,
  },
  logoImage: {
    width: 56,
    height: 56,
    borderRadius: 14,
  },
  brandName: {
    fontSize: 24,
    fontWeight: '800',
    color: darkColors.text,
    letterSpacing: -0.5,
  },

  headline: {
    fontSize: 28,
    fontWeight: '700',
    color: darkColors.text,
    textAlign: 'center',
    marginBottom: 24,
  },

  // Toggle
  toggleContainer: {
    flexDirection: 'row',
    backgroundColor: darkColors.glassSurface,
    borderWidth: 1,
    borderColor: darkColors.glassBorder,
    borderRadius: 9999,
    padding: 4,
    marginBottom: 28,
  },
  toggleButton: {
    flex: 1,
    height: 44,
    borderRadius: 9999,
    alignItems: 'center',
    justifyContent: 'center',
  },
  toggleButtonActive: {
    backgroundColor: colors.primary,
  },
  toggleText: {
    fontSize: 14,
    fontWeight: '700',
    color: darkColors.textSecondary,
  },
  toggleTextActive: {
    color: darkColors.onPrimary,
  },

  // Form
  form: {
    gap: 20,
    marginBottom: 24,
  },
  forgotButton: {
    alignSelf: 'flex-end',
    marginTop: -8,
  },
  forgotText: {
    fontSize: 14,
    fontWeight: '600',
    color: darkColors.textSecondary,
  },
  errorText: {
    fontSize: 14,
    fontWeight: '600',
    color: darkColors.error,
    textAlign: 'center',
  },
  resetSentText: {
    fontSize: 14,
    fontWeight: '600',
    color: darkColors.success,
    textAlign: 'center',
  },

  // CTA
  primaryButton: {
    height: 56,
    backgroundColor: colors.primary,
    borderRadius: 9999,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 8,
    marginBottom: 24,
  },
  primaryButtonPressed: {
    transform: [{ scale: 0.98 }],
    backgroundColor: colors.primaryDark,
  },
  primaryButtonDisabled: {
    opacity: 0.7,
  },
  primaryButtonText: {
    fontSize: 16,
    fontWeight: '700',
    color: darkColors.onPrimary,
    marginRight: 8,
  },
  buttonArrow: {
    fontSize: 20,
    fontWeight: '600',
    color: darkColors.onPrimary,
  },

  // Social slot (B3)
  dividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 16,
  },
  dividerLine: {
    flex: 1,
    height: StyleSheet.hairlineWidth,
    backgroundColor: darkColors.divider,
  },
  dividerText: {
    fontSize: 12,
    fontWeight: '600',
    color: darkColors.textTertiary,
  },
  socialSlot: {
    marginBottom: 16,
  },

  legalText: {
    textAlign: 'center',
    fontSize: 11,
    color: darkColors.textFaint,
  },
  bottomSpacer: {
    height: 40,
  },
});
