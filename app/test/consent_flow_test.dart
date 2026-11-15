import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/services/consent_flow.dart';

class _Calls {
  final log = <String>[];
}

ConsentGateway _gw(
  _Calls c, {
  bool updateFails = false,
  bool formFails = false,
  bool? can = true,
  bool canThrows = false,
  bool optionsRequired = false,
  bool optionsThrows = false,
}) =>
    ConsentGateway(
      requestInfoUpdate: () async {
        c.log.add('update');
        if (updateFails) throw 'offline';
      },
      showFormIfRequired: () async {
        c.log.add('form');
        if (formFails) throw 'form error';
      },
      canRequestAds: () async {
        c.log.add('can');
        if (canThrows) throw 'boom';
        return can!;
      },
      privacyOptionsRequired: () async {
        c.log.add('options');
        if (optionsThrows) throw 'boom';
        return optionsRequired;
      },
      showPrivacyOptions: () async => c.log.add('showOptions'),
    );

void main() {
  group('decideAdsAllowed', () {
    test('only an explicit "no" blocks ads', () {
      expect(decideAdsAllowed(true), isTrue);
      expect(decideAdsAllowed(false), isFalse);
      expect(decideAdsAllowed(null), isTrue); // check failed: still request
    });
  });

  group('gather', () {
    test('order: update, form, canRequestAds, privacy options', () async {
      final c = _Calls();
      final r = await ConsentFlow(_gw(c)).gather();
      expect(c.log, ['update', 'form', 'can', 'options']);
      expect(r.adsAllowed, isTrue);
      expect(r.infoUpdateFailed, isFalse);
    });

    test('Google says no: ads blocked', () async {
      final r = await ConsentFlow(_gw(_Calls(), can: false)).gather();
      expect(r.adsAllowed, isFalse);
    });

    test('info update fails: form skipped, ads still requested', () async {
      final c = _Calls();
      final r = await ConsentFlow(_gw(c, updateFails: true)).gather();
      expect(c.log, ['update', 'can', 'options']);
      expect(r.infoUpdateFailed, isTrue);
      expect(r.adsAllowed, isTrue);
    });

    test('info update fails and Google already says no: stays blocked',
        () async {
      final r = await ConsentFlow(_gw(_Calls(), updateFails: true, can: false))
          .gather();
      expect(r.adsAllowed, isFalse);
    });

    test('form error does not stop the flow', () async {
      final r = await ConsentFlow(_gw(_Calls(), formFails: true)).gather();
      expect(r.adsAllowed, isTrue);
    });

    test('canRequestAds throws: error reported, ads still requested',
        () async {
      final r = await ConsentFlow(_gw(_Calls(), canThrows: true)).gather();
      expect(r.canRequestAdsError, 'boom');
      expect(r.adsAllowed, isTrue);
    });

    test('privacy options row only when required', () async {
      expect(
          (await ConsentFlow(_gw(_Calls(), optionsRequired: true)).gather())
              .privacyOptionsRequired,
          isTrue);
      expect(
          (await ConsentFlow(_gw(_Calls())).gather()).privacyOptionsRequired,
          isFalse);
    });

    test('privacy status error means no row', () async {
      final r =
          await ConsentFlow(_gw(_Calls(), optionsThrows: true)).gather();
      expect(r.privacyOptionsRequired, isFalse);
    });
  });

  group('showPrivacyOptions', () {
    test('re-checks canRequestAds afterwards', () async {
      final c = _Calls();
      final ok = await ConsentFlow(_gw(c)).showPrivacyOptions();
      expect(c.log, ['showOptions', 'can']);
      expect(ok, isTrue);
    });

    test('user withdrew consent: ads blocked afterwards', () async {
      final ok =
          await ConsentFlow(_gw(_Calls(), can: false)).showPrivacyOptions();
      expect(ok, isFalse);
    });
  });
}
