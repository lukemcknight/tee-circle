import PostHog from 'posthog-react-native';

const POSTHOG_API_KEY = process.env.EXPO_PUBLIC_POSTHOG_API_KEY ?? '';
const POSTHOG_HOST = process.env.EXPO_PUBLIC_POSTHOG_HOST ?? 'https://us.i.posthog.com';

const noop = () => {};
const stub = new Proxy(
  {},
  {
    get: () => noop,
  },
) as unknown as PostHog;

let instance: PostHog;
if (!POSTHOG_API_KEY) {
  instance = stub;
} else {
  try {
    instance = new PostHog(POSTHOG_API_KEY, {
      host: POSTHOG_HOST,
      enableSessionReplay: false,
    });
  } catch (e) {
    // eslint-disable-next-line no-console
    console.warn('[analytics] PostHog failed to initialize, using no-op stub', e);
    instance = stub;
  }
}

export const posthog = instance;
