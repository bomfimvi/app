import 'dart:async';
import 'dart:io';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humhub/util/auth_in_app_browser.dart';
import 'package:humhub/models/channel_message.dart';
import 'package:humhub/models/hum_hub.dart';
import 'package:humhub/models/manifest.dart';
import 'package:humhub/pages/opener/opener.dart';
import 'package:humhub/util/black_list_rules.dart';
import 'package:humhub/util/const.dart';
import 'package:humhub/util/crypt.dart';
import 'package:humhub/util/extensions.dart';
import 'package:humhub/util/file_download_manager.dart';
import 'package:humhub/util/file_upload_manager.dart';
import 'package:humhub/util/init_from_url.dart';
import 'package:humhub/util/intent/intent_state.dart';
import 'package:humhub/util/loading_provider.dart';
import 'package:humhub/util/providers.dart';
import 'package:humhub/util/openers/universal_opener_controller.dart';
import 'package:humhub/util/push/provider.dart';
import 'package:humhub/util/router.dart';
import 'package:humhub/util/web_view_global_controller.dart';
import 'package:loggy/loggy.dart';
import 'package:open_file/open_file.dart';
import 'package:humhub/util/router.dart' as m;
import 'package:url_launcher/url_launcher.dart';
import 'package:humhub/l10n/generated/app_localizations.dart';

import '../components/connectivity_wrapper.dart';
import 'console.dart';

class WebView extends ConsumerStatefulWidget {
  const WebView({super.key});
  static const String path = '/web_view';

  @override
  WebViewAppState createState() => WebViewAppState();
}

class WebViewAppState extends ConsumerState<WebView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late AuthInAppBrowser _authBrowser;
  late Manifest _manifest;
  late URLRequest _initialRequest;
  late PullToRefreshController _pullToRefreshController;
  HeadlessInAppWebView? _headlessWebView;
  bool _isInit = false;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  StreamSubscription<bool>? _keyboardSubscription;
  final KeyboardVisibilityController _keyboardVisibilityController = KeyboardVisibilityController();
  EdgeInsets get noKeyboardBottomPadding => MediaQuery.of(context).padding.copyWith(bottom: 0);
  late EdgeInsets initKeyboardPadding = MediaQuery.of(context).padding;
  bool keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _keyboardSubscription = _keyboardVisibilityController.onChange.listen((bool visible) async {
      keyboardVisible = visible;
      await WebViewGlobalController.setWebViewSafeAreaPadding(safeArea: !keyboardVisible ? initKeyboardPadding : noKeyboardBottomPadding);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      _initialRequest = _initRequest;
      logInfo('Initializing WebView with manifest: ${_manifest.name}');
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: HexColor(_manifest.themeColor),
        ),
        onRefresh: () async {
          if (Platform.isAndroid) {
            WebViewGlobalController.value?.reload();
          } else if (Platform.isIOS) {
            WebViewGlobalController.value
                ?.loadUrl(urlRequest: URLRequest(url: await WebViewGlobalController.value?.getUrl(), headers: ref.read(humHubProvider).customHeaders));
          }
        },
      );
      _authBrowser = AuthInAppBrowser(
        manifest: _manifest,
        concludeAuth: (URLRequest request) {
          _concludeAuth(request);
        },
      );
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ConnectivityState>(
      connectivityStateProvider,
      (previous, current) {
        if (previous != null && !previous.hasInternet && current.hasInternet) {
          WebViewGlobalController.value?.reload();
        }
      },
    );

    // --- CONFIGURAÇÃO BLINDADA (GPS + UserAgent + JS) ---
    final InAppWebViewSettings mySettings = InAppWebViewSettings(
      useShouldOverrideUrlLoading: true,
      useOnLoadResource: true,
      useOnDownloadStart: true,
      
      // Essenciais para o LastMile
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      
      // Habilita o GPS Explicitamente
      geolocationEnabled: true, 
      
      safeBrowsingEnabled: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowFileAccessFromFileURLs: true,
      allowUniversalAccessFromFileURLs: true,
      mediaPlaybackRequiresUserGesture: false,
      
      cacheEnabled: false, 
      clearCache: true,
      supportZoom: false,

      // Disfarce de Chrome
      userAgent: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36",
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: HexColor(_manifest.themeColor),
      body: SafeArea(
        bottom: false,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) => exitApp(context, ref),
          child: FileUploadManagerWidget(
            child: InAppWebView(
              initialUrlRequest: _initialRequest,
              
              // APLICANDO AS CONFIGURAÇÕES
              initialSettings: mySettings, 
              
              pullToRefreshController: _pullToRefreshController,
              shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
              onWebViewCreated: _onWebViewCreated,
              shouldInterceptFetchRequest: _shouldInterceptFetchRequest,
              onCreateWindow: _onCreateWindow,
              onLoadStop: _onLoadStop,
              onLoadStart: _onLoadStart,
              onProgressChanged: _onProgressChanged,
              onReceivedError: _onReceivedError,
              onDownloadStartRequest: _onDownloadStartRequest,
              onLongPressHitTestResult: WebViewGlobalController.onLongPressHitTestResult,
              
              // --- CORREÇÃO DE GPS E PERMISSÕES ---
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
              },

              // --- CORREÇÃO DE CERTIFICADO SSL ---
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
              },
              
              onReceivedHttpError: (controller, request, errorResponse) {
                logError(errorResponse);
              },
            ),
          ),
        ),
      ),
    );
  }

  URLRequest get _initRequest {
    final args = ModalRoute.of(context)!.settings.arguments;
    String? url;
    if (args is Manifest) {
      _manifest = args;
    }
    if (args is UniversalOpenerController) {
      UniversalOpenerController controller = args;
      ref.read(humHubProvider).setInstance(controller.humhub);
      _manifest = controller.humhub.manifest!;
      url = controller.url;
    }
    if (args == null) {
      _manifest = m.AppRouter.initParams;
    }
    if (args is ManifestWithRemoteMsg) {
      ManifestWithRemoteMsg manifestPush = args;
      _manifest = manifestPush.manifest;
      url = manifestPush.remoteMessage.data['url'];
    }
    String? payloadFromPush = InitFromUrl.usePayload();
    if (payloadFromPush != null) url = payloadFromPush;
    return URLRequest(url: WebUri(url ?? _manifest.startUrl), headers: ref.read(humHubProvider).customHeaders);
  }

  Future<NavigationActionPolicy?> _shouldOverrideUrlLoading(InAppWebViewController controller, NavigationAction action) async {
    WebViewGlobalController.ajaxSetHeaders(headers: ref.read(humHubProvider).customHeaders);
    WebViewGlobalController.listenToImageOpen();
    WebViewGlobalController.appendViewportFitCover();
    await WebViewGlobalController.setWebViewSafeAreaPadding(safeArea: !keyboardVisible ? initKeyboardPadding : noKeyboardBottomPadding);

    if (WebViewGlobalController.isCommonURIScheme(webUri: action.request.url!)) {
      return WebViewGlobalController.handleCommonURISchemes(webUri: action.request.url!);
    }

    final url = action.request.url!.rawValue;

    logDebug('Navigation attempt: ${action.request.url}');

    if (BlackListRules.check(url)) {
      return NavigationActionPolicy.CANCEL;
    }
    
    // For SSO
    bool? isDomainTrusted = ref.read(humHubProvider).remoteConfig?.isTrustedDomain(action.request.url!.uriValue) ?? false;
    if ((!url.startsWith(_manifest.baseUrl) && action.isForMainFrame) && !isDomainTrusted) {
      // PERMITIR LASTMILE
      if (url.contains("lastmile") || url.contains("drivetriunfante")) {
         return NavigationActionPolicy.ALLOW;
      }

      logInfo('SSO detected, launching AuthInAppBrowser for $url');
      _authBrowser.launchUrl(action.request);
      return NavigationActionPolicy.CANCEL;
    }
    // For all other external links
    if (!url.startsWith(_manifest.baseUrl) && !action.isForMainFrame && action.navigationType == NavigationType.LINK_ACTIVATED) {
      // PERMITIR LASTMILE
      if (url.contains("lastmile") || url.contains("drivetriunfante")) {
         return NavigationActionPolicy.ALLOW;
      }
      
      await launchUrl(action.request.url!.uriValue, mode: LaunchMode.externalApplication);
      return NavigationActionPolicy.CANCEL;
    }
    
    if (Platform.isAndroid || action.navigationType == NavigationType.LINK_ACTIVATED || action.navigationType == NavigationType.FORM_SUBMITTED) {
      Map<String, String> mergedMap = {...?_initialRequest.headers, ...?action.request.headers};
      URLRequest newRequest = action.request.copyWith(headers: mergedMap);
      controller.loadUrl(urlRequest: newRequest);
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  _onWebViewCreated(InAppWebViewController controller) async {
    LoadingProvider.of(ref).showLoading();
    _headlessWebView = HeadlessInAppWebView();
    _headlessWebView!.run();
    await controller.addWebMessageListener(
      WebMessageListener(
        jsObjectName: "flutterChannel",
        onPostMessage: (inMessage, sourceOrigin, isMainFrame, replyProxy) async {
          logInfo(inMessage);
          ChannelMessage message = ChannelMessage.fromJson(inMessage!.data);
          await _handleJSMessage(message, _headlessWebView!);
          logDebug('flutterChannel triggered: ${message.type}');
        },
      ),
    );
    WebViewGlobalController.setValue(controller);
  }

  Future<FetchRequest?> _shouldInterceptFetchRequest(InAppWebViewController controller, FetchRequest request) async {
    request.headers?.addAll(_initialRequest.headers!);
    return request;
  }

  Future<bool?> _onCreateWindow(InAppWebViewController controller, CreateWindowAction createWindowAction) async {
    WebUri? urlToOpen = createWindowAction.request.url;

    if (urlToOpen == null) return Future.value(false);
    if (WebViewGlobalController.openCreateWindowInWebView(
      url: urlToOpen.rawValue,
      manifest: ref.read(humHubProvider).manifest!,
    )) {
      controller.loadUrl(urlRequest: createWindowAction.request);
      return Future.value(false);
    }

    if (await canLaunchUrl(urlToOpen)) {
      await launchUrl(urlToOpen, mode: LaunchMode.externalApplication);
    } else {
      logError('Could not launch $urlToOpen');
    }

    return Future.value(true);
  }

  _onLoadStop(InAppWebViewController controller, Uri? url) async {
    if (url!.path.contains('/user/auth/login')) WebViewGlobalController.setLoginForm();
    WebViewGlobalController.ajaxSetHeaders(headers: ref.read(humHubProvider).customHeaders);
    WebViewGlobalController.listenToImageOpen();
    WebViewGlobalController.appendViewportFitCover();
    await WebViewGlobalController.setWebViewSafeAreaPadding(safeArea: !keyboardVisible ? initKeyboardPadding : noKeyboardBottomPadding);

    LoadingProvider.of(ref).dismissAll();
  }

  void _onLoadStart(InAppWebViewController controller, Uri? url) async {
    WebViewGlobalController.ajaxSetHeaders(headers: ref.read(humHubProvider).customHeaders);
    WebViewGlobalController.listenToImageOpen();
    WebViewGlobalController.appendViewportFitCover();
    await WebViewGlobalController.setWebViewSafeAreaPadding(safeArea: !keyboardVisible ? initKeyboardPadding : noKeyboardBottomPadding);
  }

  _onProgressChanged(InAppWebViewController controller, int progress) {
    if (progress == 100) {
      _pullToRefreshController.endRefreshing();
      LoadingProvider.of(ref).dismissAll();
    }
  }

  void _onReceivedError(InAppWebViewController controller, WebResourceRequest request, WebResourceError error) {
    logWarning('WebView Error: ${error.description}');
    if ([WebResourceErrorType.NOT_CONNECTED_TO_INTERNET, WebResourceErrorType.TIMEOUT].contains(error.type)) {
      LoadingProvider.of(ref).dismissAll();
    }
  }

  _concludeAuth(URLRequest request) {
    _authBrowser.close();
    WebViewGlobalController.value!.loadUrl(urlRequest: request);
  }

  Future<void> _handleJSMessage(ChannelMessage message, HeadlessInAppWebView headlessWebView) async {
    switch (message.action) {
      case ChannelAction.showOpener:
        ref.read(humHubProvider).setOpenerState(OpenerState.shown);
        Navigator.of(context).pushNamedAndRemoveUntil(OpenerPage.path, (Route<dynamic> route) => false);
        break;
      case ChannelAction.hideOpener:
        ref.read(humHubProvider).setOpenerState(OpenerState.hidden);
        ref.read(humHubProvider).setHash(Crypt.generateRandomString(32));
        break;
      case ChannelAction.registerFcmDevice:
        String? token = ref.read(pushTokenProvider).value ?? await FirebaseMessaging.instance.getTokenSafe();
        if (token != null) {
          WebViewGlobalController.ajaxPost(
            url: message.url!,
            data: '{ token: \'$token\' }',
            headers: ref.read(humHubProvider).customHeaders,
          );
        }
        break;
      case ChannelAction.updateNotificationCount:
        UpdateNotificationCountChannelData data = message.data as UpdateNotificationCountChannelData;
        AppBadgePlus.updateBadge(data.count);
        break;
      case ChannelAction.nativeConsole:
        Navigator.of(context).pushNamed(ConsolePage.routeName);
        break;
      case ChannelAction.unregisterFcmDevice:
        String? token = ref.read(pushTokenProvider).value ?? await FirebaseMessaging.instance.getTokenSafe();
        if (token != null) {
          WebViewGlobalController.ajaxPost(
            url: message.url!,
            data: '{ token: \'$token\' }',
            headers: ref.read(humHubProvider).customHeaders,
          );
        }
        break;
      case ChannelAction.fileUploadSettings:
        FileUploadSettingsChannelData data = message.data as FileUploadSettingsChannelData;
        ref.read(humHubProvider.notifier).setFileUploadSettings(data.settings);
        FileUploadManager(
                webViewController: WebViewGlobalController.value!,
                intentNotifier: ref.read(intentProvider.notifier),
                fileUploadSettings: ref.read(humHubProvider).fileUploadSettings,
                context: context)
            .upload();
        break;
      case ChannelAction.none:
        break;
    }
  }

  Future<bool> exitApp(BuildContext context, WidgetRef ref) async {
    bool canGoBack = await WebViewGlobalController.value!.canGoBack();
    if (canGoBack) {
      WebViewGlobalController.value!.goBack();
      return Future.value(false);
    } else {
      bool? exitConfirmed;
      if (context.mounted) {
        exitConfirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10.0))),
            title: Text(AppLocalizations.of(context)!.web_view_exit_popup_title),
            content: Text(AppLocalizations.of(context)!.web_view_exit_popup_content),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(AppLocalizations.of(context)!.no),
              ),
              TextButton(
                onPressed: () {
                  ref.read(humHubProvider).openerState.isShown
                      ? Navigator.of(context).pushNamedAndRemoveUntil(OpenerPage.path, (Route<dynamic> route) => false)
                      : SystemNavigator.pop();
                },
                child: Text(AppLocalizations.of(context)!.yes),
              ),
            ],
          ),
        );
      }
      return exitConfirmed ?? false;
    }
  }

  void _onDownloadStartRequest(InAppWebViewController controller, DownloadStartRequest downloadStartRequest) async {
    PersistentBottomSheetController? persistentController;
    double downloadProgress = 0;
    Timer? downloadTimer;
    bool isDone = false;

    FileDownloadManager(
      downloadStartRequest: downloadStartRequest,
      controller: controller,
      onSuccess: (File file, String filename) async {
        Navigator.popUntil(context, ModalRoute.withName(WebView.path));
        isDone = true;
        Keys.scaffoldMessengerStateKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.file_download}: $filename'),
            action: SnackBarAction(
              label: AppLocalizations.of(context)!.open,
              onPressed: () {
                OpenFile.open(file.path);
              },
            ),
          ),
        );
      },
      onStart: () async {
        downloadProgress = 0;
        downloadTimer = Timer(const Duration(seconds: 1), () {
          if (!isDone) {
            persistentController = _scaffoldKey.currentState!.showBottomSheet((context) {
              return Container(
                width: MediaQuery.of(context).size.width,
                height: 100,
                color: const Color(0xff313033),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${AppLocalizations.of(context)!.downloading}...",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: downloadProgress / 100,
                            backgroundColor: Colors.grey,
                            color: Colors.green,
                          ),
                          downloadProgress.toStringAsFixed(0) == "100"
                              ? const Icon(Icons.check, color: Colors.green, size: 25)
                              : Text(downloadProgress.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            });
          }
        });
      },
      onProgress: (progress) async {
        downloadProgress = progress;
        if (persistentController != null) {
          persistentController!.setState!(() {});
        }
      },
      onError: (er) {
        downloadTimer?.cancel();
        if (persistentController != null) {
          Navigator.popUntil(context, ModalRoute.withName(WebView.path));
        }
        Keys.scaffoldMessengerStateKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.generic_error),
          ),
        );
      },
    ).download();

    Future.delayed(const Duration(seconds: 1), () {
      if (downloadProgress >= 100) {
        downloadTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    if (_headlessWebView != null) _headlessWebView!.dispose();
    _subscription?.cancel();
    _keyboardSubscription?.cancel();
    super.dispose();
  }
}