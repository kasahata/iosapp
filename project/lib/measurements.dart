import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'globals.dart';

class MeasurementData {
  //計測場所詳細,計測場所,コード名,ページURL（開発）,ページURL（本番）
  late String placeDetail, place, codeName, devURL, prodURL;

  MeasurementData(
      this.placeDetail, this.place, this.codeName, this.devURL, this.prodURL);
}

//CSVデータの読み込み
Future<Map<String, MeasurementData>> importCSV() async {
  const String importPath = 'datas/appEventList.csv';
  Map<String, MeasurementData> impotrMap = {};
  String csv = await rootBundle.loadString(importPath);

  int i = 0;
  for (String line in csv.split("\n")) {
    final lineSplit = line.split(',');
    if (lineSplit.length < 5) {
      continue;
    }
    // 1行目はヘッダーなのでスキップ
    if (i == 0) {
      i++;
      continue;
    }

    String url = debug ? lineSplit[3] : lineSplit[4]; //開発用URL、本番では4

    impotrMap[url] = MeasurementData(
        lineSplit[0], lineSplit[1], lineSplit[2], lineSplit[4], lineSplit[4]);
  }
  return Future<Map<String, MeasurementData>>.value(impotrMap);
}

class AppsFlyerManager extends ChangeNotifier {
  late AppsflyerSdk _appsflyerSdk;
  //Map _deepLinkData = {};
  //Map _gcd = {};
  Map<String, MeasurementData> _eventMap = {};

  // called by main.dart > initState()
  void afStart() async {
    logger.t('AppsFlyerManager()');

    _eventMap = await importCSV();

    //iOSかAndroidかで初期化処理を分ける
    if (Platform.isIOS) {
      final appsFlyerOptions = AppsFlyerOptions(
        afDevKey: "8dTkZaHxT87sFdF4HdaJUh",
        appId: "1280323739",
        showDebug: true,
        timeToWaitForATTUserAuthorization: 50, // for iOS 14.5
        manualStart: true,
      ); // Optional field

      _appsflyerSdk = AppsflyerSdk(appsFlyerOptions);
    } else if (Platform.isAndroid) {
      final AppsFlyerOptions appsFlyerOptions = AppsFlyerOptions(
        afDevKey: "8dTkZaHxT87sFdF4HdaJUh",
        showDebug: true,
        manualStart: true,
      ); // Optional field

      _appsflyerSdk = AppsflyerSdk(appsFlyerOptions);
    }

    // Initialization of the AppsFlyer SDK
    await _appsflyerSdk.initSdk(
        registerConversionDataCallback: false,
        registerOnAppOpenAttributionCallback: false,
        registerOnDeepLinkingCallback: false);

    /* コールバック不要
    // Conversion data callback
    _appsflyerSdk.onInstallConversionData((res) {
      logger.t("onInstallConversionData res: $res");
      _gcd = res;
    });

    // App open attribution callback
    _appsflyerSdk.onAppOpenAttribution((res) {
      logger.t("onAppOpenAttribution res: $res");
      _deepLinkData = res;
    });

    // Deep linking callback
    _appsflyerSdk.onDeepLinking((DeepLinkResult dp) {
      switch (dp.status) {
        case Status.FOUND:
          logger.t(dp.deepLink?.toString());
          logger.t("deep link value: ${dp.deepLink?.deepLinkValue}");
          break;
        case Status.NOT_FOUND:
          logger.t("deep link not found");
          break;
        case Status.ERROR:
          logger.t("deep link error: ${dp.error}");
          break;
        case Status.PARSE_ERROR:
          logger.t("deep link status parsing error");
          break;
      }
      logger.t("onDeepLinking res: $dp");
      _deepLinkData = dp.toJson();
    });
    */

    //_appsflyerSdk.anonymizeUser(true);
    // if (Platform.isAndroid) {
    //   _appsflyerSdk.performOnDeepLinking();
    // }

    // Starting the SDK with optional success and error callbacks
    _appsflyerSdk.startSDK();

    // test send event button
    //buildMeasurementButtons();
  }

  // urlに対応するイベントを送信
  bool logUrlEvent(String url) {
    if (_eventMap.containsKey(url)) {
      MeasurementData data = _eventMap[url]!;
      logEvent(data.codeName, {});
      return true;
    }

    return false;
  }

  // Send Custom Events
  logEvent(String eventName, Map eventValues) {
    _appsflyerSdk.logEvent(eventName, eventValues);
  }

  Widget buildMeasurementButtons() {
    return Column(
      children: _eventMap.values.map((data) {
        return TestMeasurementButton(
          place: data.codeName,
          onPressed: () => {logUrlEvent(data.devURL)},
        );
      }).toList(),
    );
  }
}

class TestMeasurementButton extends StatelessWidget {
  final String place;
  final Function onPressed;

  TestMeasurementButton({required this.place, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => onPressed(),
      child: Text(place),
    );
  }
}
