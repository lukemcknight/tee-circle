import React, { useMemo, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import DateTimePicker, {
  AndroidNativeProps,
  IOSNativeProps,
} from '@react-native-community/datetimepicker';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../theme';
import { ParsedIntent, RootStackParamList } from '../navigation/types';

type Props = NativeStackScreenProps<RootStackParamList, 'TeeTimeReview'>;

const LOW_CONFIDENCE = 0.6;
const GENERIC_QUERY = 'local';

const parseIsoDate = (iso: string): Date => {
  const [y, m, d] = iso.split('-').map(Number);
  const date = new Date();
  date.setFullYear(y || date.getFullYear(), (m || 1) - 1, d || 1);
  date.setHours(0, 0, 0, 0);
  return date;
};

const toIsoDate = (date: Date): string => {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
};

const parseHhMm = (hhmm: string): Date => {
  const [h, m] = hhmm.split(':').map(Number);
  const date = new Date();
  date.setHours(Number.isFinite(h) ? h : 6, Number.isFinite(m) ? m : 0, 0, 0);
  return date;
};

const toHhMm = (date: Date): string => {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const formatTimeLabel = (hhmm: string): string =>
  parseHhMm(hhmm).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });

type PickerTarget = 'date' | 'timeStart' | 'timeEnd' | null;

export const TeeTimeReviewScreen: React.FC<Props> = ({ navigation, route }) => {
  const { intent, transcript } = route.params;

  const [courseQuery, setCourseQuery] = useState(
    intent.courseQuery === GENERIC_QUERY ? '' : intent.courseQuery,
  );
  const [date, setDate] = useState(intent.date);
  const [timeStart, setTimeStart] = useState(intent.timeStart);
  const [timeEnd, setTimeEnd] = useState(intent.timeEnd);
  const [players, setPlayers] = useState(() => Math.min(4, Math.max(1, intent.players || 1)));
  const [holes, setHoles] = useState<9 | 18 | null>(intent.holes);
  // Not part of ParsedIntent — booking (B5) will consume this preference.
  const [walking, setWalking] = useState(false);
  const [picker, setPicker] = useState<PickerTarget>(null);

  const uncertain = intent.needsClarification || intent.confidence < LOW_CONFIDENCE;

  const dateLabel = useMemo(
    () =>
      parseIsoDate(date).toLocaleDateString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
      }),
    [date],
  );

  const handlePickerChange: IOSNativeProps['onChange'] & AndroidNativeProps['onChange'] = (
    _event,
    selected,
  ) => {
    if (!selected) return;
    if (picker === 'date') setDate(toIsoDate(selected));
    else if (picker === 'timeStart') setTimeStart(toHhMm(selected));
    else if (picker === 'timeEnd') setTimeEnd(toHhMm(selected));
  };

  const onConfirm = () => {
    const trimmedCourse = courseQuery.trim();
    const edited: ParsedIntent = {
      courseQuery: trimmedCourse.length > 0 ? trimmedCourse : GENERIC_QUERY,
      date,
      // Keep the window ordered even if the user crossed the two pickers.
      timeStart: timeStart <= timeEnd ? timeStart : timeEnd,
      timeEnd: timeStart <= timeEnd ? timeEnd : timeStart,
      players,
      holes,
      needsClarification: false,
      confidence: 1,
    };
    navigation.navigate('TeeTimeResults', { intent: edited });
  };

  const pickerValue =
    picker === 'date'
      ? parseIsoDate(date)
      : picker === 'timeStart'
        ? parseHhMm(timeStart)
        : parseHhMm(timeEnd);

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
        <View style={styles.header}>
          <Pressable onPress={() => navigation.goBack()} style={styles.headerButton}>
            <Text style={styles.cancelText}>Cancel</Text>
          </Pressable>
          <Text style={styles.headerTitle}>Confirm Search</Text>
          <View style={styles.headerButton} />
        </View>
      </SafeAreaView>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={[styles.scrollContent, picker !== null && styles.scrollContentWithPicker]}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.transcriptCard}>
          <Ionicons name="mic-outline" size={16} color={colors.muted} />
          <Text style={styles.transcriptText} numberOfLines={3}>
            &ldquo;{transcript}&rdquo;
          </Text>
        </View>

        {uncertain && (
          <View style={styles.warningBanner}>
            <Ionicons name="alert-circle-outline" size={18} color={colors.error} />
            <Text style={styles.warningText}>
              We weren&apos;t sure we got that right — please double-check the details below.
            </Text>
          </View>
        )}

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Search Details</Text>

          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Course</Text>
            <View style={[styles.inputWrapper, uncertain && styles.inputUncertain]}>
              <Ionicons name="search" size={18} color={colors.muted} />
              <TextInput
                style={styles.textInput}
                placeholder="Any course near me"
                placeholderTextColor={colors.placeholder}
                value={courseQuery}
                onChangeText={setCourseQuery}
                returnKeyType="done"
                autoCorrect={false}
                autoCapitalize="words"
              />
            </View>
            <Text style={styles.hint}>Leave blank to search courses near you.</Text>
          </View>

          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Date</Text>
            <Pressable
              style={[styles.inputWrapper, uncertain && styles.inputUncertain]}
              onPress={() => setPicker('date')}
            >
              <Text style={styles.inputText}>{dateLabel}</Text>
              <Ionicons name="calendar-outline" size={18} color={colors.muted} />
            </Pressable>
          </View>

          <View style={styles.row}>
            <View style={styles.halfInput}>
              <Text style={styles.inputLabel}>Earliest</Text>
              <Pressable
                style={[styles.inputWrapper, uncertain && styles.inputUncertain]}
                onPress={() => setPicker('timeStart')}
              >
                <Text style={styles.inputText}>{formatTimeLabel(timeStart)}</Text>
                <Ionicons name="time-outline" size={18} color={colors.muted} />
              </Pressable>
            </View>
            <View style={styles.halfInput}>
              <Text style={styles.inputLabel}>Latest</Text>
              <Pressable
                style={[styles.inputWrapper, uncertain && styles.inputUncertain]}
                onPress={() => setPicker('timeEnd')}
              >
                <Text style={styles.inputText}>{formatTimeLabel(timeEnd)}</Text>
                <Ionicons name="time-outline" size={18} color={colors.muted} />
              </Pressable>
            </View>
          </View>
        </View>

        <View style={styles.divider} />

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Format</Text>

          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Players</Text>
            <View style={[styles.stepperRow, uncertain && styles.inputUncertain]}>
              <Pressable
                style={[styles.stepperButton, players <= 1 && styles.stepperButtonDisabled]}
                onPress={() => setPlayers((p) => Math.max(1, p - 1))}
                disabled={players <= 1}
                accessibilityRole="button"
                accessibilityLabel="Fewer players"
              >
                <Ionicons name="remove" size={20} color={players <= 1 ? colors.inactive : colors.text} />
              </Pressable>
              <View style={styles.stepperValue}>
                <Text style={styles.stepperValueText}>
                  {players} {players === 1 ? 'player' : 'players'}
                </Text>
              </View>
              <Pressable
                style={[styles.stepperButton, players >= 4 && styles.stepperButtonDisabled]}
                onPress={() => setPlayers((p) => Math.min(4, p + 1))}
                disabled={players >= 4}
                accessibilityRole="button"
                accessibilityLabel="More players"
              >
                <Ionicons name="add" size={20} color={players >= 4 ? colors.inactive : colors.text} />
              </Pressable>
            </View>
          </View>

          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Length</Text>
            <View style={[styles.toggleContainer, uncertain && styles.inputUncertain]}>
              <Pressable
                style={[styles.toggleButton, holes === null && styles.toggleButtonActive]}
                onPress={() => setHoles(null)}
              >
                <Text style={[styles.toggleText, holes === null && styles.toggleTextActive]}>Any</Text>
              </Pressable>
              <Pressable
                style={[styles.toggleButton, holes === 18 && styles.toggleButtonActive]}
                onPress={() => setHoles(18)}
              >
                <Text style={[styles.toggleText, holes === 18 && styles.toggleTextActive]}>18 Holes</Text>
              </Pressable>
              <Pressable
                style={[styles.toggleButton, holes === 9 && styles.toggleButtonActive]}
                onPress={() => setHoles(9)}
              >
                <Text style={[styles.toggleText, holes === 9 && styles.toggleTextActive]}>9 Holes</Text>
              </Pressable>
            </View>
          </View>

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

        <View style={styles.bottomSpacer} />
      </ScrollView>

      <SafeAreaView edges={['bottom']} style={styles.bottomSafeArea}>
        <View style={styles.bottomAction}>
          <Pressable
            style={({ pressed }) => [styles.searchButton, pressed && styles.searchButtonPressed]}
            onPress={onConfirm}
          >
            <Text style={styles.searchButtonText}>Search Tee Times</Text>
            <Ionicons name="search" size={16} color={colors.text} />
          </Pressable>
        </View>
      </SafeAreaView>

      {picker !== null && (
        <View style={styles.pickerOverlay}>
          <View style={styles.pickerHeader}>
            <Text style={styles.pickerTitle}>
              {picker === 'date'
                ? 'Select Date'
                : picker === 'timeStart'
                  ? 'Earliest Tee Time'
                  : 'Latest Tee Time'}
            </Text>
            <Pressable onPress={() => setPicker(null)}>
              <Text style={styles.pickerDone}>Done</Text>
            </Pressable>
          </View>
          <DateTimePicker
            value={pickerValue}
            mode={picker === 'date' ? 'date' : 'time'}
            display="spinner"
            onChange={handlePickerChange}
            minimumDate={picker === 'date' ? new Date() : undefined}
            minuteInterval={picker === 'date' ? undefined : 5}
          />
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
  transcriptCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    padding: 12,
    backgroundColor: colors.surfaceGreen,
    borderRadius: 12,
    marginBottom: 16,
  },
  transcriptText: {
    flex: 1,
    fontSize: 14,
    fontStyle: 'italic',
    color: colors.textSecondary,
  },
  warningBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    padding: 12,
    backgroundColor: colors.errorLight,
    borderRadius: 12,
    marginBottom: 16,
  },
  warningText: {
    flex: 1,
    fontSize: 13,
    fontWeight: '600',
    color: colors.error,
  },
  section: {
    gap: 16,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.text,
    marginLeft: 4,
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
    gap: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  inputUncertain: {
    borderWidth: 1.5,
    borderColor: colors.error,
  },
  textInput: {
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
  hint: {
    marginLeft: 4,
    fontSize: 12,
    color: colors.muted,
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
  stepperRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: 12,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  stepperButton: {
    width: 56,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepperButtonDisabled: {
    opacity: 0.5,
  },
  stepperValue: {
    flex: 1,
    alignItems: 'center',
  },
  stepperValueText: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
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
  searchButton: {
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
  searchButtonPressed: {
    transform: [{ scale: 0.98 }],
    backgroundColor: colors.primaryDark,
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
  searchButtonText: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.text,
  },
});
