/**
 * DOPS Survey - SPA Router
 * History API tabanlı basit router.
 * /survey/{token} path'ini parse eder, API'den veri çeker, uygulamayı başlatır.
 */
const Router = (() => {
  let _token = null;

  /**
   * URL'den token'ı parse eder.
   * Beklenen format: /survey/{token}
   * @returns {string|null}
   */
  function parseToken() {
    const path = window.location.pathname;
    const match = path.match(/^\/survey\/([^/]+)\/?$/);
    return match ? decodeURIComponent(match[1]) : null;
  }

  /**
   * Hata mesajlarını Türkçe'ye çevirir.
   */
  function getErrorMessage(errorCode) {
    const messages = {
      'SURVEY_NOT_FOUND': 'Bu anket bulunamadı. Lütfen linkinizi kontrol edin.',
      'SURVEY_EXPIRED': 'Bu anketin süresi dolmuş. Artık yanıtlanamaz.',
      'ALREADY_SUBMITTED': 'Bu anket daha önce yanıtlanmış.',
      'NETWORK_ERROR': 'Bağlantı hatası oluştu. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
      'SERVER_ERROR': 'Sunucu hatası oluştu. Lütfen daha sonra tekrar deneyin.',
      'INVALID_TOKEN': 'Geçersiz anket linki. Lütfen size gönderilen linki kullanın.'
    };
    return messages[errorCode] || 'Beklenmeyen bir hata oluştu.';
  }

  /**
   * Hata ekranını gösterir.
   */
  function showError(errorCode) {
    const errorContainer = document.getElementById('errorState');
    const errorMsg = document.getElementById('errorMessage');
    const loadingOverlay = document.getElementById('loadingOverlay');
    const appContent = document.getElementById('appContent');

    if (loadingOverlay) loadingOverlay.classList.remove('active');
    if (appContent) {
      appContent.classList.remove('app-content-visible');
      appContent.classList.add('app-content-hidden');
    }
    if (errorContainer) {
      errorMsg.textContent = getErrorMessage(errorCode);
      errorContainer.classList.add('active');
    }
  }

  /**
   * Loading overlay'i gösterir/gizler.
   */
  function setLoading(show) {
    const loadingOverlay = document.getElementById('loadingOverlay');
    if (loadingOverlay) {
      if (show) {
        loadingOverlay.classList.add('active');
      } else {
        loadingOverlay.classList.remove('active');
      }
    }
  }

  /**
   * Router'ı başlatır. Sayfa yüklendiğinde çağrılır.
   */
  async function init() {
    _token = parseToken();

    // Token yoksa hata göster
    if (!_token) {
      setLoading(false);
      showError('INVALID_TOKEN');
      return;
    }

    // Loading göster
    setLoading(true);

    // API'den anket verisini çek
    const result = await SurveyAPI.fetchSurvey(_token);

    setLoading(false);

    if (!result.success) {
      showError(result.error || 'SERVER_ERROR');
      return;
    }

    // Anket zaten tamamlanmışsa
    if (result.survey && (result.survey.status === 'completed' || result.survey.status === 'submitted')) {
      showError('ALREADY_SUBMITTED');
      return;
    }

    // Anket süresi dolmuşsa
    if (result.survey && result.survey.status === 'expired') {
      showError('SURVEY_EXPIRED');
      return;
    }

    // Başarılı — survey verisini uygulamaya aktar ve UI'ı başlat
    const appContent = document.getElementById('appContent');
    if (appContent) {
      appContent.classList.remove('app-content-hidden');
      appContent.classList.add('app-content-visible');
    }

    // App'i başlat (app.js'deki initApp fonksiyonu)
    if (typeof initApp === 'function') {
      initApp(_token, result.survey || {});
    }
  }

  /**
   * Mevcut token'ı döner.
   */
  function getToken() {
    return _token;
  }

  return { init, getToken, showError, setLoading, getErrorMessage };
})();

// Sayfa yüklendiğinde router'ı başlat
document.addEventListener('DOMContentLoaded', () => {
  Router.init();
});
