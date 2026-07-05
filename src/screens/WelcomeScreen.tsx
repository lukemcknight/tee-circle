import React, { useEffect, useRef } from 'react';
import {
  Animated,
  Dimensions,
  Image,
  Pressable,
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
import { AuthBackground } from '../components/AuthBackground';

type Props = NativeStackScreenProps<RootStackParamList, 'Welcome'>;

const { width: SCREEN_WIDTH } = Dimensions.get('window');

const features = [
  { key: 'friends', title: 'Friends', icon: 'people' as const, desc: 'Build your circle' },
  { key: 'teetimes', title: 'Tee Times', icon: 'calendar' as const, desc: 'Plan rounds' },
  { key: 'scores', title: 'Scores', icon: 'golf' as const, desc: 'Track handicap' },
];

export const WelcomeScreen: React.FC<Props> = ({ navigation }) => {
  // Staggered animations
  const logoOpacity = useRef(new Animated.Value(0)).current;
  const logoTranslateY = useRef(new Animated.Value(20)).current;
  const titleOpacity = useRef(new Animated.Value(0)).current;
  const titleTranslateY = useRef(new Animated.Value(16)).current;
  const featureOpacities = features.map(() => useRef(new Animated.Value(0)).current);
  const featureTranslates = features.map(() => useRef(new Animated.Value(24)).current);
  const actionsOpacity = useRef(new Animated.Value(0)).current;
  const actionsTranslateY = useRef(new Animated.Value(20)).current;

  useEffect(() => {
    const stagger = (delay: number, opacity: Animated.Value, translate: Animated.Value) => {
      return Animated.parallel([
        Animated.timing(opacity, {
          toValue: 1,
          duration: 500,
          delay,
          useNativeDriver: true,
        }),
        Animated.timing(translate, {
          toValue: 0,
          duration: 600,
          delay,
          useNativeDriver: true,
        }),
      ]);
    };

    Animated.parallel([
      stagger(0, logoOpacity, logoTranslateY),
      stagger(120, titleOpacity, titleTranslateY),
      ...featureOpacities.map((op, i) =>
        stagger(280 + i * 100, op, featureTranslates[i]),
      ),
      stagger(600, actionsOpacity, actionsTranslateY),
    ]).start();
  }, []);

  return (
    <AuthBackground>
      <StatusBar style="light" />
      <SafeAreaView style={styles.safe}>
        {/* Logo + Title */}
        <Animated.View
          style={[
            styles.heroSection,
            { opacity: logoOpacity, transform: [{ translateY: logoTranslateY }] },
          ]}
        >
          <View style={styles.logoContainer}>
            <View style={styles.logoGlow} />
            <Image
              source={require('../../assets/icon.png')}
              style={styles.logoImage}
            />
          </View>
        </Animated.View>

        <Animated.View
          style={[
            styles.titleSection,
            { opacity: titleOpacity, transform: [{ translateY: titleTranslateY }] },
          ]}
        >
          <Text style={styles.title}>TeeCircle</Text>
          <Text style={styles.subtitle}>Connect. Schedule. Tee Off.</Text>
        </Animated.View>

        {/* Feature pills */}
        <View style={styles.featureRow}>
          {features.map((item, index) => (
            <Animated.View
              key={item.key}
              style={[
                styles.featureCard,
                {
                  opacity: featureOpacities[index],
                  transform: [{ translateY: featureTranslates[index] }],
                },
              ]}
            >
              <View style={styles.featureIconWrap}>
                <Ionicons name={item.icon} size={22} color={colors.primary} />
              </View>
              <View style={styles.featureTextWrap}>
                <Text style={styles.featureTitle}>{item.title}</Text>
                <Text style={styles.featureDesc}>{item.desc}</Text>
              </View>
            </Animated.View>
          ))}
        </View>

        {/* Actions */}
        <Animated.View
          style={[
            styles.actions,
            { opacity: actionsOpacity, transform: [{ translateY: actionsTranslateY }] },
          ]}
        >
          <Pressable
            onPress={() => navigation.navigate('Auth', { mode: 'signup' })}
            style={({ pressed }) => [styles.primaryButton, pressed && styles.primaryPressed]}
          >
            <Text style={styles.primaryButtonText}>Join the Circle</Text>
            <Ionicons name="arrow-forward" size={18} color={darkColors.onPrimary} />
          </Pressable>

          <Pressable
            onPress={() => navigation.navigate('Auth', { mode: 'login' })}
            style={({ pressed }) => [styles.loginLink, pressed && styles.loginLinkPressed]}
          >
            <Text style={styles.loginLinkText}>I already have an account</Text>
          </Pressable>

          <Text style={styles.legalText}>
            By joining, you agree to our Terms and Privacy Policy.
          </Text>
        </Animated.View>
      </SafeAreaView>
    </AuthBackground>
  );
};

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    justifyContent: 'center',
  },

  // Hero
  heroSection: {
    alignItems: 'center',
    marginBottom: 20,
  },
  logoContainer: {
    width: 96,
    height: 96,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoGlow: {
    position: 'absolute',
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: darkColors.glow,
  },
  logoImage: {
    width: 88,
    height: 88,
    borderRadius: 22,
  },

  // Title
  titleSection: {
    alignItems: 'center',
    marginBottom: 32,
    gap: 8,
  },
  title: {
    fontSize: 42,
    fontWeight: '900',
    color: darkColors.text,
    letterSpacing: -1.2,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 16,
    fontWeight: '600',
    color: darkColors.textSecondary,
    letterSpacing: 0.5,
    textAlign: 'center',
  },

  // Feature cards
  featureRow: {
    paddingHorizontal: 24,
    gap: 10,
    marginBottom: 36,
  },
  featureCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: darkColors.glassSurface,
    borderWidth: 1,
    borderColor: darkColors.glassBorder,
    borderRadius: 16,
    paddingVertical: 14,
    paddingHorizontal: 16,
  },
  featureIconWrap: {
    width: 44,
    height: 44,
    borderRadius: 12,
    backgroundColor: darkColors.iconTint,
    alignItems: 'center',
    justifyContent: 'center',
  },
  featureTextWrap: {
    flex: 1,
    gap: 2,
  },
  featureTitle: {
    fontSize: 15,
    fontWeight: '700',
    color: darkColors.text,
  },
  featureDesc: {
    fontSize: 13,
    fontWeight: '500',
    color: darkColors.textTertiary,
  },

  // Actions
  actions: {
    paddingHorizontal: 24,
    gap: 10,
  },
  primaryButton: {
    height: 56,
    borderRadius: 16,
    backgroundColor: colors.primary,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 8,
  },
  primaryPressed: {
    transform: [{ scale: 0.98 }],
    backgroundColor: colors.primaryDark,
  },
  primaryButtonText: {
    fontSize: 17,
    fontWeight: '800',
    color: darkColors.onPrimary,
    letterSpacing: 0.2,
  },
  loginLink: {
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loginLinkPressed: {
    opacity: 0.7,
  },
  loginLinkText: {
    fontSize: 14,
    fontWeight: '600',
    color: darkColors.textSecondary,
  },
  legalText: {
    textAlign: 'center',
    fontSize: 11,
    color: darkColors.textFaint,
    marginTop: 4,
  },
});
