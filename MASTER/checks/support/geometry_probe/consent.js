(() => {
  // A capture measures the page a settled visitor sees, not the consent
  // interstitial on top of it. Set the cookie the app's own reader accepts, so
  // the banner never shows; a hidden banner cannot be judged by a geometry or
  // contrast check either, so none depends on seeing it.
  const decided = 'v1|2026-01-01T00:00:00.000Z|';
  document.cookie = 'pub4_consent=' + encodeURIComponent(decided) + '; path=/; max-age=86400';
  // The welcome modal gates on a different key with no cookie equivalent, so
  // answer its one localStorage question and leave every other key alone.
  const read = Storage.prototype.getItem;
  Storage.prototype.getItem = function (key) {
    return String(key).startsWith('pub4:welcome-onboarding:') ? '1' : read.call(this, key);
  };
})();
