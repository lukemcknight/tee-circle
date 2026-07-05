import { useEffect, useState } from 'react';
import * as Location from 'expo-location';

export type LocationStatus = 'unasked' | 'granted' | 'denied' | 'unavailable';

export type DeviceLocation = {
  coords: { latitude: number; longitude: number } | null;
  status: LocationStatus;
};

let cached: DeviceLocation | null = null;

export const useDeviceLocation = (): DeviceLocation => {
  const [state, setState] = useState<DeviceLocation>(
    cached ?? { coords: null, status: 'unasked' },
  );

  useEffect(() => {
    if (cached) return;

    let cancelled = false;

    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (cancelled) return;

        if (status !== 'granted') {
          const next: DeviceLocation = { coords: null, status: 'denied' };
          cached = next;
          setState(next);
          return;
        }

        const last = await Location.getLastKnownPositionAsync();
        const pos =
          last ??
          (await Location.getCurrentPositionAsync({
            accuracy: Location.Accuracy.Low,
          }));

        if (cancelled) return;

        const next: DeviceLocation = {
          coords: { latitude: pos.coords.latitude, longitude: pos.coords.longitude },
          status: 'granted',
        };
        cached = next;
        setState(next);
      } catch {
        if (cancelled) return;
        const next: DeviceLocation = { coords: null, status: 'unavailable' };
        cached = next;
        setState(next);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  return state;
};
