import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { cardShadow, colors, radii, spacing, typography } from '../theme';
import { Round } from '../types';

type StatusVariant = 'action' | 'confirmed' | 'booked' | 'completed' | 'declined';

type Props = {
  round: Round;
  onPress?: () => void;
  onRespondYes?: () => void;
  onRespondNo?: () => void;
  myStatus?: 'pending' | 'yes' | 'no';
};

const getInitials = (name: string) => {
  const trimmed = name.trim();
  if (!trimmed) return '?';
  const parts = trimmed.split(' ').filter(Boolean);
  const first = parts[0]?.[0] ?? '?';
  const second = parts.length > 1 ? parts[parts.length - 1]?.[0] ?? '' : '';
  return `${first}${second}`.toUpperCase();
};

type VariantStyle = {
  label: string;
  accent: string;
  surface: string;
  icon: keyof typeof Ionicons.glyphMap;
};

const VARIANT_STYLES: Record<StatusVariant, VariantStyle> = {
  action: {
    label: 'Action Required',
    accent: '#f97316',
    surface: '#fff7ed',
    icon: 'alert-circle',
  },
  confirmed: {
    label: 'Confirmed',
    accent: '#16a34a',
    surface: '#ecfdf3',
    icon: 'checkmark-circle',
  },
  booked: {
    label: 'Booked',
    accent: '#2563eb',
    surface: '#eff6ff',
    icon: 'calendar',
  },
  completed: {
    label: 'Completed',
    accent: '#6b7280',
    surface: '#f3f4f6',
    icon: 'flag',
  },
  declined: {
    label: 'Declined',
    accent: '#dc2626',
    surface: '#fef2f2',
    icon: 'close-circle',
  },
};

export const RoundCard: React.FC<Props> = ({ round, onPress, onRespondYes, onRespondNo, myStatus = 'pending' }) => {
  const committed = round.invites.filter((p) => p.status === 'yes').length;
  const now = new Date();
  const teeTime = new Date(round.teeTime);
  const isPast = !Number.isNaN(teeTime.valueOf()) && teeTime < now;
  const canRespond = !!(onRespondYes && onRespondNo) && !round.locked && !isPast;
  const isPending = myStatus === 'pending';
  const isConfirmed = myStatus === 'yes';
  const isDeclined = myStatus === 'no';

  const variant: StatusVariant = isPast
    ? 'completed'
    : isDeclined
      ? 'declined'
      : isPending && canRespond
        ? 'action'
        : isConfirmed
          ? 'confirmed'
          : 'booked';

  const variantStyles = VARIANT_STYLES[variant];
  const isAction = variant === 'action';

  const showRespond = canRespond;
  const showDetails = !showRespond;
  const avatars = round.invites.slice(0, 3).map((invite) => getInitials(invite.name));

  const renderAvatars = () => (
    <View style={styles.avatarRow}>
      {avatars.map((initials, index) => (
        <View
          key={`${initials}-${index}`}
          style={[
            styles.avatar,
            { marginLeft: index === 0 ? 0 : -8 },
            index === avatars.length - 1 && avatars.length < 3 ? styles.avatarAccent : null,
          ]}
        >
          <Text style={styles.avatarText}>{initials}</Text>
        </View>
      ))}
      {round.invites.length > avatars.length && (
        <View style={[styles.avatar, styles.avatarAccent, { marginLeft: -8 }]}>
          <Text style={styles.avatarText}>+{round.invites.length - avatars.length}</Text>
        </View>
      )}
    </View>
  );

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.card,
        variant === 'completed' && styles.cardMuted,
        isAction && styles.cardAction,
        pressed && styles.pressed,
      ]}
      accessibilityRole="button"
      accessibilityLabel={`${round.course} on ${round.date} at ${round.time}`}
    >
      {/* Left accent strip */}
      <View style={[styles.accentStrip, { backgroundColor: variantStyles.accent }]} />

      <View style={styles.cardContent}>
        <View style={styles.headerRow}>
          <View style={[styles.iconBadge, { backgroundColor: variantStyles.surface }]}>
            <Ionicons name={variantStyles.icon} size={24} color={variantStyles.accent} />
          </View>
          <View style={styles.headerContent}>
            <Text style={[styles.statusPill, { color: variantStyles.accent }]}>{variantStyles.label}</Text>
            <Text style={styles.title} numberOfLines={2}>
              {round.course}
            </Text>
            <Text style={styles.dateTime} numberOfLines={1}>
              {round.date} · {round.time}
            </Text>
            {/* Info pills */}
            <View style={styles.pillRow}>
              <View style={styles.pill}>
                <Text style={styles.pillText}>{round.holes}H</Text>
              </View>
              <View style={styles.pill}>
                <Text style={styles.pillText}>{round.walking ? 'Walking' : 'Riding'}</Text>
              </View>
            </View>
          </View>
        </View>
        <View style={styles.footerRow}>
          {showRespond ? (
            <>
              {renderAvatars()}
              <View style={styles.responseButtons}>
                <Pressable
                  onPress={onRespondNo}
                  style={({ pressed }) => [
                    styles.responseButton,
                    isDeclined ? styles.responseNoActive : styles.responseNo,
                    pressed && styles.responsePressed,
                  ]}
                  accessibilityRole="button"
                  accessibilityLabel="Respond no"
                  accessibilityState={{ selected: isDeclined }}
                >
                  <Text style={isDeclined ? styles.responseNoActiveText : styles.responseNoText}>No</Text>
                </Pressable>
                <Pressable
                  onPress={onRespondYes}
                  style={({ pressed }) => [
                    styles.responseButton,
                    isConfirmed ? styles.responseYesActive : styles.responseYes,
                    pressed && styles.responsePressed,
                  ]}
                  accessibilityRole="button"
                  accessibilityLabel="Respond yes"
                  accessibilityState={{ selected: isConfirmed }}
                >
                  <Text style={isConfirmed ? styles.responseYesActiveText : styles.responseYesText}>Yes</Text>
                </Pressable>
              </View>
            </>
          ) : (
            <>
              {renderAvatars()}
              {showDetails && (
                <Pressable
                  onPress={onPress}
                  style={({ pressed }) => [styles.detailButton, pressed && styles.detailButtonPressed]}
                  accessibilityRole="button"
                  accessibilityLabel="View details"
                >
                  <Text style={styles.detailButtonText}>View Details</Text>
                </Pressable>
              )}
            </>
          )}
        </View>
      </View>
    </Pressable>
  );
};

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.card,
    borderRadius: radii.xl,
    marginBottom: 20,
    borderWidth: 1,
    borderColor: colors.borderLight,
    ...cardShadow,
    overflow: 'hidden',
    flexDirection: 'row',
  },
  cardMuted: {
    opacity: 0.75,
  },
  cardAction: {
    shadowColor: '#f97316',
    shadowOpacity: 0.15,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 8 },
    elevation: 5,
  },
  pressed: {
    opacity: 0.9,
  },
  accentStrip: {
    width: 3,
  },
  cardContent: {
    flex: 1,
    padding: spacing.lg,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
  },
  iconBadge: {
    width: 54,
    height: 54,
    borderRadius: 27,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerContent: {
    flex: 1,
    minWidth: 0,
    gap: 6,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
  },
  statusPill: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  dateTime: {
    fontSize: typography.small,
    color: colors.muted,
  },
  pillRow: {
    flexDirection: 'row',
    gap: 6,
    marginTop: 2,
  },
  pill: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
    backgroundColor: colors.surfaceGreen,
  },
  pillText: {
    fontSize: 11,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  footerRow: {
    marginTop: spacing.md,
    paddingTop: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  avatarRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  avatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    borderWidth: 2,
    borderColor: colors.card,
    backgroundColor: '#d1d5db',
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarAccent: {
    backgroundColor: colors.primary,
  },
  avatarText: {
    fontSize: 10,
    fontWeight: '700',
    color: colors.text,
  },
  responseButtons: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  responseButton: {
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 999,
    borderWidth: 1,
  },
  responsePressed: {
    opacity: 0.85,
  },
  responseYes: {
    backgroundColor: colors.card,
    borderColor: colors.primaryLight,
  },
  responseYesActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    shadowColor: colors.primary,
    shadowOpacity: 0.2,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 5 },
    elevation: 2,
  },
  responseYesText: {
    fontSize: typography.small,
    fontWeight: '700',
    color: colors.primaryDark,
  },
  responseYesActiveText: {
    fontSize: typography.small,
    fontWeight: '700',
    color: colors.text,
  },
  responseNo: {
    backgroundColor: colors.card,
    borderColor: colors.errorLight,
  },
  responseNoActive: {
    backgroundColor: colors.error,
    borderColor: colors.error,
    shadowColor: colors.error,
    shadowOpacity: 0.2,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 5 },
    elevation: 2,
  },
  responseNoText: {
    fontSize: typography.small,
    fontWeight: '700',
    color: colors.error,
  },
  responseNoActiveText: {
    fontSize: typography.small,
    fontWeight: '700',
    color: colors.card,
  },
  detailButton: {
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  detailButtonPressed: {
    opacity: 0.8,
  },
  detailButtonText: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.text,
  },
});
