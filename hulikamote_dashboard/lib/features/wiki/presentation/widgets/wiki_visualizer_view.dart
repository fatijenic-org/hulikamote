import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/utils/external_apps.dart';
import '../../data/violation_visualizer_data.dart';
import '../../domain/models/violation_visualizer_model.dart';

class WikiVisualizerView extends StatefulWidget {
  final Directory? root;

  const WikiVisualizerView({super.key, this.root});

  @override
  State<WikiVisualizerView> createState() => _WikiVisualizerViewState();
}

class _WikiVisualizerViewState extends State<WikiVisualizerView> {
  ViolationVisualizerModel _selected = kViolationVisualizerList.first;
  int _currentPhase = 0; // 0: Code & Math, 1: Brute Force, 2: First Principle, 3: Setup, 4: Dynamic Visualizer
  String _filterCategory = 'All';
  String _searchQuery = '';

  static const List<String> _categories = ['All', 'Motorcycle', 'Cars', 'Extended'];
  static const List<String> _phases = [
    '0. Code & Math',
    '1. Brute Force',
    '2. First Principle',
    '3. Setup & Geometry',
    '4. Dynamic Simulation',
  ];

  List<ViolationVisualizerModel> get _filteredList {
    return kViolationVisualizerList.where((item) {
      final matchesCategory = _filterCategory == 'All' ||
          item.category.toLowerCase().contains(_filterCategory.toLowerCase());
      final matchesSearch = _searchQuery.isEmpty ||
          item.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.definition.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.tools.any((t) => t.toLowerCase().contains(_searchQuery.toLowerCase()));
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        // ── Master Sidebar ──────────────────────────────────────────────────
        SizedBox(
          width: 280,
          child: Material(
            color: isDark ? const Color(0xFF131722) : const Color(0xFFF8FAFC),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header & Filter Box
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.science_rounded, size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'VIOLATIONS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_filteredList.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Search
                        SizedBox(
                          height: 32,
                          child: TextField(
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Search models...',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[500] : Colors.grey[400],
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 15,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF1B2130) : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Category Filter Pills
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _categories.map((cat) {
                              final isSel = _filterCategory == cat;
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChoiceChip(
                                  label: Text(cat),
                                  labelStyle: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                    color: isSel
                                        ? (isDark ? Colors.white : Colors.black)
                                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                  ),
                                  selected: isSel,
                                  onSelected: (sel) {
                                    if (sel) setState(() => _filterCategory = cat);
                                  },
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Violations List
                  Expanded(
                    child: ListView.separated(
                      itemCount: _filteredList.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                      ),
                      itemBuilder: (context, index) {
                        final item = _filteredList[index];
                        final isSel = _selected.id == item.id;
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            selected: isSel,
                            selectedTileColor: isDark
                                ? theme.colorScheme.primary.withOpacity(0.12)
                                : theme.colorScheme.primary.withOpacity(0.08),
                            title: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                color: isSel
                                    ? (isDark ? Colors.white : theme.colorScheme.primary)
                                    : (isDark ? Colors.grey[200] : const Color(0xFF1E293B)),
                              ),
                            ),
                            subtitle: Text(
                              item.category,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: isSel
                                  ? theme.colorScheme.primary
                                  : (isDark ? const Color(0xFF232A3A) : const Color(0xFFE2E8F0)),
                              child: Text(
                                item.id.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: isSel ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
                                ),
                              ),
                            ),
                            trailing: isSel
                                ? Icon(Icons.arrow_forward_ios_rounded, size: 12, color: theme.colorScheme.primary)
                                : null,
                            onTap: () {
                              setState(() {
                                _selected = item;
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Detail & Simulation Panel ───────────────────────────────────────
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF0F121A) : const Color(0xFFF1F5F9),
            child: Column(
              children: [
                // Top Detail Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF151A26) : Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _selected.title,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.4,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B5CF6).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _selected.category,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF8B5CF6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selected.definition,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ExternalApps.launchVisualizer();
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 13),
                        label: const Text('Launch App'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

                // 5-Phase Navigation Strip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF181E2E) : const Color(0xFFE2E8F0),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _phases.asMap().entries.map((entry) {
                        final phaseIndex = entry.key;
                        final phaseName = entry.value;
                        final isSelected = _currentPhase == phaseIndex;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            onTap: () => setState(() => _currentPhase = phaseIndex),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isDark ? const Color(0xFF2C3549) : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Text(
                                phaseName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Phase Content Area
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildPhaseContent(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseContent(BuildContext context) {
    switch (_currentPhase) {
      case 0:
        return _buildCodeAndMathPhase(context);
      case 1:
        return _buildBruteForcePhase(context);
      case 2:
        return _buildFirstPrinciplePhase(context);
      case 3:
        return _buildSetupGeometryPhase(context);
      case 4:
      default:
        return _buildDynamicSimulationPhase(context);
    }
  }

  Widget _buildCodeAndMathPhase(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tools Chips with Wrap
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Pipeline Stack: ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _selected.tools.map((tool) {
                  return Chip(
                    label: Text(tool),
                    labelStyle: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[200] : Colors.black87,
                    ),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: isDark ? const Color(0xFF1E2638) : Colors.white,
                    side: BorderSide(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Mathematical Formulation Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141926) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calculate_rounded, size: 16, color: Color(0xFF8B5CF6)),
                  const SizedBox(width: 8),
                  Text(
                    'MATHEMATICAL FORMULATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D111A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                  ),
                ),
                child: SelectableText(
                  _selected.mathLatex,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.5,
                    color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Optimized AI Logic Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141926) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text(
                    'OPTIMIZED PIPELINE LOGIC',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                _selected.optimizedLogic,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: isDark ? Colors.grey[200] : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBruteForcePhase(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141926) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFEF4444)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Brute Force Approach & Vulnerabilities',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Why pixel heuristics fail in real CCTV environments',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(isDark ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
            ),
            child: SelectableText(
              _selected.bruteForce,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: isDark ? Colors.grey[200] : const Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Primary Weaknesses:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          _buildBulletPoint('High computational complexity per video frame (O(N) pixel grid scanning)'),
          _buildBulletPoint('Extremely fragile under varying sunlight, camera exposure, and shadows'),
          _buildBulletPoint('False positive rate exceeds 45% during heavy stop-and-go metro traffic'),
        ],
      ),
    );
  }

  Widget _buildFirstPrinciplePhase(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141926) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lightbulb_outline_rounded, size: 18, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'First Principles & Core Invariants',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Invariant geometric and kinetic rules that govern this violation',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(isDark ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
            ),
            child: SelectableText(
              _selected.optimizedLogic,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: isDark ? Colors.grey[200] : const Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Mathematical Axioms Applied:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          _buildBulletPoint('Vector Projection: Centroid displacement dot product against legal lane unit vectors.'),
          _buildBulletPoint('PNPoly Ray-Casting: Point-in-polygon parity test for irregular multi-point intersection zones.'),
          _buildBulletPoint('Temporal Buffering: Requiring N consecutive frame confirmations to eliminate sensor flicker.'),
        ],
      ),
    );
  }

  Widget _buildSetupGeometryPhase(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141926) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.straighten_rounded, size: 18, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Setup & Zone Calibration Constraints',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Geometric parameters and ROI boundary definitions',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSetupParamCard('Camera Angle', '30° - 45° elevation overhead for minimal perspective occlusion'),
          const SizedBox(height: 8),
          _buildSetupParamCard('Minimum Resolution', '1080p @ 30 FPS with minimum 80px vehicle bounding box width'),
          const SizedBox(height: 8),
          _buildSetupParamCard('Zone Definition (ROI)', 'Polygon coordinates normalized [0.0 - 1.0] across aspect ratios'),
          const SizedBox(height: 8),
          _buildSetupParamCard('Temporal Threshold', 'Minimum 5 consecutive frames (~160ms) of consistent violation state'),
        ],
      ),
    );
  }

  Widget _buildDynamicSimulationPhase(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141926) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.motion_photos_on_rounded, size: 32, color: Color(0xFF8B5CF6)),
          ),
          const SizedBox(height: 14),
          Text(
            'Interactive 2D Simulation Canvas',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Text(
              'The physics simulation tests ${_selected.title} in real-time, driving vehicles through calibrated polygons and measuring live vector angles against traffic flow.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? Colors.grey[300] : const Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              await ExternalApps.launchVisualizer();
            },
            icon: const Icon(Icons.play_circle_fill_rounded, size: 16),
            label: const Text('Open Interactive Visualizer Desktop Engine'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[300] : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupParamCard(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2130) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[300] : const Color(0xFF1E293B),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
