import 'package:flutter_test/flutter_test.dart';
import 'package:roulette/nickname/nickname_master.dart';

void main() {
  group('parseNicknames', () {
    test('前後の空白を除き、空行を読み飛ばす', () {
      expect(parseNicknames('  あ \n\nい\r\n  \nう'), ['あ', 'い', 'う']);
    });

    test('0件なら FormatException', () {
      expect(() => parseNicknames('\n \n'), throwsFormatException);
    });

    test('上限ちょうどは読み込める', () {
      final source = List.generate(maxNicknameCount, (i) => 'n$i').join('\n');
      expect(parseNicknames(source), hasLength(maxNicknameCount));
    });

    test('上限を超えると FormatException', () {
      final source = List.generate(
        maxNicknameCount + 1,
        (i) => 'n$i',
      ).join('\n');
      expect(() => parseNicknames(source), throwsFormatException);
    });
  });

  test('同梱のマスタが読み込める', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final names = await loadNicknames();
    expect(names.length, inInclusiveRange(1, maxNicknameCount));
  });
}
