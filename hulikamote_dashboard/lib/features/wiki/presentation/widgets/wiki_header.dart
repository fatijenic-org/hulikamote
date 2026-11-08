import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/models/archived_resource.dart';

class WikiHeader extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback? onRefresh;
  final ArchivedResource? selectedArchive;
  final ValueChanged<ArchivedResource?> onSelectArchive;

  const WikiHeader({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    this.onRefresh,
    this.selectedArchive,
    required this.onSelectArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgBar = isDark ? const Color(0xFF0F141F) : Colors.white;
    final borderColor = isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: bgBar,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 860;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Navigation / Action Bar ──────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Workspace Icon & Breadcrumbs
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Workspace',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '/',
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: textMuted.withOpacity(0.6),
                      ),
                    ),
                  ),
                  Text(
                    'Wiki',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  if (selectedArchive != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '/',
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          color: textMuted.withOpacity(0.6),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: selectedArchive!.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selectedArchive!.color.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(selectedArchive!.icon, size: 11, color: selectedArchive!.color),
                          const SizedBox(width: 4),
                          Text(
                            selectedArchive!.title,
                            style: GoogleFonts.lexend(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selectedArchive!.color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => onSelectArchive(null),
                            child: Icon(Icons.close_rounded, size: 12, color: selectedArchive!.color),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // ── Archive Dropdown Menu ────────────────────────────────
                  _buildArchiveDropdown(context, isDark),
                  const SizedBox(width: 8),

                  // ── Offline Badge ────────────────────────────────────────
                  _buildBadge(
                    context,
                    icon: Icons.check_circle_rounded,
                    label: 'Offline Ready',
                    color: const Color(0xFF10B981),
                  ),

                  if (onRefresh != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Reload Wiki',
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      onPressed: onRefresh,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // ── Header Title & Search Row ────────────────────────────────
              if (isCompact) ...[
                _buildTitle(context, isDark),
                const SizedBox(height: 10),
                _buildSearchField(context, isDark, width: double.infinity),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _buildTitle(context, isDark)),
                    const SizedBox(width: 16),
                    _buildSearchField(context, isDark, width: 260),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildArchiveDropdown(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return PopupMenuButton<ArchivedResource>(
      tooltip: 'Access Preserved Resources',
      offset: const Offset(0, 36),
      constraints: const BoxConstraints(minWidth: 340, maxWidth: 440),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
        ),
      ),
      color: isDark ? const Color(0xFF141926) : Colors.white,
      itemBuilder: (context) {
        return [
          PopupMenuItem<ArchivedResource>(
            enabled: false,
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PRESERVED ARCHIVE (6 MODULES)',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: GoogleFonts.lexend(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
          ...ArchivedResource.values.map((res) {
            final isSelected = selectedArchive == res;
            return PopupMenuItem<ArchivedResource>(
              value: res,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: res.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(res.icon, size: 16, color: res.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  res.title,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: GoogleFonts.lexend(
                                    fontSize: 12.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.check_rounded, size: 14, color: theme.colorScheme.primary),
                              ],
                            ],
                          ),
                          Text(
                            res.subtitle,
                            style: GoogleFonts.lexend(
                              fontSize: 11,
                              color: textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B2232) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark ? const Color(0x26FFFFFF) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        res.badge,
                        style: GoogleFonts.lexend(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: res.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ];
      },
      onSelected: onSelectArchive,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selectedArchive != null
              ? selectedArchive!.color.withOpacity(0.12)
              : (isDark ? const Color(0xFF19202E) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selectedArchive != null
                ? selectedArchive!.color.withOpacity(0.4)
                : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 13,
              color: selectedArchive != null ? selectedArchive!.color : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              selectedArchive != null ? 'Archive: ${selectedArchive!.badge}' : 'Archive Dropdown',
              style: GoogleFonts.lexend(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selectedArchive != null
                    ? selectedArchive!.color
                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: selectedArchive != null ? selectedArchive!.color : textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isDark) {
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Huli-Kamote System Wiki',
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2234) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                selectedArchive != null ? 'Archived View' : 'Ready for Restructure',
                style: GoogleFonts.lexend(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          selectedArchive != null
              ? 'Viewing archived resource: ${selectedArchive!.title}. You can switch anytime using the Archive Dropdown.'
              : 'Clean wiki workspace ready for step-by-step structuring under your instruction.',
          style: GoogleFonts.lexend(
            fontSize: 12,
            color: textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context, bool isDark, {required double width}) {
    final theme = Theme.of(context);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return SizedBox(
      width: width,
      height: 34,
      child: TextField(
        controller: TextEditingController(text: searchQuery)
          ..selection = TextSelection.collapsed(offset: searchQuery.length),
        onChanged: onSearchChanged,
        style: GoogleFonts.lexend(fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Search wiki & archive...',
          hintStyle: GoogleFonts.lexend(
            fontSize: 11.5,
            color: textMuted,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 15,
            color: textMuted,
          ),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  onPressed: onClearSearch,
                  padding: EdgeInsets.zero,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          filled: true,
          fillColor: isDark ? const Color(0xFF151C2A) : const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withOpacity(0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
