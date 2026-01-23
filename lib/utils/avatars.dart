import 'package:flutter/material.dart';
import '../services/translation_service.dart';

class Avatar {
  final String id;
  final String assetPath;
  final String label;
  final Color themeColor;
  final String profileType; // 'librarian', 'individual', or 'kid'

  const Avatar({
    required this.id,
    required this.assetPath,
    required this.label,
    required this.themeColor,
    required this.profileType,
  });
}

// Legacy avatar images have been removed - using customizable avatar system instead
const List<Avatar> availableAvatars = [];

// Get avatars filtered by profile type
List<Avatar> getAvatarsByProfileType(BuildContext context, String profileType) {
  return availableAvatars
      .where((a) => a.profileType == profileType)
      .map(
        (a) => Avatar(
          id: a.id,
          assetPath: a.assetPath,
          label: TranslationService.translate(context, a.label),
          themeColor: a.themeColor,
          profileType: a.profileType,
        ),
      )
      .toList();
}
