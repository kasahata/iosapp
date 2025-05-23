import 'dart:developer';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:project/measurements.dart';
import 'package:project/purchases.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:project/globals.dart';

// #docregion platform_imports
// Import for Android features.
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

Future<void> injectJavascript(WebViewController controller) async {
  logger.t('injectJavascript()');
  await controller.runJavaScript('''
    console.log('Inject Javascript');

    function SendId(id)
    {
      flutterChannel.postMessage(id);
    }
    
    const IosButtonNum = 6;
    for(var i = 0; i <= IosButtonNum;i++)
    {
      var num = ( '000' + i ).slice( -3 );
      const id = 'iOS.HorseCrystal.' + num;
      const button = document.getElementById(id);
      console.log('button id: ' + id + ', button: ' + button);
      if (button != null) {
        (function(btn) { 
          btn.onclick = function() { SendId(btn.id); };
        })(button);
      }
    }

    const AndroidButtonNum = 6;
    for(var i = 1; i <= AndroidButtonNum; i++)
    {
      var num = ('000' + i).slice( -3 );
      const id = 'And.HorseCrystal.' + num;
      const button = document.getElementById(id);
      console.log('button id: ' + id + ', button: ' + button);
      if (button != null) {
        (function(btn) { 
          btn.onclick = function() { SendId(btn.id); };
        })(button);
      }
    }
''');
}

void main() => runApp(
  const MaterialApp(
        home: MyApp(),
      ),
    );

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late final WebViewController _controller;
  late final Purchases _purchases = Purchases();
  

  // AppsFlyerManagerのインスタンスを作成し、初期化
  final appsFlyerManager = AppsFlyerManager();
  await appsFlyerManager.afStart(); // 非同期処理を待つ
  final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();
  bool _isProcessing = false;

  // Appsflyer アプリ内イベントを送信する
  void sendAppFlyerEvent(String url) {
    bool logResult;
    try {
      logResult = _appsFlyerManager.logUrlEvent(url);
      if (logResult == true) {
        logger.t("Event logged successfully: $url");
      }
    } catch (e) {
      logger.t("Failed to log event: $e");
    }
  }

  // AppTrackingTransparencyの初期化
  // トラッキング認証が未設定の場合、設定を要求する
  Future<void> _initATT() async {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await Future.delayed(const Duration(milliseconds: 200));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }

  Future<void> _purchase(String id) async {
    logger.t('_purchase($id)');

    if (_purchases.products.isEmpty) {
      logger.t('products is empty');
      final state = _scaffoldKey.currentState;
      if (state != null) {
        state.showSnackBar(
          SnackBar(
            content: Text('button id: $id, products is empty'),
          ),
        );
      }
      return;
    }

    String btnLastThreeDigits = id.substring(id.length - 3);
    int btnIdIdx = int.parse(btnLastThreeDigits);
    Map<int, String> idMap = {
      1: 'jp.pygmyslabo.derbyleague.100',
      2: 'jp.pygmyslabo.derbyleague.500',
      3: 'jp.pygmyslabo.derbyleague.1500',
      4: 'jp.pygmyslabo.derbyleague.3000',
      5: 'jp.pygmyslabo.derbyleague.5000',
      6: 'jp.pygmyslabo.derbyleague.10000',
    };

    String productId = idMap[btnIdIdx]!;
    logger.t('productId: $productId');

    var product =
        _purchases.products.firstWhere((element) => element.id == productId);

    final result = await _purchases.buy(product);
    // resultとidをSnackBarで表示
    final message = 'productId: $productId, result: $result';
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> _restore() async {
    await _purchases.restore();
  }

  @override
  void initState() {
    super.initState();

    // AppTrackingTransparencyの初期化
    // Build後に確認のダイアログが表示されます。
    WidgetsBinding.instance?.addPostFrameCallback((_) => _initATT());

    // アプリ計測の初期化
    _appsFlyerManager.afStart();

    _controller = WebViewController()
      ..loadRequest(Uri.parse('https://derby-league.com/dl_app/Top/'))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            logger.t('progress: $progress');
          },
          onPageStarted: (String url) {
            logger.t('page started: $url');
          },
          onPageFinished: (String url) {
            logger.t('page finished: $url');
            if (url == 'https://derby-league.com/dl_app/Payment/') {
              injectJavascript(_controller);
            }

            sendAppFlyerEvent(url);
          },
          onWebResourceError: (WebResourceError error) {
            logger.e('web resource error: $error');
          },
          onNavigationRequest: (NavigationRequest request) {
            logger.t('navigation request: $request');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'flutterChannel',
        onMessageReceived: (message) async {
          logger.t('message: ${message.message}');
          final id = message.message;
          setState(() {
            _isProcessing = true;
          });

          await _purchase(id);
          setState(() {
            _isProcessing = false;
          });
        },
      );
    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    () async {
      await _restore();
      setState(() {
        _isProcessing = false;
      });
    }();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldKey,
      child: Scaffold(
        // デバッグ用設定ボタン(歯車アイコン)
        // TODO: 本番リリース時には削除してください
        floatingActionButton: debug
            ? FloatingActionButton(
                onPressed: () {
                  showDialog<void>(
                      context: context,
                      builder: (_) {
                        return _appsFlyerManager.buildMeasurementButtons();
                      });
                },
                child: const Icon(Icons.settings),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: _isProcessing
                      ? [
                          // 処理中
                          WebViewWidget(
                            controller: _controller,
                          ),
                          const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ]
                      : [
                          // 通常
                          WebViewWidget(
                            controller: _controller,
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

