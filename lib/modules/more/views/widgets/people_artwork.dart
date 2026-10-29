import 'package:flutter/material.dart';

const friendsArtworkAsset = 'assets/images/more_friends.png';

class PeopleEntryArtwork extends StatelessWidget {
  const PeopleEntryArtwork({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
    friendsArtworkAsset,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}
