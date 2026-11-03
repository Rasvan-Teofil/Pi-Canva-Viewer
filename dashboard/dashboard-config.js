/*
 * Public dashboard defaults.
 *
 * The bootstrap script or a local deployment may replace this file with
 * site-specific data. Keep it free of credentials: the dashboard is meant to
 * be reachable without a PIN in V1.
 */
window.PI_SCREEN_CONFIG = window.PI_SCREEN_CONFIG || {
  churchName: "ICF Heilbronn",
  logoText: "ICF",
  logoUrl: "./assets/icf-logo.svg",
  timezone: "Europe/Berlin",
  backgroundImage: "",
  weather: {
    location: "Heilbronn",
    latitude: 49.1427,
    longitude: 9.2109,
    refreshMinutes: 30,
  },
  verse: {
    label: "Vers des Tages",
    text: "Der HERR ist mein Hirte, mir wird nichts mangeln.",
    reference: "Psalm 23,1",
  },
  calendar: {
    title: "Demnächst in der Church",
    embedUrl: "",
    events: [
      {
        date: "Sonntag",
        time: "10:30",
        title: "Celebration",
        location: "ICF Heilbronn",
      },
      {
        date: "Mittwoch",
        time: "19:30",
        title: "Connect & Prayer",
        location: "Church Space",
      },
      {
        date: "Freitag",
        time: "19:00",
        title: "Youth",
        location: "ICF Heilbronn",
      },
    ],
  },
};
