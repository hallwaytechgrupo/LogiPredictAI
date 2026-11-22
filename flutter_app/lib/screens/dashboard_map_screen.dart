part of 'dashboard_screen.dart';

/// O workspace mantém os campos e desmonta o mapa que não estiver visível.
extension _DashboardMapScreen on _DashboardScreenState {
  Widget _buildMapPage() {
    return MapWorkspaceScreen(
        active: _tab == 1,
        historyBuilder: (active) => LogisticsHeatMap(
              active: active,
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
              onToggleHubLayer: _setMapHubLayer,
            ));
  }
}
