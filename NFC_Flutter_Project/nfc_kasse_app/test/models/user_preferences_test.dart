import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/models/category_model.dart';
import 'package:nfc_kasse_app/models/user_preferences_model.dart';

CategoryModel _cat(int n) => CategoryModel(id: '$n', name: 'K$n', sortOrder: n);

void main() {
  final serverOrder = [_cat(1), _cat(2), _cat(3), _cat(4)];
  List<String> ids(List<CategoryModel> cats) => cats.map((c) => c.id).toList();

  test('without saved order the server order is kept', () {
    expect(ids(UserPreferences.empty.applyCategoryOrder(serverOrder)), ['1', '2', '3', '4']);
  });

  test('saved order wins, unknown categories are appended, stale ids ignored', () {
    final prefs = UserPreferences.empty.withCategoryOrder(['3', '99', '1']);
    expect(ids(prefs.applyCategoryOrder(serverOrder)), ['3', '1', '2', '4']);
  });

  test('category color override can be set and reset', () {
    final prefs = UserPreferences.empty.withCategoryColor('2', const Color(0xFFA5D6A7));
    expect(prefs.getCategoryColor('2'), const Color(0xFFA5D6A7));
    expect(prefs.withCategoryColor('2', null).getCategoryColor('2'), isNull);
  });
}
