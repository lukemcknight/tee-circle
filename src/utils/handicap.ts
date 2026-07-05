import { HandicapDifferential } from '../types';

const roundToTenth = (value: number) => Math.round(value * 10) / 10;

export const calculateDifferential = ({
  grossScore,
  courseRating,
  slopeRating,
}: {
  grossScore: number;
  courseRating: number;
  slopeRating: number;
}) => roundToTenth(((grossScore - courseRating) * 113) / slopeRating);

export const calculateHandicapIndex = (differentials: HandicapDifferential[]) => {
  if (differentials.length === 0) return null;

  const values = differentials
    .map((item) => item.differential)
    .filter((value) => Number.isFinite(value))
    .sort((a, b) => a - b);

  if (values.length === 0) return null;

  const countingScores = Math.min(values.length, 8);
  const average = values.slice(0, countingScores).reduce((sum, value) => sum + value, 0) / countingScores;

  return roundToTenth(average);
};

export const calculateCourseHandicap = ({
  handicapIndex,
  slopeRating,
  courseRating,
  par,
}: {
  handicapIndex: number;
  slopeRating: number;
  courseRating: number;
  par: number;
}) => Math.round((handicapIndex * slopeRating) / 113 + (courseRating - par));
