export const colors = {
  // Primary greens
  primary: '#13ec5b',
  primaryLight: '#7CCB8A',
  primaryDark: '#0fd650',
  secondary: '#3D8B54',

  // Accent (green)
  accent: '#13ec5b',

  // Backgrounds
  background: '#f6f8f6',
  card: '#FFFFFF',
  inputBackground: '#FFFFFF',

  // Text
  text: '#102216',
  textSecondary: '#4c9a66',
  muted: '#6B7280',
  placeholder: '#9CA3AF',
  inactive: '#9ca3af',

  // Surfaces
  surfaceGreen: '#e7f3eb',
  surfaceGreenPressed: '#d8efe0',
  backgroundGreen: '#EAF4EC',

  // Borders
  border: '#E5E7EB',
  borderLight: '#eef2ef',
  borderSubtle: '#d8e9df',
  borderGreen: '#cfe7d7',

  // Semantic colors
  success: '#13ec5b',
  error: '#DC2626',
  errorLight: '#FEE2E2',

  // Shadow
  shadow: 'rgba(0,0,0,0.08)',

  // Nav
  navBackground: 'rgba(255, 255, 255, 0.95)',
};

export const spacing = {
  xs: 8,
  sm: 12,
  md: 16,
  lg: 24,
  xl: 32,
};

export const radii = {
  sm: 8,
  md: 12,
  lg: 18,
  xl: 22,
};

export const typography = {
  title: 24,
  subtitle: 18,
  body: 16,
  small: 14,
};

export const cardShadow = {
  shadowColor: colors.shadow,
  shadowOffset: { width: 0, height: 4 },
  shadowOpacity: 1,
  shadowRadius: 10,
  elevation: 2,
} as const;
