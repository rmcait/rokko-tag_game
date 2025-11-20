class AppConstants {
  const AppConstants._();

  static const appName = 'Tag Game';
  static const mockApiDelay = Duration(milliseconds: 300);
  static const bool seedLobbyWithMockMembers = true;
  static const int lobbyMockMemberCount = 3;
  // Items / mock toggle
  static const bool useMockItems = true;
  // When using the FREEZE_TAGGER item: trigger radius (meters) and freeze duration (seconds)
  static const double itemFreezeRadiusMeters = 5.0;
  static const int itemFreezeDurationSeconds = 5;
  // When using the SEE_TAGGER item: how long (seconds) the tagger location is revealed
  static const int itemSeeTaggerDurationSeconds = 3;
  // Tagger reveal ability: how many meters the tagger must walk to charge
  static const double taggerRevealRequiredMeters = 300.0;
  // How long (seconds) runners' positions are revealed when tagger activates
  static const int taggerRevealDurationSeconds = 3;
  // Mock UI toggle: when true, navigation goes to a placeholder play screen
  static const bool useMockUi = true;
}
