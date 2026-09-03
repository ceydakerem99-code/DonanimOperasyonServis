/**
 * DOPS Survey - API Layer
 * Cloudflare Worker API ile iletişim kuran fonksiyonlar.
 * CONFIG.API_BASE_URL'i merkezi config'den alır.
 */
const SurveyAPI = (() => {

  /**
   * Anket verisini API'den çeker.
   * @param {string} token - Anket token'ı (URL'den parse edilir)
   * @returns {Promise<{success: boolean, survey?: object, error?: string}>}
   */
  async function fetchSurvey(token) {
    const url = `${CONFIG.API_BASE_URL}/api/survey/${encodeURIComponent(token)}`;

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'application/json'
        }
      });

      if (!response.ok) {
        if (response.status === 403) {
          return { success: false, error: 'INVALID_TOKEN' };
        }
        if (response.status === 404) {
          return { success: false, error: 'SURVEY_NOT_FOUND' };
        }
        if (response.status === 409) {
          return { success: false, error: 'ALREADY_SUBMITTED' };
        }
        if (response.status === 410) {
          return { success: false, error: 'SURVEY_EXPIRED' };
        }
        return { success: false, error: 'SERVER_ERROR' };
      }

      const data = await response.json();
      return { success: true, survey: data };

    } catch (err) {
      console.error('[SurveyAPI] fetchSurvey error:', err);
      return { success: false, error: 'NETWORK_ERROR' };
    }
  }

  /**
   * Anket cevaplarını API'ye gönderir.
   * @param {string} token - Anket token'ı
   * @param {object} payload - Anket cevapları
   * @returns {Promise<{success: boolean, error?: string}>}
   */
  async function submitSurvey(token, payload) {
    const url = `${CONFIG.API_BASE_URL}/api/survey/${encodeURIComponent(token)}/submit`;

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        if (response.status === 403) {
          return { success: false, error: 'INVALID_TOKEN' };
        }
        if (response.status === 409) {
          return { success: false, error: 'ALREADY_SUBMITTED' };
        }
        if (response.status === 404) {
          return { success: false, error: 'SURVEY_NOT_FOUND' };
        }
        if (response.status === 410) {
          return { success: false, error: 'SURVEY_EXPIRED' };
        }
        return { success: false, error: 'SERVER_ERROR' };
      }

      const data = await response.json();
      return { success: true, ...data };

    } catch (err) {
      console.error('[SurveyAPI] submitSurvey error:', err);
      return { success: false, error: 'NETWORK_ERROR' };
    }
  }

  return { fetchSurvey, submitSurvey };
})();
