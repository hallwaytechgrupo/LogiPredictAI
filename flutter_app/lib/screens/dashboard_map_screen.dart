part of 'dashboard_screen.dart';

/// Delegates to the standalone [LogisticsHeatMap] widget so that the
/// FlutterMap is NOT recreated on every dashboard `setState`.
/// This prevents the expensive hit-testing and pointer-event processing
/// cascade that freezes the app when the user changes the browser zoom.
extension _DashboardMapScreen on _DashboardScreenState {
  Widget _buildMapPage() {
    return LogisticsHeatMap(
      regionOrderData: _regionOrderData,
      mapHubs: _mapHubs,
      showHubLayer: _showHubLayer,
      loading: _loadingRegions,
      error: _regionError,
      onRegionTap: (record) => _showRegionDetails(record),
      onHubTap: (hub) => _showHubDetails(hub),
      onRefresh: () {
        _loadRegions();
        _loadMapHubs();
      },
      onToggleHubLayer: (value) => setState(() => _showHubLayer = value),
    );
  }
}
