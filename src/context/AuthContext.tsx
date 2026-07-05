import React, { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { Session, User } from '@supabase/supabase-js';
import { supabase, supabaseConfigError } from '../lib/supabase';
import { posthog } from '../lib/analytics';
import { Profile } from '../types';
import { normalizeUsername } from '../utils/username';
import { withRetry } from '../utils/retry';

const withTimeout = <T,>(promise: Promise<T>, ms: number, errorMessage: string): Promise<T> => {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(errorMessage)), ms)
    ),
  ]);
};

type AuthContextValue = {
  user: User | null;
  profile: Profile | null;
  userEmail: string | null;
  session: Session | null;
  initializing: boolean;
  refreshProfile: () => Promise<void>;
  signIn: (identifier: string, password?: string) => Promise<boolean>;
  signUp: (params: { name: string; username: string; email: string; password: string }) => Promise<boolean>;
  signOut: () => Promise<void>;
  deleteProfile: () => Promise<boolean>;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  if (supabaseConfigError) {
    throw new Error(supabaseConfigError);
  }
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [initializing, setInitializing] = useState(true);

  const clearAuthState = useCallback(() => {
    setSession(null);
    setUser(null);
    setUserEmail(null);
    setProfile(null);
  }, []);

  const ensureProfile = useCallback(
    async (authUser: User) => {
      const fullName = authUser.user_metadata?.full_name ?? null;
      const username = authUser.user_metadata?.username ?? null;
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, username')
        .eq('id', authUser.id)
        .maybeSingle();

      if (error) {
        setProfile(null);
        return;
      }

      if (!data) {
        const insert = await supabase.from('profiles').upsert({
          id: authUser.id,
          full_name: fullName,
          username,
        });

        if (!insert.error) {
          setProfile({
            id: authUser.id,
            full_name: fullName,
            username,
          });
        }
      } else {
        if ((!data.username && username) || (!data.full_name && fullName)) {
          const patch = await supabase.from('profiles').upsert({
            id: authUser.id,
            full_name: fullName ?? data.full_name,
            username: username ?? data.username ?? null,
          });
          if (patch.error) return;
          setProfile({
            id: authUser.id,
            full_name: fullName ?? data.full_name,
            username: username ?? data.username ?? null,
          });
        } else {
          setProfile(data);
        }
      }
    },
    [],
  );

  useEffect(() => {
    let isMounted = true;

    const init = async () => {
      try {
        const { data, error } = await withRetry(
          () => withTimeout(
            supabase.auth.getSession(),
            10000,
            'Session initialization timed out'
          ),
          { maxRetries: 3, baseDelayMs: 1000 }
        );

        if (!isMounted) return;

        if (error && error.message?.includes('Invalid Refresh Token')) {
          await supabase.auth.signOut({ scope: 'local' });
          clearAuthState();
          return;
        }

        const currentSession = data.session;
        setSession(currentSession);
        setUser(currentSession?.user ?? null);
        setUserEmail(currentSession?.user?.email ?? null);

        if (currentSession?.user) {
          // Fire-and-forget: profile loading shouldn't block navigation
          withRetry(
            () => ensureProfile(currentSession.user),
            { maxRetries: 2, baseDelayMs: 500 }
          ).catch(() => {});
        }
      } catch {
        if (isMounted) {
          setSession(null);
          setUser(null);
          setProfile(null);
        }
      } finally {
        if (isMounted) {
          setInitializing(false);
        }
      }
    };
    init();

    const { data: listener } = supabase.auth.onAuthStateChange(async (event, nextSession) => {
      if (!isMounted) return;

      if ((event as string) === 'TOKEN_REFRESH_FAILED') {
        // Try to refresh the session one more time before giving up
        try {
          const { data: refreshData } = await supabase.auth.refreshSession();
          if (refreshData.session && isMounted) {
            setSession(refreshData.session);
            setUser(refreshData.session.user);
            setUserEmail(refreshData.session.user?.email ?? null);
            return;
          }
        } catch {
          // Refresh truly failed, sign out
        }
        await supabase.auth.signOut({ scope: 'local' });
        clearAuthState();
        return;
      }

      setSession(nextSession);
      setUser(nextSession?.user ?? null);
      setUserEmail(nextSession?.user?.email ?? null);

      if (nextSession?.user) {
        posthog.identify(nextSession.user.id, {
          email: nextSession.user.email ?? null,
        });
        // Fire-and-forget: don't block auth state updates
        ensureProfile(nextSession.user).catch(() => {});
      } else if (isMounted) {
        posthog.reset();
        setProfile(null);
      }
    });

    return () => {
      isMounted = false;
      listener.subscription.unsubscribe();
    };
  }, [clearAuthState, ensureProfile]);

  const refreshProfile = useCallback(async () => {
    if (!user) return;
    await ensureProfile(user);
  }, [user, ensureProfile]);

  const signIn = useCallback(async (identifier: string, password?: string) => {
    const email = identifier.trim();
    if (password) {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (!error) posthog.capture('sign_in', { method: 'email' });
      return !error;
    }
    const { error } = await supabase.auth.signInWithOtp({ email });
    if (!error) posthog.capture('sign_in', { method: 'otp' });
    return !error;
  }, []);

  const signUp = useCallback(async (params: { name: string; username: string; email: string; password: string }) => {
    const { name, username, email, password } = params;
    const normalizedUsername = normalizeUsername(username);
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: name,
          username: normalizedUsername,
        },
      },
    });
    if (!error) posthog.capture('sign_up', { method: 'email' });
    return !error;
  }, []);

  const signOut = useCallback(async () => {
    try {
      await supabase.auth.signOut();
    } finally {
      clearAuthState();
    }
  }, [clearAuthState]);

  const deleteProfile = useCallback(async () => {
    if (!user) return false;

    // Clear user metadata
    await supabase.auth.updateUser({
      data: {
        full_name: null,
        username: null,
      },
    });

    // Use RPC to safely delete all user data (friendships, groups, rounds, etc.)
    const { error: deleteError } = await supabase.rpc('delete_user_account');
    if (deleteError) {
      return false;
    }

    const { error: signOutError } = await supabase.auth.signOut();
    setUserEmail(null);
    setProfile(null);
    return !signOutError;
  }, [user]);

  const value: AuthContextValue = {
    user,
    profile,
    session,
    initializing,
    signIn,
    signUp,
    signOut,
    userEmail,
    refreshProfile,
    deleteProfile,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export const useAuth = (): AuthContextValue => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};
