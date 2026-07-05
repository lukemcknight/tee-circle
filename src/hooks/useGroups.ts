import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Group, GroupMember } from '../types';
import { useAuth } from '../context/AuthContext';
import { withSupabaseRetry } from '../utils/retry';

type GroupMembershipRow = {
  group_id: string;
  groups: { id: string; name: string } | null;
};

type GroupMemberRow = {
  group_id: string;
  user_id: string;
  profiles: {
    id: string;
    full_name: string | null;
    username: string | null;
  } | null;
};

export const useGroups = () => {
  const { user, initializing } = useAuth();
  const [groups, setGroups] = useState<Group[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchGroups = useCallback(async () => {
    if (!user) {
      setGroups([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // Fetch membership and created groups in parallel with retry
      const [membershipResult, createdResult] = await Promise.all([
        withSupabaseRetry(() =>
          supabase
            .from('group_members')
            .select('group_id, groups(id, name)')
            .eq('user_id', user.id)
        ),
        withSupabaseRetry(() =>
          supabase
            .from('groups')
            .select('id, name')
            .eq('created_by', user.id)
        ),
      ]);

      // If both queries failed, set error state
      if (membershipResult.error && createdResult.error) {
        setError('Connection failed after retries');
        setGroups([]);
        return;
      }

      const membership = membershipResult.data ?? [];
      const createdList = createdResult.data ?? [];

      const groupIds = new Set<string>();
      (membership as unknown as GroupMembershipRow[]).forEach((m) => groupIds.add(m.group_id));
      createdList.forEach((g: { id: string }) => groupIds.add(g.id));

      const groupIdList = Array.from(groupIds);
      if (groupIdList.length === 0) {
        setGroups([]);
        return;
      }

      const membersResult = await withSupabaseRetry(() =>
        supabase
          .from('group_members')
          .select('group_id, user_id, profiles(id, full_name, username)')
          .in('group_id', groupIdList)
      );

      // If members fetch failed, show groups without member details
      const members = membersResult.data ?? [];
      if (membersResult.error) {
        // Partial failure: show groups but flag the error
        setError('Could not load group members');
      }

      const groupedMembers = new Map<string, GroupMember[]>();
      (members as unknown as GroupMemberRow[]).forEach((member) => {
        const list = groupedMembers.get(member.group_id) ?? [];
        list.push({ user_id: member.user_id, profile: member.profiles });
        groupedMembers.set(member.group_id, list);
      });

      const nextGroups: Group[] = (membership as unknown as GroupMembershipRow[])
        .map((m) => ({
          id: m.groups?.id ?? m.group_id,
          name: m.groups?.name ?? 'Group',
          members: groupedMembers.get(m.group_id) ?? [],
        }))
        .concat(
          createdList.map((g) => ({
            id: g.id,
            name: g.name ?? 'Group',
            members: groupedMembers.get(g.id) ?? [],
          })),
        )
        .filter((g, index, arr) => arr.findIndex((other) => other.id === g.id) === index);

      setGroups(nextGroups);
    } catch {
      setError('Unexpected error loading groups');
      setGroups([]);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    if (initializing) return;
    fetchGroups();
  }, [initializing, fetchGroups]);

  return {
    groups,
    loading: loading || initializing,
    error,
    refresh: fetchGroups,
  };
};
