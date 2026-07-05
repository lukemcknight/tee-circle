import React from 'react';
import { StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { darkColors } from '../theme';

type Props = {
  children: React.ReactNode;
};

// Shared dark premium backdrop for the Welcome → Auth flow: full-bleed
// green gradient plus ambient blurred orbs, so both screens read as one
// continuous surface.
export const AuthBackground: React.FC<Props> = ({ children }) => {
  return (
    <View style={styles.root}>
      <LinearGradient
        colors={darkColors.gradient}
        locations={darkColors.gradientLocations}
        style={StyleSheet.absoluteFillObject}
      />

      {/* Ambient orbs */}
      <View pointerEvents="none" style={styles.orbTopRight} />
      <View pointerEvents="none" style={styles.orbBottomLeft} />
      <View pointerEvents="none" style={styles.orbCenter} />

      {children}
    </View>
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: darkColors.background,
  },
  orbTopRight: {
    position: 'absolute',
    top: -80,
    right: -60,
    width: 280,
    height: 280,
    borderRadius: 140,
    backgroundColor: darkColors.orbStrong,
  },
  orbBottomLeft: {
    position: 'absolute',
    bottom: -40,
    left: -80,
    width: 240,
    height: 240,
    borderRadius: 120,
    backgroundColor: darkColors.orbMedium,
  },
  orbCenter: {
    position: 'absolute',
    top: '35%',
    left: '20%',
    width: 200,
    height: 200,
    borderRadius: 100,
    backgroundColor: darkColors.orbSoft,
  },
});
