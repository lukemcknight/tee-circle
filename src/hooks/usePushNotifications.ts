import { MutableRefObject, useCallback, useEffect, useRef } from 'react';
import { AppState, Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import Constants from 'expo-constants';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';

const getProjectId = (): string | undefined =>
  (Constants?.expoConfig?.extra?.eas as { projectId?: string } | undefined)?.projectId ??
  Constants?.easConfig?.projectId ??
  undefined;

const fetchPushToken = async (hasRequestedRef: MutableRefObject<boolean>) => {
  const settings = await Notifications.getPermissionsAsync();
  let status = settings.status;

  if (status !== 'granted' && settings.canAskAgain && !hasRequestedRef.current) {
    const request = await Notifications.requestPermissionsAsync();
    status = request.status;
    hasRequestedRef.current = true;
  }

  if (status !== 'granted') {
    return null;
  }

  const projectId = getProjectId();
  const response = await Notifications.getExpoPushTokenAsync(projectId ? { projectId } : undefined);
  return response.data;
};

const saveToken = async (userId: string, token: string) => {
  try {
    const { data: existing } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', userId)
      .limit(1)
      .maybeSingle();

    if (existing?.token === token) {
      return;
    }

    if (existing) {
      await supabase.from('push_tokens').update({ token, platform: Platform.OS }).eq('user_id', userId);
      return;
    }

    await supabase.from('push_tokens').insert({ user_id: userId, token, platform: Platform.OS });
  } catch {
    // Silent failure: token storage is best-effort only.
  }
};

export const usePushNotifications = () => {
  const { user, initializing } = useAuth();
  const hasRequestedPermission = useRef(false);
  const registering = useRef(false);

  const register = useCallback(async () => {
    if (!user || initializing || registering.current) {
      return;
    }

    registering.current = true;
    try {
      if (Platform.OS === 'android') {
        await Notifications.setNotificationChannelAsync('default', {
          name: 'default',
          importance: Notifications.AndroidImportance.MAX,
        });
      }

      const token = await fetchPushToken(hasRequestedPermission);
      if (token) {
        await saveToken(user.id, token);
      }
    } catch {
      // Ignore registration errors to avoid interrupting the UI.
    } finally {
      registering.current = false;
    }
  }, [user, initializing]);

  useEffect(() => {
    register();
  }, [register]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        register();
      }
    });

    return () => subscription.remove();
  }, [register]);
};
