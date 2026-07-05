import React, { useMemo, useState } from 'react';
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import DateTimePicker, { AndroidNativeProps, IOSNativeProps } from '@react-native-community/datetimepicker';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useData } from '../context/DataContext';
import { useAuth } from '../context/AuthContext';
import { useStoreReview } from '../hooks/useStoreReview';
import { CourseSearchInput } from '../components/CourseSearchInput';
import { CourseSelection } from '../types';

type Props = NativeStackScreenProps<RootStackParamList, 'CreateRound'>;

export const CreateRoundScreen: React.FC<Props> = ({ navigation }) => {
  const { user, profile } = useAuth();
  const { createRound } = useData();
  const { trackRoundCreated } = useStoreReview();
  const [course, setCourse] = useState<CourseSelection | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [dateValue, setDateValue] = useState<Date>(() => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  });
  const [timeValue, setTimeValue] = useState<Date>(() => {
    const d = new Date();
    d.setHours(8, 0, 0, 0);
    return d;
  });
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);
  const [holes, setHoles] = useState<9 | 18>(18);
  const [walking, setWalking] = useState(false);

  const dateLabel = useMemo(
    () =>
      dateValue.toLocaleDateString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
      }),
    [dateValue],
  );

  const timeLabel = useMemo(
    () =>
      timeValue.toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
      }),
    [timeValue],
  );

  const profileInitial =
    profile?.full_name?.trim()?.charAt(0)?.toUpperCase() ||
    profile?.username?.trim()?.charAt(0)?.toUpperCase() ||
    '?';

  const canSave = !!course && course.name.trim().length > 0 && user;

  const createRoundFromForm = async () => {
    if (submitting) return;

    if (!course || !course.name.trim()) {
      Alert.alert('Course required', 'Add a course name to create the round.');
      return;
    }

    if (!user) {
      Alert.alert('Sign in required', 'You need to be signed in to create a round.');
      return;
    }

    setSubmitting(true);
    const teeTime = new Date(dateValue);
    teeTime.setHours(timeValue.getHours(), timeValue.getMinutes(), 0, 0);

    const round = await createRound({
      course: {
        name: course.name.trim(),
        placeId: course.placeId ?? null,
        address: course.address ?? null,
        lat: course.lat ?? null,
        lng: course.lng ?? null,
      },
      teeTime,
      holes,
      walking,
    });

    if (!round) {
      setSubmitting(false);
      Alert.alert('Could not create round', 'Something went wrong. Please try again.');
      return;
    }

    trackRoundCreated();
    navigation.replace('RoundDetail', { roundId: round.id, initialRound: round });
  };

  const onSubmit = async () => {
    await createRoundFromForm();
  };

  const handleDateChange: IOSNativeProps['onChange'] & AndroidNativeProps['onChange'] = (event, selectedDate) => {
    if (!selectedDate) return;
    const newDate = new Date(selectedDate);
    newDate.setHours(0, 0, 0, 0);
    setDateValue(newDate);
  };

  const handleTimeChange: IOSNativeProps['onChange'] & AndroidNativeProps['onChange'] = (event, selectedDate) => {
    if (!selectedDate) return;
    const newTime = new Date(timeValue);
    newTime.setHours(selectedDate.getHours(), selectedDate.getMinutes(), 0, 0);
    setTimeValue(newTime);
  };

  const closePickers = () => {
    setShowDatePicker(false);
    setShowTimePicker(false);
  };

  return (
    <View style={styles.container}>
      {/* Header */}
      <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
        <View style={styles.header}>
          <Pressable onPress={() => navigation.goBack()} style={styles.headerButton}>
            <Text style={styles.cancelText}>Cancel</Text>
          </Pressable>
          <Text style={styles.headerTitle}>New Tee Time</Text>
          <Pressable
            onPress={onSubmit}
            disabled={!canSave || submitting}
            style={styles.headerButton}
          >
            <Text style={[styles.saveText, (!canSave || submitting) && styles.saveTextDisabled]}>
              {submitting ? 'Saving...' : 'Save'}
            </Text>
          </Pressable>
        </View>
      </SafeAreaView>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={[
          styles.scrollContent,
          (showDatePicker || showTimePicker) && styles.scrollContentWithPicker,
        ]}
        showsVerticalScrollIndicator={false}
      >
        {/* Section 1: Course Details */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Course Details</Text>

          {/* Location Input */}
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Location</Text>
            <CourseSearchInput value={course} onChange={setCourse} />
          </View>

          {/* Date & Time Row */}
          <View style={styles.row}>
            <View style={styles.halfInput}>
              <Text style={styles.inputLabel}>Date</Text>
              <Pressable style={styles.inputWrapper} onPress={() => setShowDatePicker(true)}>
                <Text style={[styles.inputText, !dateValue && styles.placeholderText]}>
                  {dateLabel}
                </Text>
                <Ionicons name="calendar-outline" size={18} color={colors.muted} />
              </Pressable>
            </View>
            <View style={styles.halfInput}>
              <Text style={styles.inputLabel}>Time</Text>
              <Pressable style={styles.inputWrapper} onPress={() => setShowTimePicker(true)}>
                <Text style={[styles.inputText, !timeValue && styles.placeholderText]}>
                  {timeLabel}
                </Text>
                <Ionicons name="time-outline" size={18} color={colors.muted} />
              </Pressable>
            </View>
          </View>
        </View>

        <View style={styles.divider} />

        {/* Section 2: Format */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Format</Text>

          {/* Holes Toggle */}
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Length</Text>
            <View style={styles.toggleContainer}>
              <Pressable
                style={[styles.toggleButton, holes === 18 && styles.toggleButtonActive]}
                onPress={() => setHoles(18)}
              >
                <Text style={[styles.toggleText, holes === 18 && styles.toggleTextActive]}>
                  18 Holes
                </Text>
              </Pressable>
              <Pressable
                style={[styles.toggleButton, holes === 9 && styles.toggleButtonActive]}
                onPress={() => setHoles(9)}
              >
                <Text style={[styles.toggleText, holes === 9 && styles.toggleTextActive]}>
                  9 Holes
                </Text>
              </Pressable>
            </View>
          </View>

          {/* Transport Preference */}
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Transport</Text>
            <View style={styles.transportRow}>
              <Pressable
                style={[styles.transportCard, !walking && styles.transportCardActive]}
                onPress={() => setWalking(false)}
              >
                {!walking && <Ionicons name="checkmark" size={16} color={colors.text} />}
                <Text style={styles.transportIcon}>🚗</Text>
                <Text style={[styles.transportLabel, !walking && styles.transportLabelActive]}>
                  Riding
                </Text>
              </Pressable>
              <Pressable
                style={[styles.transportCard, walking && styles.transportCardActive]}
                onPress={() => setWalking(true)}
              >
                {walking && <Ionicons name="checkmark" size={16} color={colors.text} />}
                <Text style={styles.transportIcon}>🚶</Text>
                <Text style={[styles.transportLabel, walking && styles.transportLabelActive]}>
                  Walking
                </Text>
              </Pressable>
            </View>
          </View>
        </View>

        <View style={styles.divider} />

        {/* Section 3: Who's Playing */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Who's Playing?</Text>
            <Text style={styles.playerCount}>1 Player</Text>
          </View>

          {/* Player List */}
          <View style={styles.playerList}>
            {/* Current User (Host) */}
            <View style={styles.playerCard}>
              <View style={styles.playerInfo}>
                <View style={styles.hostAvatar}>
                  <Text style={styles.hostAvatarText}>{profileInitial}</Text>
                </View>
                <View>
                  <Text style={styles.playerName}>You (Host)</Text>
                  <Text style={styles.playerRole}>Organizer</Text>
                </View>
              </View>
              <View style={styles.confirmedBadge}>
                <Text style={styles.confirmedText}>CONFIRMED</Text>
              </View>
            </View>

          </View>
        </View>

        <View style={styles.bottomSpacer} />
      </ScrollView>

      {/* Bottom Action */}
      <SafeAreaView edges={['bottom']} style={styles.bottomSafeArea}>
        <View style={styles.bottomAction}>
          <Pressable
            style={({ pressed }) => [
              styles.createButton,
              pressed && styles.createButtonPressed,
              (!canSave || submitting) && styles.createButtonDisabled,
            ]}
            onPress={onSubmit}
            disabled={!canSave || submitting}
          >
            <Text style={styles.createButtonText}>
              {submitting ? 'Creating...' : 'Create & Send Invites'}
            </Text>
            {!submitting && <Ionicons name="paper-plane" size={16} color={colors.text} />}
          </Pressable>
        </View>
      </SafeAreaView>

      {/* Date/Time Picker */}
      {(showDatePicker || showTimePicker) && (
        <View style={styles.pickerOverlay}>
          <View style={styles.pickerHeader}>
            <Text style={styles.pickerTitle}>
              {showDatePicker ? 'Select Date' : 'Select Time'}
            </Text>
            <Pressable onPress={closePickers}>
              <Text style={styles.pickerDone}>Done</Text>
            </Pressable>
          </View>
          {showDatePicker && (
            <DateTimePicker
              value={dateValue}
              mode="date"
              display="spinner"
              onChange={handleDateChange}
              minimumDate={new Date()}
            />
          )}
          {showTimePicker && (
            <DateTimePicker
              value={timeValue}
              mode="time"
              display="spinner"
              onChange={handleTimeChange}
              minuteInterval={5}
            />
          )}
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  headerSafeArea: {
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  headerButton: {
    minWidth: 60,
  },
  cancelText: {
    fontSize: 16,
    fontWeight: '500',
    color: colors.muted,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
  },
  saveText: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.primary,
    textAlign: 'right',
  },
  saveTextDisabled: {
    opacity: 0.5,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 16,
    paddingTop: 24,
  },
  scrollContentWithPicker: {
    paddingBottom: 300,
  },
  section: {
    gap: 16,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.text,
    marginLeft: 4,
  },
  playerCount: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.muted,
  },
  inputGroup: {
    gap: 8,
  },
  inputLabel: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.muted,
    marginLeft: 4,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 48,
    backgroundColor: colors.card,
    borderRadius: 12,
    paddingHorizontal: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  inputIcon: {
    fontSize: 18,
    marginRight: 12,
    opacity: 0.5,
  },
  inputIconRight: {
    fontSize: 18,
    opacity: 0.5,
  },
  input: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: colors.text,
  },
  inputText: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: colors.text,
  },
  placeholderText: {
    color: colors.placeholder,
  },
  row: {
    flexDirection: 'row',
    gap: 16,
  },
  halfInput: {
    flex: 1,
    gap: 8,
  },
  divider: {
    height: 1,
    backgroundColor: colors.border,
    marginVertical: 24,
  },
  toggleContainer: {
    flexDirection: 'row',
    backgroundColor: colors.border,
    borderRadius: 12,
    padding: 4,
  },
  toggleButton: {
    flex: 1,
    height: 40,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  toggleButtonActive: {
    backgroundColor: colors.primary,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  toggleText: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.muted,
  },
  toggleTextActive: {
    fontWeight: '700',
    color: colors.text,
  },
  transportRow: {
    flexDirection: 'row',
    gap: 12,
  },
  transportCard: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 16,
    backgroundColor: colors.card,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: 'transparent',
    position: 'relative',
  },
  transportCardActive: {
    borderColor: colors.primary,
    backgroundColor: 'rgba(19, 236, 91, 0.05)',
  },
  checkIcon: {
    position: 'absolute',
    top: 8,
    right: 8,
    fontSize: 14,
    color: colors.primary,
    fontWeight: '700',
  },
  transportIcon: {
    fontSize: 24,
    marginBottom: 4,
  },
  transportLabel: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.muted,
  },
  transportLabelActive: {
    color: colors.text,
  },
  playerList: {
    gap: 12,
  },
  playerCard: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 12,
    backgroundColor: colors.card,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  playerInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  hostAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.text,
    alignItems: 'center',
    justifyContent: 'center',
  },
  hostAvatarText: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.card,
  },
  playerName: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.text,
  },
  playerRole: {
    fontSize: 12,
    color: colors.muted,
  },
  confirmedBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: 'rgba(19, 236, 91, 0.15)',
    borderRadius: 4,
  },
  confirmedText: {
    fontSize: 11,
    fontWeight: '700',
    color: colors.secondary,
  },
  addButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    padding: 16,
    borderWidth: 2,
    borderStyle: 'dashed',
    borderColor: colors.border,
    borderRadius: 12,
  },
  addIconCircle: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  addIcon: {
    fontSize: 20,
    fontWeight: '600',
    color: colors.muted,
  },
  addButtonText: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.muted,
  },
  bottomSpacer: {
    height: 120,
  },
  bottomSafeArea: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: colors.background,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  bottomAction: {
    padding: 16,
  },
  createButton: {
    height: 56,
    backgroundColor: colors.primary,
    borderRadius: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 8,
    elevation: 4,
  },
  createButtonPressed: {
    transform: [{ scale: 0.98 }],
    backgroundColor: colors.primaryDark,
  },
  createButtonDisabled: {
    opacity: 0.5,
  },
  createButtonText: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
  },
  createButtonIcon: {
    fontSize: 18,
  },
  pickerOverlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: colors.background,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    borderTopWidth: 1,
    borderColor: colors.border,
    paddingBottom: 34,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -4 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 8,
  },
  pickerHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  pickerTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
  },
  pickerDone: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.primary,
  },
});
