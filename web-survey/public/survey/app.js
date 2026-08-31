const EXPERIENCE_TAGS = [
  "Hızlı çözüldü",
  "Personel ilgiliydi",
  "Sorun tamamen çözüldü",
  "Bilgilendirme iyiydi",
];

const DIMENSIONS = [
  "overall",
  "serviceQuality",
  "staffCare",
  "resolutionSpeed",
];

const ratings = {
  overall: 0,
  serviceQuality: 0,
  staffCare: 0,
  resolutionSpeed: 0,
};

const selectedTags = new Set();

function extractToken() {
  const parts = window.location.pathname.split("/").filter(Boolean);
  const surveyIndex = parts.indexOf("survey");
  if (surveyIndex >= 0 && parts[surveyIndex + 1]) {
    return decodeURIComponent(parts[surveyIndex + 1]);
  }
  const params = new URLSearchParams(window.location.search);
  return params.get("token");
}

function apiBase() {
  return window.SURVEY_API_BASE || "";
}

function show(id) {
  document.getElementById(id)?.classList.remove("hidden");
}

function hide(id) {
  document.getElementById(id)?.classList.add("hidden");
}

function setText(id, value) {
  const element = document.getElementById(id);
  if (element) {
    element.textContent = value;
  }
}

function formatDate(iso) {
  if (!iso) return "—";
  try {
    return new Intl.DateTimeFormat("tr-TR", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(iso));
  } catch {
    return "—";
  }
}

function updateSubmitState() {
  const ready = DIMENSIONS.every((dimension) => ratings[dimension] > 0);
  const button = document.getElementById("submit-button");
  if (button) {
    button.disabled = !ready;
  }
}

function renderStars() {
  document.querySelectorAll(".rating-block").forEach((block) => {
    const dimension = block.dataset.dimension;
    const container = block.querySelector(".stars");
    const selectedLabel = block.querySelector("[data-selected]");
    if (!container || !dimension) return;

    container.innerHTML = "";
    for (let value = 1; value <= 5; value += 1) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "star-button";
      button.setAttribute("aria-label", `${value} yıldız`);
      button.textContent = value <= ratings[dimension] ? "★" : "☆";
      if (value <= ratings[dimension]) {
        button.classList.add("active");
      }
      button.addEventListener("click", () => {
        ratings[dimension] = value;
        if (selectedLabel) {
          selectedLabel.textContent = `${value} / 5`;
        }
        renderStars();
        updateSubmitState();
      });
      container.appendChild(button);
    }
  });
}

function renderExperienceTags() {
  const container = document.getElementById("experience-tags");
  if (!container) return;
  container.innerHTML = "";
  EXPERIENCE_TAGS.forEach((tag) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `chip${selectedTags.has(tag) ? " selected" : ""}`;
    button.textContent = tag;
    button.addEventListener("click", () => {
      if (selectedTags.has(tag)) {
        selectedTags.delete(tag);
      } else {
        selectedTags.add(tag);
      }
      renderExperienceTags();
    });
    container.appendChild(button);
  });
}

async function loadSurvey() {
  const token = extractToken();
  if (!token) {
    hide("state-loading");
    setText("error-message", "Anket bağlantısı bulunamadı.");
    show("state-error");
    return;
  }

  try {
    const response = await fetch(`${apiBase()}/api/survey/${encodeURIComponent(token)}`);
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.message || "Değerlendirme bilgileri yüklenemedi.");
    }

    if (payload.status && payload.status !== "pending") {
      hide("state-loading");
      setText("error-message", "Bu değerlendirme zaten yanıtlanmış veya artık geçerli değil.");
      show("state-error");
      return;
    }

    setText("work-order-number", payload.workOrderNumber || "—");
    setText("customer-name", payload.customerName || "—");
    setText("work-type-label", payload.workTypeLabel || "—");
    setText("completed-at", formatDate(payload.completedAt));

    hide("state-loading");
    show("survey-form");
    renderStars();
    renderExperienceTags();
    updateSubmitState();
    bindSubmit(token);
  } catch (error) {
    hide("state-loading");
    setText("error-message", error.message || "Değerlendirme bilgileri yüklenemedi.");
    show("state-error");
  }
}

function bindSubmit(token) {
  const form = document.getElementById("survey-form");
  const submitError = document.getElementById("submit-error");
  if (!form) return;

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (submitError) {
      submitError.classList.add("hidden");
      submitError.textContent = "";
    }

    const button = document.getElementById("submit-button");
    if (button) {
      button.disabled = true;
      button.textContent = "Gönderiliyor...";
    }

    try {
      const response = await fetch(
        `${apiBase()}/api/survey/${encodeURIComponent(token)}/submit`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            overallRating: ratings.overall,
            serviceQualityRating: ratings.serviceQuality,
            staffCareRating: ratings.staffCare,
            resolutionSpeedRating: ratings.resolutionSpeed,
            experienceTags: Array.from(selectedTags),
            freeformComment: document.getElementById("freeform-comment")?.value || "",
          }),
        },
      );
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(payload.message || "Değerlendirme gönderilemedi.");
      }

      hide("survey-form");
      show("state-success");
    } catch (error) {
      if (submitError) {
        submitError.textContent = error.message || "Değerlendirme gönderilemedi.";
        submitError.classList.remove("hidden");
      }
      if (button) {
        button.disabled = false;
        button.textContent = "Değerlendirmeyi Gönder";
      }
      updateSubmitState();
    }
  });
}

loadSurvey();
