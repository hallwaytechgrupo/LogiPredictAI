---
sessionId: session-261102-141323-t878
---

# Requirements

### Overview & Goals
Replace the current hub-based map with a geographic map that shows the distribution of Olist orders across Brazilian cities, highlighting areas with higher or lower delay rates. The map will be based exclusively on Olist order, customer, and geolocation data — **never associating orders with simulated hubs**.

### Scope

#### In Scope
- New backend endpoint `/api/v1/analytics/orders-geography` that aggregates Olist orders by city/state using customer location data.
- Metrics per locality: total orders, orders with valid dates, delayed orders, orders without delivery date, delay rate, risk level.
- Risk classification: baixo (0–5%), médio (5–15%), alto (15–30%), muito alto (>30%), sem_dados.
- Risk thresholds centralized in a configuration object in the backend.
- Flutter frontend: new map view consuming the endpoint, with risk-colored markers, legend, tooltips, detail dialog, loading/error/empty states, and UF filter.
- Backend and frontend tests.

#### Out of Scope
- Associating orders with simulated hubs.
- Modifying the ML training pipeline or prediction endpoint.
- Changing the existing `/analytics/hubs` endpoint.
- Modifying original Olist data files.
- Region-level aggregation (unless the architecture makes it trivial).

### Functional Requirements
1. **Geographic aggregation**: Group orders by customer city + state using `customer_zip_code_prefix` → geolocation join.
2. **Delay calculation**: An order is delayed when `order_delivered_customer_date > order_estimated_delivery_date` (calendar date comparison). Orders without `order_delivered_customer_date` are neither delayed nor counted in the denominator.
3. **Risk classification**: Configurable thresholds (0–5% baixo, 5–15% médio, 15–30% alto, >30% muito alto). Localities with no valid-date orders → `sem_dados`.
4. **Map display**: Markers colored by risk level, tooltip with summary, detail dialog with full metrics.
5. **Filters**: Filter by UF (state). Filter by region if compatible.
6. **API response**: Each locality returns city, state, total_orders, orders_with_valid_dates, delayed_orders, orders_without_delivery_date, delay_rate, risk_level, latitude, longitude.

### Non-Functional Requirements
- Aggregation performed in the backend; no raw order transfer to frontend.
- Each order counted exactly once per locality (no duplication from joins).
- Handle null/invalid dates and missing coordinates gracefully.
- Preserve existing project patterns, styles, and technologies.

# Technical Design

### Current Implementation
- **Backend**: `back/src/app.js` (single-file Express app, 1771 lines). Already loads `olist_geolocation_dataset.csv` into a geolocation index (median lat/lng per zip code prefix). The existing `/api/v1/analytics/hubs` endpoint aggregates predictions by hub.
- **Raw data available**: `back/data/raw/` contains `olist_orders_dataset.csv` (with `order_delivered_customer_date`, `order_estimated_delivery_date`), `olist_customers_dataset.csv` (with `customer_zip_code_prefix`, `customer_city`, `customer_state`), and `olist_geolocation_dataset.csv` (coordinates per zip prefix).
- **Frontend**: `flutter_app/lib/screens/dashboard_map_screen.dart` (part of `dashboard_screen.dart`). Uses `FlutterMap` with `MarkerLayer`. Risk colors via `HubRiskBand` enum in `hub_risk_layer_unavailable.dart`. API services follow a pattern: model class + API client class in separate files under `lib/services/`.
- **Tests**: Backend uses `node:test` with a harness that creates temp files and starts the app. Frontend uses `flutter_test`.

### Key Decisions
1. **Read raw Olist CSVs in the backend**: The existing `pedidos_logipredict.csv` lacks `order_delivered_customer_date` and customer location. The new endpoint will read the raw CSVs (`olist_orders_dataset.csv`, `olist_customers_dataset.csv`) and join them with the existing geolocation index to compute delay metrics.
2. **New configurable risk thresholds**: Instead of reusing `HubRiskBand` (which uses 0/50/100% thresholds for prediction-based risk), introduce a new `OrderRiskBand` with the specified thresholds (0–5%, 5–15%, 15–30%, >30%). Centralized in a config object in `app.js`.
3. **Aggregation in the backend**: The endpoint will perform all joins and aggregation server-side, returning only the aggregated results to the frontend.
4. **Reuse existing geolocation index**: The `loadGeolocationIndex()` function already provides city, state, and median coordinates per zip code prefix — perfect for resolving customer locations.
5. **New Flutter service**: Follow the existing pattern (`HubAnalyticsApi` → `hub_analytics_api.dart`) with a new `OrdersGeographyApi` service.

### Proposed Changes

#### Backend (`back/src/app.js`)
- Add a `RISK_THRESHOLDS` config object near the top of `createApp()` with configurable boundaries: `{ low: 5, medium: 15, high: 30 }`.
- Add `classifyOrderRisk(delayRate)` function that returns `'baixo'`, `'medio'`, `'alto'`, `'muito_alto'`, or `'sem_dados'`.
- Add `loadOrdersDataset()` function that reads `olist_orders_dataset.csv` (raw) and parses relevant columns: `order_id`, `customer_id`, `order_delivered_customer_date`, `order_estimated_delivery_date`.
- Add `loadCustomersDataset()` function that reads `olist_customers_dataset.csv` and parses: `customer_id`, `customer_zip_code_prefix`, `customer_city`, `customer_state`.
- Add `GET /api/v1/analytics/orders-geography` endpoint that:
  - Loads orders, customers, and geolocation index.
  - Joins orders → customers (on `customer_id`) → geolocation (on `customer_zip_code_prefix`).
  - Groups by (city, state) and computes metrics.
  - Supports optional `state` query param filter.
  - Returns aggregated results with coordinates.

#### Frontend — New Service (`flutter_app/lib/services/orders_geography_api.dart`)
- `OrderGeographyRecord` model class with fields: city, state, totalOrders, ordersWithValidDates, delayedOrders, ordersWithoutDeliveryDate, delayRate, riskLevel, latitude, longitude.
- `OrderRiskBand` enum: `semDados`, `baixo`, `medio`, `alto`, `muitoAlto`.
- `orderRiskColor(band)` and `orderRiskLabel(band)` helper functions.
- `OrdersGeographyApi` client class with `list({String? state})` method.

#### Frontend — Map Screen (`flutter_app/lib/screens/dashboard_map_screen.dart`)
- Replace hub-based markers with order geography markers.
- Add state to `_DashboardScreenState`: `_orderGeographyData`, `_loadingOrderGeography`, `_orderGeographyError`, `_selectedGeographyState`.
- New `_loadOrderGeography()` method.
- Update `_buildMapPage()` to show order-based markers with risk colors.
- Add UF filter dropdown.
- Add risk legend for `OrderRiskBand`.
- Update detail dialog to show order geography metrics.
- Update map title from "Mapa de Calor Logístico" to "Mapa Geográfico de Pedidos e Atrasos".

#### Frontend — Risk Legend Widget (`flutter_app/lib/widgets/hub_risk_layer_unavailable.dart`)
- Add `OrderRiskBand` enum and associated color/label helpers alongside the existing `HubRiskBand`.

### Data Models / Contracts

#### API Response
```
GET /api/v1/analytics/orders-geography?state=SP

200 OK:
{
  "data": [
    {
      "city": "sao paulo",
      "state": "SP",
      "total_orders": 1234,
      "orders_with_valid_dates": 1100,
      "delayed_orders": 120,
      "orders_without_delivery_date": 134,
      "delay_rate": 10.91,
      "risk_level": "medio",
      "latitude": -23.55,
      "longitude": -46.63
    }
  ],
  "total": 1,
  "filters": { "state": "SP" }
}
```

#### Risk Classification Config
```js
const RISK_THRESHOLDS = { low: 5, medium: 15, high: 30 };
// delayRate <= 5 → 'baixo'
// 5 < delayRate <= 15 → 'medio'
// 15 < delayRate <= 30 → 'alto'
// delayRate > 30 → 'muito_alto'
// ordersWithValidDates === 0 → 'sem_dados'
```

### File Structure
```
Modified:
  back/src/app.js                          — new endpoint + config + helpers
  flutter_app/lib/screens/dashboard_map_screen.dart  — new map view
  flutter_app/lib/screens/dashboard_screen.dart      — new state vars
  flutter_app/lib/widgets/hub_risk_layer_unavailable.dart  — OrderRiskBand helpers

Created:
  flutter_app/lib/services/orders_geography_api.dart  — API service + models
  back/test/analytics_orders_geography.test.js        — backend tests
  flutter_app/test/orders_geography_api_test.dart     — frontend tests
```

# Testing

### Validation Approach
Follow the existing test patterns: backend uses `node:test` with a harness that creates temp CSV files and starts the app; frontend uses `flutter_test` with mock HTTP responses.

### Backend Tests (`back/test/analytics_orders_geography.test.js`)
1. **Delay rate calculation**: Create orders where `delivered > estimated` and verify `delay_rate` is correct.
2. **Risk classification**: Verify thresholds: 0–5% → baixo, 5–15% → medio, 15–30% → alto, >30% → muito_alto.
3. **Orders without delivery date excluded**: Orders with null `order_delivered_customer_date` are not counted as delayed and not in the denominator.
4. **No duplication after joins**: Verify each order is counted once even when multiple items exist.
5. **Aggregation by city and state**: Multiple orders in the same city are aggregated correctly.
6. **State filter**: `?state=SP` returns only SP localities.
7. **Response structure**: Validate all required fields are present.
8. **Localities without coordinates**: Orders whose customer zip prefix has no geolocation entry are excluded from the map data.
9. **sem_dados classification**: A locality with orders but no valid dates → `sem_dados`.

### Frontend Tests (`flutter_app/test/orders_geography_api_test.dart`)
1. **Model parsing**: `OrderGeographyRecord.fromJson()` parses valid JSON correctly.
2. **Risk band classification**: `orderRiskBand()` returns correct band for each threshold.
3. **API client**: `OrdersGeographyApi.list()` makes the correct request and parses the response.
4. **Error handling**: Invalid response throws appropriate exception.
5. **State filter**: `list(state: 'SP')` includes the query param.

# Delivery Steps

### ✓ Step 1: Backend: risk config, CSV loaders, and /analytics/orders-geography endpoint
Add the new endpoint to `back/src/app.js` that aggregates Olist orders by customer city/state with delay metrics.
- Add `RISK_THRESHOLDS` config and `classifyOrderRisk()` helper near the top of `createApp()`.
- Add `loadOrdersDataset()` to read and parse `olist_orders_dataset.csv` (order_id, customer_id, order_delivered_customer_date, order_estimated_delivery_date).
- Add `loadCustomersDataset()` to read and parse `olist_customers_dataset.csv` (customer_id, customer_zip_code_prefix, customer_city, customer_state).
- Implement `GET /api/v1/analytics/orders-geography` endpoint: join orders → customers → geolocation index, group by (city, state), compute metrics, apply risk classification, support `?state=` filter.
- Ensure each order is counted exactly once (no duplication from joins).
- Handle null dates, invalid coordinates, and missing geolocation gracefully.
- Create `back/test/analytics_orders_geography.test.js` with tests for: delay rate calculation, risk classification thresholds, orders without delivery date exclusion, no duplication, aggregation, state filter, response structure, and sem_dados classification.

### ✓ Step 2: Frontend: OrdersGeographyApi service and OrderRiskBand helpers
Create the Flutter API service and risk classification helpers for the orders geography feature.
- Create `flutter_app/lib/services/orders_geography_api.dart` with:
  - `OrderGeographyRecord` model class (city, state, totalOrders, ordersWithValidDates, delayedOrders, ordersWithoutDeliveryDate, delayRate, riskLevel, latitude, longitude).
  - `OrderRiskBand` enum: semDados, baixo, medio, alto, muitoAlto.
  - `orderRiskBand()`, `orderRiskColor()`, `orderRiskLabel()` helpers.
  - `OrdersGeographyApi` client with `list({String? state})` method.
- Add `OrderRiskBand` helpers to `flutter_app/lib/widgets/hub_risk_layer_unavailable.dart` alongside existing `HubRiskBand`.
- Create `flutter_app/test/orders_geography_api_test.dart` with tests for model parsing, risk band classification, API client request, and error handling.

### ✓ Step 3: Frontend: Replace map view with order geography data
Update the Flutter map screen to consume the new orders geography endpoint and display order-based markers.
- Add state variables to `_DashboardScreenState` in `dashboard_screen.dart`: `_orderGeographyData`, `_loadingOrderGeography`, `_orderGeographyError`, `_selectedGeographyState`.
- Add `_loadOrderGeography()` method that calls `OrdersGeographyApi.list()`.
- Update `_buildMapPage()` in `dashboard_map_screen.dart`:
  - Replace hub markers with order geography markers (colored by `OrderRiskBand`).
  - Update map title to "Mapa Geográfico de Pedidos e Atrasos".
  - Add UF filter dropdown.
  - Add risk legend for `OrderRiskBand` values.
  - Update detail dialog to show: city, state, total orders, delayed orders, delay rate, risk level, orders without delivery date.
  - Handle loading, error, and empty states.
  - Use `FlutterMap` with `MarkerLayer` (same pattern as current implementation).
  - Fit camera to all marker points on load.

---

## NEW TASK: Refactor map to region-level choropleth

### ✓ Step 4: Backend - new /analytics/orders-geography/regions endpoint
Add new endpoint aggregating orders by Brazilian region (Norte, Nordeste, Centro-Oeste, Sudeste, Sul).
- Add UF-to-region mapping constant in `app.js`.
- Reuse existing CSV loaders and classification helpers.
- Return region metrics + per-state breakdown sorted by delay rate.
- Create backend tests.

### ✓ Step 5: Frontend - add flutter_map_geojson2 package and region GeoJSON assets
- Add `flutter_map_geojson2` to `pubspec.yaml`.
- Download Brazilian region GeoJSON from GeoFabrik, add as assets.
- Create `flutter_app/lib/services/orders_region_api.dart` with model + API client.

### ✓ Step 6: Frontend - replace map view with choropleth
- Rewrite `dashboard_map_screen.dart` to use `GeoJsonLayer` with 5 region polygons colored by risk.
- Update title to "Mapa de Retenção e Gargalos Logísticos".
- Add tap interaction, region detail dialog with UF breakdown.
- Remove city markers and UF filter.
- Add region state vars to `dashboard_screen.dart`.

### ✓ Step 7: Fix flutter_map_geojson2 package version
- Downgrade `flutter_map_geojson2` from `^8.0.0` to `^1.0.2` in `pubspec.yaml` (v8 doesn't exist).
- Update `dashboard_map_screen.dart` to use the correct v1.0.2 API: `GeoJsonLayer.asset()` instead of `GeoJsonLayer(GeoJsonSource.asset())`, 3-parameter `onPolygon` callback.
- Fix polygon tap interaction: `flutter_map` v7.0.2 `Polygon` has no `tapCallback` — use `LayerHitNotifier<String>` with `hitValue` on each `Polygon<String>` and `onTap` on `MapOptions` instead.
- Add `_regionHitNotifier` field to `_DashboardScreenState` with proper disposal.

---

## NEW TASK: Improve region visualization

### ✓ Step 8: Improve map visual clarity with fixed region colors and IBGE geometries
Replace risk-based region colors with fixed geographic colors and improve GeoJSON quality.
- Add `REGION_FIXED_COLORS` map in `hub_risk_layer_unavailable.dart` with distinct colors per region (Norte=green, Nordeste=red, Centro-Oeste=blue, Sudeste=orange, Sul=purple).
- Add `orderRiskShortLabel()` helper for compact risk badges.
- Update `dashboard_map_screen.dart`:
  - Use fixed region colors for polygon fill (35% opacity) and borders (2.5px).
  - Add region name labels with risk badges using `MarkerLayer` at approximate centroids.
  - Replace single risk legend with two legends: region colors + risk badge colors.
  - Update attribution from "GeoFabrik (OpenStreetMap)" to "IBGE (Malha Territorial)".
- Replace `brazil_regions.geojson` with IBGE official state boundaries dissolved into 5 regions using `shapely.unary_union`, simplified to 122K.
- Remove old individual region GeoJSON files (norte.geojson, nordeste.geojson, etc.).

---

## NEW TASK: Add hub layer to regional map

### ✓ Step 9: Add hub marker layer with visibility toggle to regional map
Add simulated hubs as an independent visual layer on top of region polygons.
- Add `_showHubLayer` boolean state variable in `dashboard_screen.dart`, defaulting to `true`.
- Add `_hubHitNotifier` (`LayerHitNotifier<LogisticHub>`) in `dashboard_screen.dart` with proper disposal.
- Update `dashboard_map_screen.dart`:
  - Add `MarkerLayer` for hubs above `GeoJsonLayer` but below region labels, using `Icons.warehouse` or `Icons.local_shipping` as marker icon.
  - Filter hubs by `hasValidCoordinates` and only include active hubs (`isActive`).
  - Color hub markers by status: green for active, gray for inactive.
  - Use `_hubHitNotifier` for tap interaction on hub markers.
  - Add hub detail dialog showing: name, city, state, status, classification/provisionalCategory.
  - Add visibility toggle (checkbox or switch) in the map header to show/hide the hub layer.
  - Add hub legend item showing the warehouse icon with label "Hubs logísticos (simulados)".
  - Ensure hubs are visually above region polygons but do not interfere with region tap detection.
  - Preserve map performance: no clustering needed if hub count is small (<50).