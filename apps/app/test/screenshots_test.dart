import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/screenshots.dart';

void main() {
  test('reads the app from a Samsung file name', () {
    expect(appFromName('Screenshot_20261022_101530_Instagram.jpg'), 'Instagram');
    expect(appFromName('Screenshot_20261022_101530_Samsung_Internet.jpg'), 'Samsung Internet');
    expect(appFromName('Screenshot_20261022-101530.png'), isNull);
  });

  test('drops status-bar lines and app buttons', () {
    expect(extractInfo('10:15\n87%\nLike\n@chef.raj\nBest paneer tikka recipe\nReply\n1.2K'),
        '@chef.raj\nBest paneer tikka recipe');
  });

  test('a reel with a handle, a caption and hashtags looks useful', () {
    final j = judge(
      '10:15\n@travel.india\nTop 5 cafes in Goa you must visit this winter, save this for later '
      '#goa #cafes\nOriginal audio\nLike\nShare',
      app: 'Instagram',
    );
    expect(j.verdict, Verdict.keep);
    expect(j.info, contains('Top 5 cafes in Goa'));
  });

  test('a home screen with no text looks like junk', () {
    expect(judge('10:15\n87%', app: 'One UI Home').verdict, Verdict.junk);
  });

  test('a one-time code is junk', () {
    expect(judge('Your OTP is 482913. Do not share it with anyone.', app: 'Messages').verdict, Verdict.junk);
  });
}
