import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing } from '../theme';

type TabName = 'Schedule' | 'Friends' | 'Profile';

type Props = {
  activeTab: TabName;
  onNavigate: (tab: TabName) => void;
};

export const BottomNavBar: React.FC<Props> = ({ activeTab, onNavigate }) => {
  const insets = useSafeAreaInsets();
  const bottomPadding = Math.max(insets.bottom, spacing.md);

  const tabs: { name: TabName; icon: keyof typeof Ionicons.glyphMap; iconActive: keyof typeof Ionicons.glyphMap }[] = [
    { name: 'Schedule', icon: 'calendar-outline', iconActive: 'calendar' },
    { name: 'Friends', icon: 'people-outline', iconActive: 'people' },
    { name: 'Profile', icon: 'person-outline', iconActive: 'person' },
  ];

  return (
    <View style={[styles.container, { paddingBottom: bottomPadding }]}>
      {tabs.map((tab) => {
        const isActive = activeTab === tab.name;
        return (
          <Pressable
            key={tab.name}
            style={styles.tab}
            onPress={() => onNavigate(tab.name)}
            accessibilityRole="tab"
            accessibilityLabel={tab.name}
            accessibilityState={{ selected: isActive }}
          >
            <Ionicons
              name={isActive ? tab.iconActive : tab.icon}
              size={24}
              color={isActive ? colors.primary : colors.inactive}
            />
            {isActive && <View style={styles.activeIndicator} />}
            <Text style={[styles.label, isActive && styles.labelActive]}>
              {tab.name}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingTop: spacing.sm,
    paddingHorizontal: spacing.lg,
    backgroundColor: colors.navBackground,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
  },
  tab: {
    alignItems: 'center',
    flex: 1,
    paddingVertical: spacing.xs,
  },
  activeIndicator: {
    width: 24,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.primary,
    marginTop: 4,
  },
  label: {
    fontSize: 10,
    fontWeight: '600',
    color: colors.inactive,
    marginTop: 4,
  },
  labelActive: {
    fontWeight: '700',
    color: colors.primary,
  },
});
