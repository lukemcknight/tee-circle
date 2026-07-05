import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { AppNavigator } from './src/navigation/AppNavigator';
import { AuthProvider } from './src/context/AuthContext';
import { DataProvider } from './src/context/DataContext';
import { usePushNotifications } from './src/hooks/usePushNotifications';
import { ErrorBoundary } from './src/components/ErrorBoundary';

const NotificationInitializer = () => {
  usePushNotifications();
  return null;
};

export default function App() {
  return (
    <ErrorBoundary>
      <AuthProvider>
        <DataProvider>
          <NotificationInitializer />
          <StatusBar style="dark" />
          <AppNavigator />
        </DataProvider>
      </AuthProvider>
    </ErrorBoundary>
  );
}
