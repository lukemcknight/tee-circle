import { Profile } from '../types';

export const getProfileName = (profile: Pick<Profile, 'full_name' | 'username'> | null | undefined) => {
  if (!profile) return '';

  const fullName = profile.full_name?.trim();
  if (fullName) return fullName;

  const username = profile.username?.trim()?.replace(/^@+/, '');
  if (username) return `@${username}`;

  return '';
};

export const getProfileHandle = (profile: Pick<Profile, 'username'> | null | undefined) => {
  if (!profile) return null;

  const username = profile.username?.trim()?.replace(/^@+/, '');
  if (!username) return null;

  return `@${username}`;
};
