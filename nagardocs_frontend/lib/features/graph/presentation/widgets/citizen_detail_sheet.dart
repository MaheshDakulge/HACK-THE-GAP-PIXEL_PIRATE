// lib/features/graph/presentation/widgets/citizen_detail_sheet.dart
// Bottom sheet showing a citizen's digitized documents
// Appears when user taps a node on the graph

import 'package:flutter/material.dart';
import '../../domain/graph_models.dart';

class CitizenDetailSheet extends StatelessWidget {
  final CitizenNode citizen;
  final VoidCallback onClose;

  const CitizenDetailSheet({
    super.key,
    required this.citizen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _avatarBg(citizen),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    citizen.initials,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _avatarText(citizen),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              citizen.fullName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (citizen.isFlagged) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCEBEB),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: 14, color: Color(0xFFE24B4A)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Flagged',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFA32D2D),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${citizen.docCount} records'
                        '${citizen.dob != null ? ' • DOB: ${citizen.dob}' : ''}'
                        '${citizen.uidNumber != null ? ' • UID: ${citizen.uidNumber}' : ''}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 24, color: Colors.grey),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Document cards
          if (citizen.docs.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_rounded, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'No digitized documents',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: citizen.docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _DocumentCard(doc: citizen.docs[index]),
              ),
            ),
        ],
      ),
    );
  }

  Color _avatarBg(CitizenNode n) {
    final bgs = [
      const Color(0xFFE6F1FB),
      const Color(0xFFFBEAF0),
      const Color(0xFFE1F5EE),
      const Color(0xFFFAEEDA),
      const Color(0xFFEEEDFE),
    ];
    return bgs[n.fullName.hashCode.abs() % bgs.length];
  }

  Color _avatarText(CitizenNode n) {
    final txs = [
      const Color(0xFF0C447C),
      const Color(0xFF72243E),
      const Color(0xFF085041),
      const Color(0xFF633806),
      const Color(0xFF3C3489),
    ];
    return txs[n.fullName.hashCode.abs() % txs.length];
  }
}

// ── Single document card (full width) ──────────────────────────
class _DocumentCard extends StatelessWidget {
  final CitizenDocument doc;
  const _DocumentCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: doc.isTampered ? const Color(0xFFFEF5F5) : Colors.white,
        border: Border.all(
          color: doc.isTampered
              ? const Color(0xFFF09595)
              : Colors.grey.shade300,
          width: doc.isTampered ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: doc.isTampered ? const Color(0xFFFCEBEB) : const Color(0xFFF5F6FA),
              shape: BoxShape.circle,
            ),
            child: Icon(
              doc.isTampered ? Icons.warning_rounded : Icons.description_rounded,
              color: doc.isTampered ? const Color(0xFFE24B4A) : const Color(0xFF185FA5),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      doc.type,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    _ConfidenceBadge(confidence: doc.confidence),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  doc.value.isEmpty ? doc.filename : doc.value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: doc.isTampered ? const Color(0xFFA32D2D) : const Color(0xFF222222),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final int confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final bool isHigh = confidence >= 85;
    final bool isMed = confidence >= 60 && confidence < 85;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHigh ? const Color(0xFFEAF3DE) : isMed ? const Color(0xFFFAEEDA) : const Color(0xFFFCEBEB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHigh ? Icons.check_circle_rounded : isMed ? Icons.info_rounded : Icons.error_rounded,
            size: 12,
            color: isHigh ? const Color(0xFF27500A) : isMed ? const Color(0xFF633806) : const Color(0xFF791F1F),
          ),
          const SizedBox(width: 4),
          Text(
            '$confidence%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isHigh ? const Color(0xFF27500A) : isMed ? const Color(0xFF633806) : const Color(0xFF791F1F),
            ),
          ),
        ],
      ),
    );
  }
}
