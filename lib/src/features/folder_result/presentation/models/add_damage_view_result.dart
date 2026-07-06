import 'damage_annotation_draft.dart';

sealed class AddDamageViewResult {
  const AddDamageViewResult();
}

final class AddDamageViewSaved extends AddDamageViewResult {
  const AddDamageViewSaved(this.draft);

  final DamageAnnotationDraft draft;
}

final class AddDamageViewDeleted extends AddDamageViewResult {
  const AddDamageViewDeleted(this.localId);

  final String localId;
}
