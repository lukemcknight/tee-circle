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
  TextInput,
  View,
} from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { colors, radii, spacing, typography } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import { isValidEmail } from '../utils/validation';
import { getUsernameError } from '../utils/username';

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

  if (initializing) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.flex}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          {/* Header */}
          <LinearGradient
            colors={[colors.primary, colors.background]}
            start={{ x: 0.5, y: 0 }}
            end={{ x: 0.5, y: 1 }}
            style={styles.headerImage}
          >
            {/* Decorative circles */}
            <View style={styles.decoCircle1} />
            <View style={styles.decoCircle2} />
            <View style={styles.decoCircle3} />
            {/* Brand */}
            <View style={styles.brandContainer}>
              <Image source={require('../../assets/icon.png')} style={styles.logoImage} />
              <Text style={styles.brandName}>TeeCircle</Text>
              <Text style={styles.brandTagline}>Your Golf Circle, simplified.</Text>
            </View>
          </LinearGradient>

          {/* Main Content */}
          <View style={styles.content}>
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
                  <View style={styles.inputGroup}>
                    <Text style={styles.inputLabel}>EMAIL</Text>
                    <View style={styles.inputWrapper}>
                      <TextInput
                        style={styles.input}
                        placeholder="birdie_king@example.com"
                        placeholderTextColor={colors.placeholder}
                        value={identifier}
                        onChangeText={(v) => {
                          setIdentifier(v);
                          setAuthError(null);
                        }}
                        autoCapitalize="none"
                        keyboardType="email-address"
                        autoComplete="email"
                      />
                    </View>
                  </View>

                  <View style={styles.inputGroup}>
                    <Text style={styles.inputLabel}>PASSWORD</Text>
                    <View style={styles.inputWrapper}>
                      <TextInput
                        style={[styles.input, styles.inputWithIcon]}
                        placeholder="••••••••"
                        placeholderTextColor={colors.placeholder}
                        value={loginPassword}
                        onChangeText={(v) => {
                          setLoginPassword(v);
                          setAuthError(null);
                        }}
                        secureTextEntry={!showPassword}
                        autoComplete="password"
                      />
                      <Pressable
                        style={styles.eyeButton}
                        onPress={() => setShowPassword(!showPassword)}
                      >
                        <Ionicons name={showPassword ? 'eye-off' : 'eye'} size={20} color={colors.placeholder} />
                      </Pressable>
                    </View>
                  </View>

                  <Pressable style={styles.forgotButton} onPress={handleForgotPassword}>
                    <Text style={styles.forgotText}>Forgot Password?</Text>
                  </Pressable>
                </>
              ) : (
                <>
                  <View style={styles.inputGroup}>
                    <Text style={styles.inputLabel}>FULL NAME</Text>
                    <View style={styles.inputWrapper}>
                      <TextInput
                        style={styles.input}
                        placeholder="Tiger Woods"
                        placeholderTextColor={colors.placeholder}
                        value={name}
                        onChangeText={(v) => {
                          setName(v);
                          setAuthError(null);
                        }}
                        autoComplete="name"
                      />
                    </View>
                  </View>

                  <View style={styles.inputGroup}>
                    <Text style={styles.inputLabel}>USERNAME</Text>
                    <View style={styles.inputWrapper}>
                      <TextInput
                        style={styles.input}
                        placeholder="birdie_king"
                        placeholderTextColor={colors.placeholder}
                        value={username}
                        onChangeText={(v) => {
                          setUsername(v);
                          setAuthError(null);
                        }}
                        autoCapitalize="none"
                        autoComplete="username"
                      />
                    </View>
                  </View>

                  <View style={styles.inputGroup}>
                    <Text style={styles.inputLabel}>EMAIL</Text>
                    <View style={styles.inputWrapper}>
                      <TextInput
                        style={styles.input}
                        placeholder="birdie_king@example.com"
                        placeholderTextColor={colors.placeholder}
                        value={signupEmail}
                        onChangeText={(v) => {
                          setSignupEmail(v);
                          setAuthError(null);
                        }}
                        autoCapitalize="none"
                        keyboardType="email-address"
                        autoComplete="email"
                      />
                    </View>
                  </View>

                  <View style={styles.inputGroup}>
                    <Text style={styles.inputLabel}>PASSWORD</Text>
                    <View style={styles.inputWrapper}>
                      <TextInput
                        style={[styles.input, styles.inputWithIcon]}
                        placeholder="••••••••"
                        placeholderTextColor={colors.placeholder}
                        value={signupPassword}
                        onChangeText={(v) => {
                          setSignupPassword(v);
                          setAuthError(null);
                        }}
                        secureTextEntry={!showPassword}
                        autoComplete="new-password"
                      />
                      <Pressable
                        style={styles.eyeButton}
                        onPress={() => setShowPassword(!showPassword)}
                      >
                        <Ionicons name={showPassword ? 'eye-off' : 'eye'} size={20} color={colors.placeholder} />
                      </Pressable>
                    </View>
                  </View>
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

            <View style={styles.bottomSpacer} />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  flex: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  scrollContent: {
    flexGrow: 1,
  },
  headerImage: {
    height: 320,
    justifyContent: 'flex-end',
    overflow: 'hidden',
  },
  decoCircle1: {
    position: 'absolute',
    width: 160,
    height: 160,
    borderRadius: 80,
    backgroundColor: 'rgba(255,255,255,0.08)',
    top: -30,
    right: -40,
  },
  decoCircle2: {
    position: 'absolute',
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: 'rgba(255,255,255,0.06)',
    top: 80,
    left: -20,
  },
  decoCircle3: {
    position: 'absolute',
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(255,255,255,0.05)',
    bottom: 60,
    right: 30,
  },
  brandContainer: {
    alignItems: 'center',
    paddingBottom: 32,
  },
  logoImage: {
    width: 64,
    height: 64,
    borderRadius: 16,
    marginBottom: 12,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.4,
    shadowRadius: 20,
    elevation: 8,
  },
  brandName: {
    fontSize: 30,
    fontWeight: '800',
    color: colors.text,
    letterSpacing: -0.5,
  },
  brandTagline: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.muted,
    marginTop: 4,
  },
  content: {
    flex: 1,
    paddingHorizontal: 24,
    marginTop: -24,
  },
  headline: {
    fontSize: 28,
    fontWeight: '700',
    color: colors.text,
    textAlign: 'center',
    marginBottom: 24,
  },
  toggleContainer: {
    flexDirection: 'row',
    backgroundColor: colors.border,
    borderRadius: 9999,
    padding: 4,
    marginBottom: 32,
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
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  toggleText: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.muted,
  },
  toggleTextActive: {
    color: colors.text,
  },
  form: {
    gap: 20,
    marginBottom: 24,
  },
  inputGroup: {
    gap: 8,
  },
  inputLabel: {
    fontSize: 11,
    fontWeight: '600',
    color: colors.muted,
    letterSpacing: 1,
    marginLeft: 4,
  },
  inputWrapper: {
    position: 'relative',
  },
  input: {
    height: 56,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 16,
    paddingHorizontal: 16,
    fontSize: 16,
    fontWeight: '500',
    color: colors.text,
  },
  inputWithIcon: {
    paddingRight: 50,
  },
  eyeButton: {
    position: 'absolute',
    right: 16,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
  },
  eyeIcon: {
    fontSize: 20,
    opacity: 0.5,
  },
  forgotButton: {
    alignSelf: 'flex-end',
    marginTop: -8,
  },
  forgotText: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.text,
  },
  errorText: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.error,
    textAlign: 'center',
  },
  resetSentText: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.secondary,
    textAlign: 'center',
  },
  primaryButton: {
    height: 56,
    backgroundColor: colors.primary,
    borderRadius: 9999,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 14,
    elevation: 4,
    marginBottom: 32,
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
    color: colors.text,
    marginRight: 8,
  },
  buttonArrow: {
    fontSize: 20,
    fontWeight: '600',
    color: colors.text,
  },
  bottomSpacer: {
    height: 40,
  },
});
