/**
 * DOPS Survey - Application Logic
 * Handles step navigation, rating selection, emoji selection, form state,
 * and API submission.
 *
 * Router tarafından initApp(token, surveyData) çağrılarak başlatılır.
 */

/**
 * Ana uygulama başlatma fonksiyonu.
 * Router token'ı parse edip API'den veriyi aldıktan sonra bunu çağırır.
 * @param {string} token - Anket token'ı
 * @param {object} surveyData - API'den gelen anket verisi
 */
function initApp(token, surveyData) {
  // ---- State ----
  let currentStep = 1;
  const totalSteps = 4;

  const state = {
    ratings: { genel: 0, kalite: 0, personel: 0, hiz: 0 },
    experience: null,
    previousUser: null,
    source: null,
    nps: 0,
    comments: { best: '', improve: '', extra: '' }
  };

  // ---- DOM Elements ----
  const stepContents = document.querySelectorAll('.step-content');
  const stepIndicators = document.querySelectorAll('.stepper .step');

  // Navigation buttons
  const btnStep1Next = document.getElementById('btnStep1Next');
  const btnStep2Back = document.getElementById('btnStep2Back');
  const btnStep2Next = document.getElementById('btnStep2Next');
  const btnStep3Back = document.getElementById('btnStep3Back');
  const btnStep3Next = document.getElementById('btnStep3Next');

  // ---- Step Navigation ----
  function goToStep(step) {
    if (step < 1 || step > totalSteps) return;

    // Update step content visibility
    stepContents.forEach(el => el.classList.remove('active'));
    const targetContent = document.getElementById(`step${step}`);
    if (targetContent) {
      targetContent.classList.add('active');
    }

    // Update stepper indicators
    stepIndicators.forEach(el => {
      const stepNum = parseInt(el.dataset.step);
      el.classList.remove('active', 'completed');
      if (stepNum === step) {
        el.classList.add('active');
      } else if (stepNum < step) {
        el.classList.add('completed');
      }
    });

    currentStep = step;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  // Button event listeners
  btnStep1Next.addEventListener('click', () => goToStep(2));
  btnStep2Back.addEventListener('click', () => goToStep(1));
  btnStep2Next.addEventListener('click', () => goToStep(3));
  btnStep3Back.addEventListener('click', () => goToStep(2));

  // ---- Submit Handler ----
  btnStep3Next.addEventListener('click', async () => {
    // Collect textarea values
    const textareas = document.querySelectorAll('.step-3 .text-input');
    if (textareas[0]) state.comments.best = textareas[0].value.trim();
    if (textareas[1]) state.comments.improve = textareas[1].value.trim();
    if (textareas[2]) state.comments.extra = textareas[2].value.trim();

    // Collect radio values
    const previousRadio = document.querySelector('input[name="previous"]:checked');
    if (previousRadio) state.previousUser = previousRadio.value;

    const sourceRadio = document.querySelector('input[name="source"]:checked');
    if (sourceRadio) state.source = sourceRadio.value;

    // Build payload matching Worker API schema
    const overall = state.ratings.genel || 5;
    const quality = state.ratings.kalite || 5;
    const staff = state.ratings.personel || 5;
    const speed = state.ratings.hiz || 5;

    const commentParts = [];
    if (state.comments.best) commentParts.push(`Beğenilen: ${state.comments.best}`);
    if (state.comments.improve) commentParts.push(`Geliştirilebilir: ${state.comments.improve}`);
    if (state.comments.extra) commentParts.push(`Ek: ${state.comments.extra}`);

    const payload = {
      overallRating: overall,
      serviceQualityRating: quality,
      staffCareRating: staff,
      resolutionSpeedRating: speed,
      freeformComment: commentParts.join(" | ") || undefined
    };

    // Set button to loading state
    btnStep3Next.disabled = true;
    btnStep3Next.classList.add('loading');
    const originalText = btnStep3Next.innerHTML;
    btnStep3Next.innerHTML = `
      <span class="spinner"></span>
      Gönderiliyor...
    `;

    // Submit to API
    const result = await SurveyAPI.submitSurvey(token, payload);

    if (result.success) {
      // Success — go to thank you step
      goToStep(4);
    } else {
      // Error — restore button and show error
      btnStep3Next.disabled = false;
      btnStep3Next.classList.remove('loading');
      btnStep3Next.innerHTML = originalText;

      // Show inline error message
      showSubmitError(result.error);
    }
  });

  /**
   * Submit hatası durumunda form footer'da hata mesajı gösterir.
   */
  function showSubmitError(errorCode) {
    // Remove existing error if any
    const existing = document.getElementById('submitError');
    if (existing) existing.remove();

    const errorDiv = document.createElement('div');
    errorDiv.id = 'submitError';
    errorDiv.className = 'submit-error';
    errorDiv.textContent = Router.getErrorMessage(errorCode || 'SERVER_ERROR');

    const formFooter = btnStep3Next.closest('.form-footer');
    if (formFooter) {
      formFooter.parentNode.insertBefore(errorDiv, formFooter);
    }

    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (errorDiv.parentNode) errorDiv.remove();
    }, 5000);
  }

  // ---- Rating Buttons ----
  document.querySelectorAll('.rating-buttons').forEach(group => {
    const category = group.dataset.category;
    const buttons = group.querySelectorAll('.rate-btn');

    buttons.forEach(btn => {
      btn.addEventListener('click', () => {
        const value = parseInt(btn.dataset.value);
        state.ratings[category] = value;

        // Update visual state
        buttons.forEach(b => {
          const bVal = parseInt(b.dataset.value);
          b.classList.remove('selected', 'filled');
          if (bVal === value) {
            b.classList.add('selected');
          } else if (bVal < value) {
            b.classList.add('filled');
          }
        });
      });
    });
  });

  // ---- Emoji Selection ----
  const emojiButtons = document.querySelectorAll('.emoji-btn');
  emojiButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      emojiButtons.forEach(b => b.classList.remove('selected'));
      btn.classList.add('selected');
      state.experience = btn.dataset.value;
    });
  });

  // ---- NPS Buttons ----
  const npsButtons = document.querySelectorAll('.nps-btn');
  npsButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const value = parseInt(btn.dataset.value);
      state.nps = value;

      npsButtons.forEach(b => {
        const bVal = parseInt(b.dataset.value);
        b.classList.remove('selected');
        if (bVal <= value) {
          b.classList.add('selected');
        }
      });
    });
  });

  // ---- Radio Cards ---- (handled by native radio behavior + CSS)

  // ---- Keyboard Navigation ----
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      // Don't trigger if user is typing in a textarea
      if (document.activeElement.tagName === 'TEXTAREA') return;

      if (currentStep < totalSteps) {
        const nextBtns = {
          1: btnStep1Next,
          2: btnStep2Next,
          3: btnStep3Next
        };
        if (nextBtns[currentStep]) {
          nextBtns[currentStep].click();
        }
      }
    }
  });

  // ---- Initialize ----
  goToStep(1);
}
