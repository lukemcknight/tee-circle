import React, { useMemo, useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import { BackButton } from '../components/BackButton';
import { PrimaryButton } from '../components/PrimaryButton';
import { useData } from '../context/DataContext';
import { useHandicap } from '../hooks/useHandicap';
import { useStoreReview } from '../hooks/useStoreReview';
import { RootStackParamList } from '../navigation/types';
import { colors, spacing, typography } from '../theme';
import { calculateCourseHandicap } from '../utils/handicap';

type Props = NativeStackScreenProps<RootStackParamList, 'RoundScore'>;

const parsePositiveInt = (value: string) => {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
};

const parsePositiveFloat = (value: string) => {
  const parsed = Number.parseFloat(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
};

type InputCardProps = {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
  placeholder: string;
  keyboardType?: 'default' | 'number-pad' | 'decimal-pad';
  accent?: string;
  hint?: string;
};

const InputCard: React.FC<InputCardProps> = ({
  label,
  value,
  onChangeText,
  placeholder,
  keyboardType = 'default',
  accent = '#d4e3d7',
  hint,
}) => (
  <View style={[styles.inputCard, { borderColor: accent }]}>
    <View style={styles.inputCardHeader}>
      <Text style={styles.inputCardLabel}>{label}</Text>
      {hint ? <Text style={styles.inputCardHint}>{hint}</Text> : null}
    </View>
    <TextInput
      style={styles.inputCardField}
      value={value}
      onChangeText={onChangeText}
      placeholder={placeholder}
      placeholderTextColor={colors.placeholder}
      keyboardType={keyboardType}
    />
  </View>
);

const StatChip: React.FC<{ label: string; value: string; bright?: boolean }> = ({ label, value, bright }) => (
  <View style={[styles.statChip, bright && styles.statChipBright]}>
    <Text style={[styles.statChipLabel, bright && styles.statChipLabelBright]}>{label}</Text>
    <Text style={[styles.statChipValue, bright && styles.statChipValueBright]}>{value}</Text>
  </View>
);

export const RoundScoreScreen: React.FC<Props> = ({ navigation, route }) => {
  const round = route.params.initialRound;
  const { saveScorecard } = useData();
  const { profile: handicapProfile } = useHandicap();
  const { trackScorePosted } = useStoreReview();
  const [grossScore, setGrossScore] = useState('');
  const [courseRating, setCourseRating] = useState(round ? (round.holes === 9 ? '36.0' : '72.0') : '72.0');
  const [slopeRating, setSlopeRating] = useState('113');
  const [par, setPar] = useState(round ? String(round.holes === 9 ? 36 : 72) : '72');
  const [teeName, setTeeName] = useState('');
  const [teeColor, setTeeColor] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const grossScoreValue = parsePositiveInt(grossScore);
  const courseRatingValue = parsePositiveFloat(courseRating);
  const slopeRatingValue = parsePositiveInt(slopeRating);
  const parValue = parsePositiveInt(par);
  const handicapIndex = handicapProfile?.handicapIndex ?? null;

  const projectedCourseHandicap =
    handicapIndex !== null && courseRatingValue && slopeRatingValue && parValue
      ? calculateCourseHandicap({
          handicapIndex,
          courseRating: courseRatingValue,
          slopeRating: slopeRatingValue,
          par: parValue,
        })
      : 0;

  const projectedNet =
    grossScoreValue !== null && Number.isFinite(projectedCourseHandicap)
      ? grossScoreValue - projectedCourseHandicap
      : null;

  const scoreDelta =
    grossScoreValue !== null && parValue !== null ? grossScoreValue - parValue : null;

  const roundDateLabel = useMemo(() => {
    if (!round) return 'Handicap score posting';
    return `${round.date} · ${round.time}`;
  }, [round]);

  const canSubmit = useMemo(
    () => !!(grossScoreValue && courseRatingValue && slopeRatingValue && parValue),
    [grossScoreValue, courseRatingValue, slopeRatingValue, parValue],
  );

  const handleSave = async () => {
    if (!grossScoreValue || !courseRatingValue || !slopeRatingValue || !parValue) {
      Alert.alert('Missing details', 'Add your gross score, rating, slope, and par to post the round.');
      return;
    }

    setSubmitting(true);
    const success = await saveScorecard({
      roundId: route.params.roundId,
      grossScore: grossScoreValue,
      courseRating: courseRatingValue,
      slopeRating: slopeRatingValue,
      par: parValue,
      teeName,
      teeColor,
    });
    setSubmitting(false);

    if (!success) {
      Alert.alert(
        'Could not save score',
        'The scorecard tables may not be applied in Supabase yet, or the save failed. Apply the new SQL files and try again.',
      );
      return;
    }

    trackScorePosted();
    navigation.goBack();
  };

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
          <BackButton onPress={() => navigation.goBack()} />

          <View style={styles.heroWrap}>
            <LinearGradient
              colors={['#0d2418', '#17442a', '#2f8553']}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
              style={styles.hero}
            >
              <View style={styles.orbLarge} />
              <View style={styles.orbSmall} />
              <Text style={styles.heroKicker}>Score Studio</Text>
              <Text style={styles.heroTitle}>Post Your Round</Text>
              <Text style={styles.heroCourse}>{round?.course ?? 'TeeCircle Round'}</Text>
              <Text style={styles.heroMeta}>
                {roundDateLabel}
                {round ? ` · ${round.holes} holes · ${round.walking ? 'Walking' : 'Riding'}` : ''}
              </Text>

              <View style={styles.heroChipRow}>
                <StatChip label="Current HI" value={handicapIndex !== null ? handicapIndex.toFixed(1) : '--'} />
                <StatChip label="Course Hcp" value={String(projectedCourseHandicap)} />
              </View>
            </LinearGradient>

            <View style={styles.scoreDock}>
              <Text style={styles.scoreDockLabel}>Gross Score</Text>
              <TextInput
                style={styles.scoreDockInput}
                value={grossScore}
                onChangeText={setGrossScore}
                keyboardType="number-pad"
                placeholder={round?.holes === 9 ? '42' : '86'}
                placeholderTextColor="#8ca296"
              />
              <Text style={styles.scoreDockHint}>Round total only for Phase 1</Text>
            </View>
          </View>

          <View style={styles.scoreboard}>
            <View style={styles.scoreboardHeader}>
              <Text style={styles.sectionKicker}>Live Preview</Text>
              <Text style={styles.sectionTitle}>What this round posts</Text>
            </View>
            <View style={styles.scoreboardGrid}>
              <StatChip
                label="Projected Net"
                value={projectedNet !== null ? String(projectedNet) : '--'}
                bright
              />
              <StatChip
                label="To Par"
                value={scoreDelta !== null ? `${scoreDelta > 0 ? '+' : ''}${scoreDelta}` : '--'}
                bright
              />
              <StatChip label="Tee" value={teeName.trim() || 'Standard'} />
            </View>
          </View>

          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionKicker}>Course Data</Text>
              <Text style={styles.sectionTitle}>Dial in the handicap math</Text>
              <Text style={styles.sectionBody}>
                Use the card or tee information from the course. These values drive your differential and net score.
              </Text>
            </View>

            <View style={styles.inputGrid}>
              <InputCard
                label="Course Rating"
                value={courseRating}
                onChangeText={setCourseRating}
                placeholder="72.0"
                keyboardType="decimal-pad"
                accent="#bad9c1"
                hint="rating"
              />
              <InputCard
                label="Slope"
                value={slopeRating}
                onChangeText={setSlopeRating}
                placeholder="113"
                keyboardType="number-pad"
                accent="#c9d6eb"
                hint="55-155"
              />
              <InputCard
                label="Par"
                value={par}
                onChangeText={setPar}
                placeholder="72"
                keyboardType="number-pad"
                accent="#ead7be"
              />
              <InputCard
                label="Tee Name"
                value={teeName}
                onChangeText={setTeeName}
                placeholder="Blue tees"
                accent="#d9d3eb"
                hint="optional"
              />
            </View>

            <InputCard
              label="Tee Color"
              value={teeColor}
              onChangeText={setTeeColor}
              placeholder="Blue"
              accent="#d8ddd3"
              hint="optional"
            />
          </View>

          <LinearGradient
            colors={['#f2f8f2', '#dfefe2']}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={styles.insightCard}
          >
            <Text style={styles.sectionKicker}>Handicap Engine</Text>
            <Text style={styles.insightTitle}>TeeCircle preview</Text>
            <Text style={styles.insightCopy}>
              Your handicap here is an in-app playing number based on posted differentials. It gives you a usable net foundation for future matches, side games, and wagers.
            </Text>
            <View style={styles.insightRow}>
              <View style={styles.insightMetric}>
                <Text style={styles.insightMetricLabel}>Current HI</Text>
                <Text style={styles.insightMetricValue}>
                  {handicapIndex !== null ? handicapIndex.toFixed(1) : 'Not set'}
                </Text>
              </View>
              <View style={styles.insightMetric}>
                <Text style={styles.insightMetricLabel}>Course Handicap</Text>
                <Text style={styles.insightMetricValue}>{projectedCourseHandicap}</Text>
              </View>
            </View>
          </LinearGradient>

          <View style={styles.footerCard}>
            <Text style={styles.footerTitle}>Lock in this score</Text>
            <Text style={styles.footerBody}>
              Saving will update your round card, create a handicap differential, and refresh your profile handicap snapshot.
            </Text>
            <PrimaryButton
              label={submitting ? 'Saving...' : 'Save Score'}
              onPress={handleSave}
              disabled={!canSubmit || submitting}
            />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#e9efe9',
  },
  flex: {
    flex: 1,
  },
  container: {
    padding: spacing.lg,
    gap: spacing.md,
    paddingBottom: spacing.xl * 2,
  },
  heroWrap: {
    marginBottom: spacing.lg,
  },
  hero: {
    borderRadius: 34,
    padding: spacing.lg,
    paddingBottom: 88,
    overflow: 'hidden',
    shadowColor: '#102818',
    shadowOffset: { width: 0, height: 14 },
    shadowOpacity: 0.2,
    shadowRadius: 24,
    elevation: 10,
  },
  orbLarge: {
    position: 'absolute',
    width: 220,
    height: 220,
    borderRadius: 110,
    backgroundColor: 'rgba(255,255,255,0.08)',
    right: -60,
    top: -40,
  },
  orbSmall: {
    position: 'absolute',
    width: 110,
    height: 110,
    borderRadius: 55,
    backgroundColor: 'rgba(177, 247, 199, 0.14)',
    left: -24,
    bottom: 42,
  },
  heroKicker: {
    color: '#bde7c8',
    fontSize: 12,
    fontWeight: '800',
    textTransform: 'uppercase',
    letterSpacing: 1.4,
  },
  heroTitle: {
    marginTop: 10,
    fontSize: 34,
    lineHeight: 38,
    fontWeight: '900',
    letterSpacing: -1.1,
    color: '#ffffff',
  },
  heroCourse: {
    marginTop: spacing.sm,
    fontSize: 18,
    fontWeight: '700',
    color: '#eefaf1',
  },
  heroMeta: {
    marginTop: 6,
    fontSize: typography.small,
    color: 'rgba(239, 250, 242, 0.8)',
  },
  heroChipRow: {
    flexDirection: 'row',
    gap: spacing.sm,
    marginTop: spacing.lg,
  },
  scoreDock: {
    marginTop: -66,
    marginHorizontal: spacing.md,
    backgroundColor: '#fbfcf8',
    borderRadius: 30,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#d4ddd2',
    shadowColor: '#243328',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.12,
    shadowRadius: 18,
    elevation: 8,
  },
  scoreDockLabel: {
    fontSize: 12,
    fontWeight: '800',
    color: colors.secondary,
    textTransform: 'uppercase',
    letterSpacing: 1.3,
  },
  scoreDockInput: {
    marginTop: 8,
    minWidth: 140,
    textAlign: 'center',
    fontSize: 58,
    lineHeight: 64,
    fontWeight: '900',
    color: '#102216',
    letterSpacing: -2,
    paddingVertical: 0,
  },
  scoreDockHint: {
    marginTop: 2,
    fontSize: 13,
    color: '#6c7e72',
    fontWeight: '600',
  },
  scoreboard: {
    backgroundColor: '#12281b',
    borderRadius: 28,
    padding: spacing.lg,
    gap: spacing.md,
  },
  scoreboardHeader: {
    gap: 4,
  },
  scoreboardGrid: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  sectionCard: {
    backgroundColor: '#fbfbf7',
    borderRadius: 28,
    padding: spacing.lg,
    gap: spacing.md,
    borderWidth: 1,
    borderColor: '#dde3d8',
  },
  sectionHeader: {
    gap: 6,
  },
  sectionKicker: {
    fontSize: 12,
    fontWeight: '800',
    textTransform: 'uppercase',
    letterSpacing: 1.2,
    color: '#5d7c68',
  },
  sectionTitle: {
    fontSize: 26,
    lineHeight: 30,
    fontWeight: '900',
    color: '#102216',
    letterSpacing: -0.8,
  },
  sectionBody: {
    fontSize: typography.small,
    lineHeight: 20,
    color: '#66756b',
  },
  inputGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  inputCard: {
    width: '48%',
    minWidth: 150,
    backgroundColor: '#ffffff',
    borderRadius: 22,
    padding: spacing.md,
    borderWidth: 1.5,
    gap: spacing.sm,
  },
  inputCardHeader: {
    gap: 2,
  },
  inputCardLabel: {
    fontSize: typography.small,
    fontWeight: '800',
    color: '#12261a',
  },
  inputCardHint: {
    fontSize: 11,
    fontWeight: '700',
    color: '#6d7d72',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  inputCardField: {
    minHeight: 48,
    borderRadius: 16,
    backgroundColor: '#f7f8f4',
    paddingHorizontal: spacing.md,
    fontSize: typography.body,
    fontWeight: '700',
    color: '#102216',
  },
  statChip: {
    flex: 1,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    borderRadius: 18,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.sm,
    gap: 4,
  },
  statChipBright: {
    backgroundColor: '#f2fbf4',
    borderColor: '#d3ebd9',
  },
  statChipLabel: {
    fontSize: 11,
    fontWeight: '800',
    textTransform: 'uppercase',
    letterSpacing: 0.8,
    color: 'rgba(255,255,255,0.72)',
  },
  statChipLabelBright: {
    color: '#5d7b69',
  },
  statChipValue: {
    fontSize: 22,
    fontWeight: '900',
    color: '#ffffff',
    letterSpacing: -0.6,
  },
  statChipValueBright: {
    color: '#102216',
  },
  insightCard: {
    borderRadius: 28,
    padding: spacing.lg,
    gap: spacing.md,
    borderWidth: 1,
    borderColor: '#d1e5d5',
  },
  insightTitle: {
    fontSize: 24,
    lineHeight: 28,
    fontWeight: '900',
    color: '#102216',
    letterSpacing: -0.7,
  },
  insightCopy: {
    fontSize: typography.small,
    lineHeight: 20,
    color: '#476053',
  },
  insightRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  insightMetric: {
    flex: 1,
    backgroundColor: 'rgba(255,255,255,0.56)',
    borderRadius: 20,
    padding: spacing.md,
    gap: 6,
  },
  insightMetricLabel: {
    fontSize: 12,
    fontWeight: '800',
    textTransform: 'uppercase',
    letterSpacing: 0.8,
    color: '#4f735b',
  },
  insightMetricValue: {
    fontSize: 28,
    lineHeight: 32,
    fontWeight: '900',
    color: '#12261a',
    letterSpacing: -0.9,
  },
  footerCard: {
    backgroundColor: '#fffefb',
    borderRadius: 28,
    padding: spacing.lg,
    gap: spacing.md,
    borderWidth: 1,
    borderColor: '#e2e1d8',
  },
  footerTitle: {
    fontSize: 24,
    lineHeight: 28,
    fontWeight: '900',
    color: '#102216',
    letterSpacing: -0.8,
  },
  footerBody: {
    fontSize: typography.small,
    lineHeight: 20,
    color: '#67746c',
  },
});
