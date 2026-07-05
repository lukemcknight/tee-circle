export const normalizeUsername = (value: string) => {
  const trimmed = value.trim().replace(/^@+/, '');
  return trimmed.toLowerCase();
};

const USERNAME_REGEX = /^[a-z0-9_-]{3,20}$/;

export const isValidUsername = (value: string) => {
  const normalized = normalizeUsername(value);
  return USERNAME_REGEX.test(normalized);
};

export const getUsernameError = (value: string): string | null => {
  const normalized = normalizeUsername(value);
  if (normalized.length === 0) {
    return 'Username is required';
  }
  if (normalized.length < 3) {
    return 'Username must be at least 3 characters';
  }
  if (normalized.length > 20) {
    return 'Username must be 20 characters or less';
  }
  if (!/^[a-z0-9_-]+$/.test(normalized)) {
    return 'Username can only contain letters, numbers, underscores, and hyphens';
  }
  return null;
};
