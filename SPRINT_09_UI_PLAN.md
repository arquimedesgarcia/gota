# SPRINT 09-UI: GOTA PROTOTYPE VISUAL ADAPTATION — MASTER PLAN

**Status:** ACTIVE  
**Last Updated:** 2026-09-14  
**Estimated Duration:** 14-18 implementation hours + testing  

---

## PHASE 1: Design System Completion (1.5 hours)

### ✓ PHASE 1.1: Add Spacing & Radius Constants to app_theme.dart
- [ ] Add `AppSpacing` class (xs, sm, md, lg, xl)
- [ ] Add `AppRadius` class (sm, md, lg, xl)
- **Status:** NOT STARTED

### ✓ PHASE 1.2: Create app_components.dart with Button/Card Presets
- [ ] Create `lib/shared/widgets/app_components.dart`
- [ ] Define `primaryButtonStyle()` preset
- [ ] Define `secondaryButtonStyle()` preset
- **Status:** NOT STARTED

### ✓ PHASE 1.3: Create GotaStatusBadge Component
- [ ] Create `lib/shared/widgets/gota_status_badge.dart`
- [ ] Implement badge widget (pill shape, semantic colors, 12px text)
- **Status:** NOT STARTED

### ✓ PHASE 1 VERIFICATION
- [ ] `flutter analyze` clean
- [ ] All colors match DESIGN_SYSTEM.md
- [ ] Spacing base is 4dp throughout
- **Status:** NOT STARTED

---

## PHASE 2: Home Screen Adaptation (2.5 hours)

**File:** `lib/features/home/presentation/home_screen.dart`

### ✓ PHASE 2.1: Gradient Header
- [ ] Replace `_GotaHeader` with LinearGradient (170deg, primaryDark → primary)
- [ ] Add decorative blobs (optional)
- [ ] Add location subtitle
- **Status:** NOT STARTED

### ✓ PHASE 2.2: Hero Report Button (64px)
- [ ] Implement large "Reportar fuga" button with icon + dual-line text
- [ ] Style with FilledButton preset from Phase 1
- **Status:** NOT STARTED

### ✓ PHASE 2.3: 2-Column Action Grid
- [ ] Convert "Llegó/Se fue" and "Mapa" to 2-column GridView (96dp height)
- [ ] Apply app_components styling
- **Status:** NOT STARTED

### ✓ PHASE 2.4: Community Stats Card
- [ ] Add 3-column stat display (fugas reportadas/resueltas/validadas)
- [ ] Use semantic colors (primary/success/primaryDark)
- **Status:** NOT STARTED

### ✓ PHASE 2.5: Apply AppSpacing to RecentLeaksList
- [ ] Update padding/margins to use AppSpacing constants
- **Status:** NOT STARTED

### ✓ PHASE 2 VERIFICATION
- [ ] HomeScreen renders without errors
- [ ] All buttons ≥48dp
- [ ] Gradient header displays
- [ ] Recent leaks list renders
- **Status:** NOT STARTED

---

## PHASE 3: Report Flow — Step Indicator (2 hours)

**File:** `lib/features/leaks/presentation/leak_report_screen.dart`

### ✓ PHASE 3.1: Create _StepIndicator Widget
- [ ] New widget with horizontal progress bars (4 steps)
- [ ] Current step: full color bar
- [ ] Completed: full color bar
- [ ] Future: outline bar
- **Status:** NOT STARTED

### ✓ PHASE 3.2: Update Report Header
- [ ] Replace title-only with `_StepIndicator`
- [ ] Show step progress percentage
- **Status:** NOT STARTED

### ✓ PHASE 3.3: Apply to All 5 Steps
- [ ] LocationStepView
- [ ] PhotosStepView
- [ ] DataStepView
- [ ] ReviewStepView
- [ ] ResultStepView
- **Status:** NOT STARTED

### ✓ PHASE 3 VERIFICATION
- [ ] Step indicator renders all 4 steps
- [ ] Progress updates correctly
- [ ] Text readable (≥13px)
- **Status:** NOT STARTED

---

## PHASE 4: Report Flow — Form Layout Refinement (2 hours)

**File:** `lib/features/leaks/presentation/leak_report_screen.dart`

### ✓ PHASE 4.1: Location Step Styling
- [ ] Apply AppSpacing.lg padding
- [ ] Ensure inputs use app_components styling
- **Status:** NOT STARTED

### ✓ PHASE 4.2: Photos Step Styling
- [ ] Keep 3-column grid
- [ ] Apply button preset to upload action
- [ ] Add upload progress indicator if in-flight
- **Status:** NOT STARTED

### ✓ PHASE 4.3: Data Step Styling
- [ ] Municipio/sector/descripción inputs consistency
- [ ] Ensure all fields ≥48dp touch area
- **Status:** NOT STARTED

### ✓ PHASE 4.4: Review Step & Duplicate Detection
- [ ] Summary card styling
- [ ] Duplicate detection card ("¿Ya existe un reporte de fuga cerca?")
- [ ] Two buttons: "Ver reporte" / "Es otra fuga"
- **Status:** NOT STARTED

### ✓ PHASE 4 VERIFICATION
- [ ] All form elements render
- [ ] Validation works (no functional change)
- [ ] Buttons ≥48dp
- [ ] Duplicate flow works
- **Status:** NOT STARTED

---

## PHASE 5: Leak Detail Screen — Photo Carousel (1.5 hours)

**File:** `lib/features/leaks/presentation/leak_detail_screen.dart`

### ✓ PHASE 5.1: Create Photo Carousel Widget
- [ ] Full-width photo display (250dp height)
- [ ] Counter badge ("1 / 3") top-right
- [ ] Navigation arrows/buttons
- **Status:** NOT STARTED

### ✓ PHASE 5.2: Thumbnail Strip
- [ ] 64px thumbnails below carousel
- [ ] Current selected: blue border
- [ ] Tap to navigate
- **Status:** NOT STARTED

### ✓ PHASE 5.3: Validation Progress Bar Styling
- [ ] LinearProgressIndicator with semantic color (success green)
- [ ] Label: "Confirmaciones para cerrar: N de M"
- **Status:** NOT STARTED

### ✓ PHASE 5 VERIFICATION
- [ ] Carousel navigates correctly
- [ ] Counter updates
- [ ] Thumbnail selection works
- [ ] Progress bar displays
- **Status:** NOT STARTED

---

## PHASE 6: Map Screen — Search + Filters + Legend (2 hours)

**File:** `lib/features/map/presentation/map_screen.dart`

### ✓ PHASE 6.1: Search Bar
- [ ] TextField with search icon, placeholder "Buscar sector o municipio"
- [ ] Apply InputDecoration from app_theme.dart
- [ ] Connect to map filter logic
- **Status:** NOT STARTED

### ✓ PHASE 6.2: Filter Chips
- [ ] ChoiceChip for status filters (Activas/Resueltas/Todas)
- [ ] Wrap layout with AppSpacing.sm spacing
- **Status:** NOT STARTED

### ✓ PHASE 6.3: Map Legend
- [ ] Bottom-left corner: colored dots + labels (Activa/Resuelta)
- [ ] Transparent background with border
- **Status:** NOT STARTED

### ✓ PHASE 6.4: Selection Detail Card
- [ ] Bottom-right overlay when marker selected
- [ ] Photo + status badge + title + validation count
- [ ] "Ver detalle" button
- **Status:** NOT STARTED

### ✓ PHASE 6 VERIFICATION
- [ ] Search bar filters leaks
- [ ] Filter chips update map
- [ ] Legend visible
- [ ] Selection card appears/disappears
- [ ] "Ver detalle" navigates
- **Status:** NOT STARTED

---

## PHASE 7: Water Screen Styling (1 hour)

**Files:** `lib/features/water/presentation/water_screen.dart`, `water_register_screen.dart`

### ✓ PHASE 7.1: Button Styling
- [ ] "Llegó" / "Se fue" buttons (64px minimum)
- [ ] Apply app_components presets
- **Status:** NOT STARTED

### ✓ PHASE 7.2: Event List Styling
- [ ] Use GotaStatusBadge for status
- [ ] Apply AppSpacing to tiles
- **Status:** NOT STARTED

### ✓ PHASE 7.3: Stats Card Styling
- [ ] Consistent padding/spacing
- [ ] All text ≥13px
- **Status:** NOT STARTED

### ✓ PHASE 7 VERIFICATION
- [ ] Screen renders with consistent styling
- [ ] Register flow works
- **Status:** NOT STARTED

---

## PHASE 8: Notifications Screen Styling (30 min)

**File:** `lib/features/notifications/presentation/notifications_screen.dart`

### ✓ PHASE 8.1: Tile Styling
- [ ] Apply AppSpacing to tiles
- [ ] Ensure touch targets ≥48dp
- [ ] Unread badge styling (primary color)
- **Status:** NOT STARTED

### ✓ PHASE 8 VERIFICATION
- [ ] Notifications render correctly
- [ ] Mark-read actions work
- **Status:** NOT STARTED

---

## PHASE 9: Testing & Verification (2-3 hours)

### ✓ PHASE 9.1: Automated Tests
- [ ] `flutter analyze` — Zero issues
- [ ] `flutter test` — All tests pass
- **Status:** NOT STARTED

### ✓ PHASE 9.2: Manual Testing on Android
- [ ] Test on 3 device sizes (small, standard, large)
- [ ] Portrait + landscape
- [ ] Network error states
- [ ] Loading states
- [ ] End-to-end flows (report, validation, map, water, notifications)
- **Status:** NOT STARTED

### ✓ PHASE 9.3: Accessibility Verification
- [ ] All buttons/interactive elements ≥48dp
- [ ] Text ≥13sp, readable
- [ ] Color + text for all states
- [ ] SafeArea respected
- **Status:** NOT STARTED

---

## PHASE 10: Documentation & Closure (1 hour)

### ✓ PHASE 10.1: Documentation Updates
- [ ] Update `docs/UX_SPEC.md` — Step indicator pattern
- [ ] Update `docs/DESIGN_SYSTEM.md` — AppSpacing, component presets
- **Status:** NOT STARTED

### ✓ PHASE 10.2: Git Commit & Push
- [ ] Single commit: `feat(sprint-09): adapt UI to new Gota prototype`
- [ ] Comprehensive commit message
- [ ] Push to main
- **Status:** NOT STARTED

### ✓ PHASE 10.3: Final Verification Report
- [ ] Summary of what was implemented
- [ ] What was deferred and why
- [ ] Final status
- **Status:** NOT STARTED

---

## DEFERRED (OUT OF S09-UI SCOPE)

- ❌ HistoryScreen (data exists, no UI needed for MVP)
- ❌ CommunityScreen (requires backend aggregation)
- ❌ PermissionsScreen (design done, low priority)
- ❌ Dark mode
- ❌ Upload progress bar (compression already optimized)
- ❌ Sector breadcrumb hierarchy
- ❌ Water event timeline visualization
- ❌ Notification badge count on tab

---

## EXECUTION NOTES

- Each phase is self-contained
- Phases 2-8 can be parallelized if needed
- Commit after Phase 1 (foundation)
- Then commits per screen (Home, Report, Map, Water, Notifications)
- Final commit after Phase 9-10

---

**Starting:** PHASE 1 — Design System Completion
