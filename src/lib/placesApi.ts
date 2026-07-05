const AUTOCOMPLETE_URL = 'https://places.googleapis.com/v1/places:autocomplete';
const PLACE_DETAILS_URL = 'https://places.googleapis.com/v1/places';

const GOOGLE_PLACES_API_KEY = process.env.EXPO_PUBLIC_GOOGLE_PLACES_API_KEY;

export type GolfCoursePrediction = {
  placeId: string;
  mainText: string;
  secondaryText: string;
};

export type PlaceDetails = {
  placeId: string;
  name: string;
  address: string;
  lat: number;
  lng: number;
};

export type LocationBias = {
  latitude: number;
  longitude: number;
};

export const isPlacesApiConfigured = (): boolean => !!GOOGLE_PLACES_API_KEY;

export const createSessionToken = (): string => {
  const bytes = new Uint8Array(16);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = Math.floor(Math.random() * 256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

const requireKey = (): string => {
  if (!GOOGLE_PLACES_API_KEY) {
    throw new Error('EXPO_PUBLIC_GOOGLE_PLACES_API_KEY is not set');
  }
  return GOOGLE_PLACES_API_KEY;
};

export const autocompleteGolfCourses = async (
  input: string,
  sessionToken: string,
  bias: LocationBias | null,
  signal?: AbortSignal,
): Promise<GolfCoursePrediction[]> => {
  const apiKey = requireKey();
  const body: Record<string, unknown> = {
    input,
    includedPrimaryTypes: ['golf_course'],
    sessionToken,
  };
  if (bias) {
    body.locationBias = {
      circle: {
        center: { latitude: bias.latitude, longitude: bias.longitude },
        radius: 50000,
      },
    };
  }

  const res = await fetch(AUTOCOMPLETE_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask':
        'suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat',
    },
    body: JSON.stringify(body),
    signal,
  });

  if (!res.ok) {
    throw new Error(`Places autocomplete failed: ${res.status}`);
  }

  const json = (await res.json()) as {
    suggestions?: Array<{
      placePrediction?: {
        placeId: string;
        text?: { text: string };
        structuredFormat?: {
          mainText?: { text: string };
          secondaryText?: { text: string };
        };
      };
    }>;
  };

  return (json.suggestions ?? [])
    .map((s) => s.placePrediction)
    .filter((p): p is NonNullable<typeof p> => !!p)
    .map((p) => ({
      placeId: p.placeId,
      mainText: p.structuredFormat?.mainText?.text ?? p.text?.text ?? '',
      secondaryText: p.structuredFormat?.secondaryText?.text ?? '',
    }));
};

export const getPlaceDetails = async (
  placeId: string,
  sessionToken: string,
): Promise<PlaceDetails> => {
  const apiKey = requireKey();
  const res = await fetch(
    `${PLACE_DETAILS_URL}/${encodeURIComponent(placeId)}?sessionToken=${encodeURIComponent(sessionToken)}`,
    {
      headers: {
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
      },
    },
  );

  if (!res.ok) {
    throw new Error(`Place details failed: ${res.status}`);
  }

  const json = (await res.json()) as {
    id: string;
    displayName?: { text: string };
    formattedAddress?: string;
    location?: { latitude: number; longitude: number };
  };

  return {
    placeId: json.id,
    name: json.displayName?.text ?? '',
    address: json.formattedAddress ?? '',
    lat: json.location?.latitude ?? 0,
    lng: json.location?.longitude ?? 0,
  };
};
