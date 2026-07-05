import 'react-native-url-polyfill/auto';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type Json = string | number | boolean | null | { [key: string]: Json } | Json[];

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          full_name: string | null;
          username: string | null;
          avatar_url: string | null;
          created_at: string | null;
        };
        Insert: {
          id: string;
          full_name?: string | null;
          username?: string | null;
          avatar_url?: string | null;
          created_at?: string | null;
        };
        Update: {
          id?: string;
          full_name?: string | null;
          username?: string | null;
          avatar_url?: string | null;
          created_at?: string | null;
        };
      };
      groups: {
        Row: {
          id: string;
          name: string;
          created_by: string | null;
          created_at: string | null;
        };
        Insert: {
          id?: string;
          name: string;
          created_by?: string | null;
          created_at?: string | null;
        };
        Update: {
          id?: string;
          name?: string;
          created_by?: string | null;
          created_at?: string | null;
        };
      };
      group_members: {
        Row: {
          id: string;
          group_id: string;
          user_id: string;
          role: string | null;
          created_at: string | null;
        };
        Insert: {
          id?: string;
          group_id: string;
          user_id: string;
          role?: string | null;
          created_at?: string | null;
        };
        Update: {
          id?: string;
          group_id?: string;
          user_id?: string;
          role?: string | null;
          created_at?: string | null;
        };
      };
      rounds: {
        Row: {
          id: string;
          course_name: string;
          course_place_id: string | null;
          course_address: string | null;
          course_lat: number | null;
          course_lng: number | null;
          tee_time: string;
          holes: number | null;
          walk_ride: string | null;
          status: string | null;
          created_by: string | null;
        };
        Insert: {
          id?: string;
          course_name: string;
          course_place_id?: string | null;
          course_address?: string | null;
          course_lat?: number | null;
          course_lng?: number | null;
          tee_time: string;
          holes?: number | null;
          walk_ride?: string | null;
          status?: string | null;
          created_by?: string | null;
        };
        Update: {
          id?: string;
          course_name?: string;
          course_place_id?: string | null;
          course_address?: string | null;
          course_lat?: number | null;
          course_lng?: number | null;
          tee_time?: string;
          holes?: number | null;
          walk_ride?: string | null;
          status?: string | null;
          created_by?: string | null;
        };
      };
      round_responses: {
        Row: {
          round_id: string;
          user_id: string;
          response: 'pending' | 'yes' | 'no' | null;
          created_at: string | null;
        };
        Insert: {
          round_id: string;
          user_id: string;
          response?: 'pending' | 'yes' | 'no' | null;
          created_at?: string | null;
        };
        Update: {
          round_id?: string;
          user_id?: string;
          response?: 'pending' | 'yes' | 'no' | null;
          created_at?: string | null;
        };
      };
      player_handicap_profiles: {
        Row: {
          user_id: string;
          handicap_index: number | null;
          handicap_source: string;
          rounds_count: number;
          last_calculated_at: string | null;
          is_hidden: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          user_id: string;
          handicap_index?: number | null;
          handicap_source?: string;
          rounds_count?: number;
          last_calculated_at?: string | null;
          is_hidden?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          user_id?: string;
          handicap_index?: number | null;
          handicap_source?: string;
          rounds_count?: number;
          last_calculated_at?: string | null;
          is_hidden?: boolean;
          created_at?: string;
          updated_at?: string;
        };
      };
      scorecards: {
        Row: {
          id: string;
          round_id: string;
          player_id: string;
          entered_by: string;
          status: 'draft' | 'completed';
          holes: number;
          gross_score: number | null;
          net_score: number | null;
          handicap_index_at_round: number | null;
          course_handicap: number | null;
          playing_handicap: number | null;
          course_name: string | null;
          tee_name: string | null;
          tee_color: string | null;
          course_rating: number | null;
          slope_rating: number | null;
          par: number | null;
          started_at: string | null;
          completed_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          round_id: string;
          player_id: string;
          entered_by: string;
          status?: 'draft' | 'completed';
          holes: number;
          gross_score?: number | null;
          net_score?: number | null;
          handicap_index_at_round?: number | null;
          course_handicap?: number | null;
          playing_handicap?: number | null;
          course_name?: string | null;
          tee_name?: string | null;
          tee_color?: string | null;
          course_rating?: number | null;
          slope_rating?: number | null;
          par?: number | null;
          started_at?: string | null;
          completed_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          round_id?: string;
          player_id?: string;
          entered_by?: string;
          status?: 'draft' | 'completed';
          holes?: number;
          gross_score?: number | null;
          net_score?: number | null;
          handicap_index_at_round?: number | null;
          course_handicap?: number | null;
          playing_handicap?: number | null;
          course_name?: string | null;
          tee_name?: string | null;
          tee_color?: string | null;
          course_rating?: number | null;
          slope_rating?: number | null;
          par?: number | null;
          started_at?: string | null;
          completed_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
      };
      scorecard_holes: {
        Row: {
          id: string;
          scorecard_id: string;
          hole_number: number;
          par: number | null;
          stroke_index: number | null;
          yards: number | null;
          strokes: number | null;
          putts: number | null;
          fairway_hit: boolean | null;
          gir: boolean | null;
          penalties: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          scorecard_id: string;
          hole_number: number;
          par?: number | null;
          stroke_index?: number | null;
          yards?: number | null;
          strokes?: number | null;
          putts?: number | null;
          fairway_hit?: boolean | null;
          gir?: boolean | null;
          penalties?: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          scorecard_id?: string;
          hole_number?: number;
          par?: number | null;
          stroke_index?: number | null;
          yards?: number | null;
          strokes?: number | null;
          putts?: number | null;
          fairway_hit?: boolean | null;
          gir?: boolean | null;
          penalties?: number;
          created_at?: string;
          updated_at?: string;
        };
      };
      handicap_differentials: {
        Row: {
          id: string;
          user_id: string;
          round_id: string | null;
          scorecard_id: string;
          holes: number;
          adjusted_gross_score: number;
          course_rating: number;
          slope_rating: number;
          pcc: number;
          differential: number;
          played_at: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          round_id?: string | null;
          scorecard_id: string;
          holes: number;
          adjusted_gross_score: number;
          course_rating: number;
          slope_rating: number;
          pcc?: number;
          differential: number;
          played_at: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          round_id?: string | null;
          scorecard_id?: string;
          holes?: number;
          adjusted_gross_score?: number;
          course_rating?: number;
          slope_rating?: number;
          pcc?: number;
          differential?: number;
          played_at?: string;
          created_at?: string;
        };
      };
      friendships: {
        Row: {
          id: string;
          user_low: string;
          user_high: string;
          requested_by: string;
          status: 'pending' | 'accepted';
          created_at: string | null;
          accepted_at: string | null;
        };
        Insert: {
          id?: string;
          user_low: string;
          user_high: string;
          requested_by: string;
          status?: 'pending' | 'accepted';
          created_at?: string | null;
          accepted_at?: string | null;
        };
        Update: {
          id?: string;
          user_low?: string;
          user_high?: string;
          requested_by?: string;
          status?: 'pending' | 'accepted';
          created_at?: string | null;
          accepted_at?: string | null;
        };
      };
      push_tokens: {
        Row: {
          user_id: string;
          token: string;
          platform: string | null;
          created_at: string | null;
        };
        Insert: {
          user_id: string;
          token: string;
          platform?: string | null;
          created_at?: string | null;
        };
        Update: {
          user_id?: string;
          token?: string;
          platform?: string | null;
          created_at?: string | null;
        };
      };
    };
    Views: {
      visible_rounds: {
        Row: {
          id: string;
          course_name: string;
          course_place_id: string | null;
          course_address: string | null;
          course_lat: number | null;
          course_lng: number | null;
          tee_time: string;
          holes: number | null;
          walk_ride: string | null;
          status: string | null;
          created_by: string | null;
        };
      };
    };
    Functions: {
      delete_user_account: {
        Args: Record<string, never>;
        Returns: void;
      };
      send_friend_request_by_username: {
        Args: { p_username: string };
        Returns: boolean;
      };
      accept_friend_request: {
        Args: { p_friendship_id: string };
        Returns: boolean;
      };
      invite_friend_to_round: {
        Args: { p_round_id: string; p_friend_id: string };
        Returns: boolean;
      };
      add_member_to_group_by_username: {
        Args: { p_group_id: string; p_username: string };
        Returns: boolean;
      };
      delete_round: {
        Args: { p_round_id: string };
        Returns: boolean;
      };
      get_friend_count: {
        Args: { p_user_id: string };
        Returns: number | null;
      };
    };
  };
};

const AsyncStorageAdapter = {
  getItem: (key: string) => AsyncStorage.getItem(key),
  setItem: (key: string, value: string) => AsyncStorage.setItem(key, value),
  removeItem: (key: string) => AsyncStorage.removeItem(key),
};

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

export const supabaseConfigError: string | null =
  !SUPABASE_URL || !SUPABASE_ANON_KEY
    ? 'Missing Supabase credentials. EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY must be set at build time.'
    : null;

export const supabase = createClient(
  SUPABASE_URL ?? 'https://missing.supabase.co',
  SUPABASE_ANON_KEY ?? 'missing-anon-key',
  {
    auth: {
      storage: AsyncStorageAdapter,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  },
);

export type TypedSupabaseClient = SupabaseClient;
