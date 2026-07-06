import * as AppleAuthentication from 'expo-apple-authentication';
import * as Crypto from 'expo-crypto';
import { GoogleSignin } from '@react-native-google-signin/google-signin';
import { supabase } from './supabase';

export type SocialSignInResult = 'success' | 'cancelled' | 'error';

GoogleSignin.configure({
  iosClientId: process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID,
  webClientId: process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID,
});

export const signInWithAppleNative = async (): Promise<SocialSignInResult> => {
  try {
    // Supabase verifies the id_token's nonce claim (SHA256 of rawNonce) against rawNonce
    const rawNonce = Crypto.randomUUID();
    const hashedNonce = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      rawNonce,
    );

    const credential = await AppleAuthentication.signInAsync({
      requestedScopes: [
        AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
        AppleAuthentication.AppleAuthenticationScope.EMAIL,
      ],
      nonce: hashedNonce,
    });

    if (!credential.identityToken) {
      return 'error';
    }

    const { error } = await supabase.auth.signInWithIdToken({
      provider: 'apple',
      token: credential.identityToken,
      nonce: rawNonce,
    });
    if (error) {
      return 'error';
    }

    // Apple only provides fullName on the very first authorization — persist it
    // to user metadata so ensureProfile() can patch profiles.full_name.
    const givenName = credential.fullName?.givenName;
    if (givenName) {
      const fullName = [givenName, credential.fullName?.familyName]
        .filter(Boolean)
        .join(' ');
      await supabase.auth.updateUser({ data: { full_name: fullName } });
    }

    return 'success';
  } catch (e) {
    if ((e as { code?: string })?.code === 'ERR_REQUEST_CANCELED') {
      return 'cancelled';
    }
    return 'error';
  }
};

export const signInWithGoogleNative = async (): Promise<SocialSignInResult> => {
  try {
    const response = await GoogleSignin.signIn();
    if (response.type !== 'success') {
      return 'cancelled';
    }
    if (!response.data.idToken) {
      return 'error';
    }

    const { error } = await supabase.auth.signInWithIdToken({
      provider: 'google',
      token: response.data.idToken,
    });
    return error ? 'error' : 'success';
  } catch {
    return 'error';
  }
};
