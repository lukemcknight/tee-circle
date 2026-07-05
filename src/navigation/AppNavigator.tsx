import React, { useCallback, useRef } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { NavigationContainer, NavigationContainerRef } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { posthog } from '../lib/analytics';
import { SafeAreaView } from 'react-native-safe-area-context';
import { colors } from '../theme';
import { HomeScreen } from '../screens/HomeScreen';
import { CreateRoundScreen } from '../screens/CreateRoundScreen';
import { RoundDetailScreen } from '../screens/RoundDetailScreen';
import { InviteFriendsScreen } from '../screens/InviteFriendsScreen';
import { RootStackParamList } from './types';
import { AuthScreen } from '../screens/AuthScreen';
import { GroupDetailsScreen } from '../screens/GroupDetailsScreen';
import { GroupMembersScreen } from '../screens/GroupMembersScreen';
import { ProfileScreen } from '../screens/ProfileScreen';
import { FriendsScreen } from '../screens/FriendsScreen';
import { FriendDetailScreen } from '../screens/FriendDetailScreen';
import { UsernameScreen } from '../screens/UsernameScreen';
import { useAuth } from '../context/AuthContext';
import { WelcomeScreen } from '../screens/WelcomeScreen';
import { RoundScoreScreen } from '../screens/RoundScoreScreen';

const Stack = createNativeStackNavigator<RootStackParamList>();

export const AppNavigator = () => {
  const { user, initializing } = useAuth();
  const routeNameRef = useRef<string | undefined>(undefined);
  const navigationRef = useRef<NavigationContainerRef<RootStackParamList>>(null);

  const onStateChange = useCallback(() => {
    const currentRouteName = navigationRef.current?.getCurrentRoute()?.name;
    if (currentRouteName && currentRouteName !== routeNameRef.current) {
      posthog.screen(currentRouteName);
    }
    routeNameRef.current = currentRouteName;
  }, []);

  if (initializing) {
    return (
      <SafeAreaView style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background }}>
        <ActivityIndicator size="large" color={colors.accent} />
      </SafeAreaView>
    );
  }

  return (
    <NavigationContainer ref={navigationRef} onStateChange={onStateChange}>
      <Stack.Navigator
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.background },
        }}
      >
        {user ? (
          <Stack.Group>
            <Stack.Screen name="Home" component={HomeScreen} options={{ animation: 'none' }} />
            <Stack.Screen name="CreateRound" component={CreateRoundScreen} />
            <Stack.Screen name="RoundDetail" component={RoundDetailScreen} />
            <Stack.Screen name="RoundScore" component={RoundScoreScreen} />
            <Stack.Screen name="InviteFriends" component={InviteFriendsScreen} />
            <Stack.Screen name="GroupDetails" component={GroupDetailsScreen} />
            <Stack.Screen name="GroupMembers" component={GroupMembersScreen} />
            <Stack.Screen name="Profile" component={ProfileScreen} options={{ animation: 'none' }} />
            <Stack.Screen name="Friends" component={FriendsScreen} options={{ animation: 'none' }} />
            <Stack.Screen name="FriendDetail" component={FriendDetailScreen} />
            <Stack.Screen name="Username" component={UsernameScreen} />
          </Stack.Group>
        ) : (
          <Stack.Group>
            <Stack.Screen name="Welcome" component={WelcomeScreen} />
            <Stack.Screen name="Auth" component={AuthScreen} />
          </Stack.Group>
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
};
