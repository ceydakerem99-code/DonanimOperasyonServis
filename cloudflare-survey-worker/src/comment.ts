export type SurveySubmissionPayload = {
  overallRating: number;
  serviceQualityRating: number;
  staffCareRating: number;
  resolutionSpeedRating: number;
  experienceTags?: string[];
  freeformComment?: string;
};

const EXPERIENCE_TAGS = [
  "Hızlı çözüldü",
  "Personel ilgiliydi",
  "Sorun tamamen çözüldü",
  "Bilgilendirme iyiydi",
] as const;

export function isValidRating(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 5;
}

export function normalizeExperienceTags(tags: unknown): string[] {
  if (!Array.isArray(tags)) {
    return [];
  }
  return tags
    .filter((tag): tag is string => typeof tag === "string")
    .map((tag) => tag.trim())
    .filter((tag) => (EXPERIENCE_TAGS as readonly string[]).includes(tag));
}

export function buildStructuredComment(payload: SurveySubmissionPayload): string {
  const lines = [
    `Servis Kalitesi: ${payload.serviceQualityRating}/5`,
    `Personel İlgisi: ${payload.staffCareRating}/5`,
    `Çözüm Hızı: ${payload.resolutionSpeedRating}/5`,
  ];

  const tags = normalizeExperienceTags(payload.experienceTags);
  if (tags.length > 0) {
    lines.push(`Deneyim: ${tags.join(", ")}`);
  }

  const trimmedComment = payload.freeformComment?.trim();
  if (trimmedComment) {
    lines.push(`Yorum: ${trimmedComment}`);
  }

  return lines.join("\n");
}

export function validateSubmissionPayload(
  body: unknown,
): { ok: true; value: SurveySubmissionPayload } | { ok: false; message: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, message: "Geçersiz istek gövdesi." };
  }

  const candidate = body as Record<string, unknown>;
  const overallRating = candidate.overallRating;
  const serviceQualityRating = candidate.serviceQualityRating;
  const staffCareRating = candidate.staffCareRating;
  const resolutionSpeedRating = candidate.resolutionSpeedRating;

  if (
    !isValidRating(overallRating as number) ||
    !isValidRating(serviceQualityRating as number) ||
    !isValidRating(staffCareRating as number) ||
    !isValidRating(resolutionSpeedRating as number)
  ) {
    return { ok: false, message: "Tüm puanlar 1 ile 5 arasında olmalıdır." };
  }

  return {
    ok: true,
    value: {
      overallRating: overallRating as number,
      serviceQualityRating: serviceQualityRating as number,
      staffCareRating: staffCareRating as number,
      resolutionSpeedRating: resolutionSpeedRating as number,
      experienceTags: normalizeExperienceTags(candidate.experienceTags),
      freeformComment:
        typeof candidate.freeformComment === "string"
          ? candidate.freeformComment
          : undefined,
    },
  };
}
