import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'package:kakao_flutter_sdk_common/src/web/login.dart';
import 'package:kakao_flutter_sdk_common/src/web/navi.dart';
import 'package:kakao_flutter_sdk_common/src/web/ua_parser.dart';
import 'package:kakao_flutter_sdk_common/src/web/utility.dart';

class KakaoFlutterSdkPlugin {
  final _uaParser = UaParser();

  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
        "kakao_flutter_sdk", const StandardMethodCodec(), registrar);

    final KakaoFlutterSdkPlugin instance = KakaoFlutterSdkPlugin();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    String userAgent = html.window.navigator.userAgent;
    Browser currentBrowser = _uaParser.detectBrowser(userAgent);

    switch (call.method) {
      case "appVer":
        return await Utility.getAppVersion();
      case "packageName":
        return await Utility.getPackageName();
      case "launchBrowserTab":
        Map<dynamic, dynamic> args = call.arguments;
        String uri = args["url"];
        bool popupLogin = args[CommonConstants.isPopup];
        final fullUri = Uri.parse(uri);
        Map<String, dynamic> queryParameters =
            Map.from(fullUri.queryParameters);

        if (popupLogin) {
          queryParameters[CommonConstants.redirectUri] =
              html.window.location.origin;
          final finalUri = fullUri.replace(queryParameters: queryParameters);
          html.window.open(finalUri.toString(), "KakaoAccountLogin");
        } else {
          queryParameters[CommonConstants.redirectUri] =
              args[CommonConstants.redirectUri];
          final finalUri = fullUri.replace(queryParameters: queryParameters);
          html.window.location.href = finalUri.toString();
        }
        final completer = Completer();
        html.window.addEventListener("message", (html.Event e) {
          if (e is html.MessageEvent) {
            return completer.complete(e.data);
          } else {
            return completer.completeError(PlatformException(
                code: "NotMessageEvent",
                details: "Received wrong type of event ${e.runtimeType}"));
          }
        });
        return completer.future;
      case "retrieveAuthCode":
        _retrieveAuthCode();
        break;
      case "getOrigin":
        return html.window.location.origin;
      case "getKaHeader":
        return _getKaHeader();
      case 'isKakaoTalkSharingAvailable':
      case 'isKakaoNaviInstalled':
      case "isKakaoTalkInstalled":
        if (_uaParser.isAndroid(userAgent) || _uaParser.isiOS(userAgent)) {
          return true;
        }
        return false;
      case "platformId":
        final origin = html.window.location.origin
            .replaceFirst('https', '')
            .replaceFirst('http', '')
            .split('')
            .map((e) => e.codeUnits[0])
            .toList();
        int end = origin.length >= 10 ? 10 : origin.length;
        return Uint8List.fromList(origin.sublist(0, end));
      case "platformRedirectUri":
        if (_uaParser.isAndroid(userAgent)) {
          return "${CommonConstants.scheme}://${KakaoSdk.hosts.kapi}${CommonConstants.androidWebRedirectUri}";
        } else if (_uaParser.isiOS(userAgent)) {
          return CommonConstants.iosWebRedirectUri;
        }
        // Returns meaningless values unless Android and iOS.
        return html.window.origin;
      case 'redirectForEasyLogin':
        final String redirectUri = call.arguments['redirect_uri'];
        final String code = call.arguments['code'];
        final String state = call.arguments['state'];
        html.window.location.href =
            '$redirectUri?code=${Uri.encodeComponent(code)}&state=${Uri.encodeComponent(state)}';
        return;
      case "authorizeWithTalk":
        if (!_uaParser.isAndroid(userAgent) && !_uaParser.isiOS(userAgent)) {
          throw PlatformException(
              code: 'NotImplemented',
              message:
                  'KakaoTalk easy login is only available on Android or iOS devices.');
        }

        var arguments = call.arguments;
        final kaHeader = await KakaoSdk.kaHeader;

        if (_uaParser.isAndroid(userAgent)) {
          String intent =
              androidLoginIntent(kaHeader, userAgent, Map.castFrom(arguments));

          if (currentBrowser == Browser.kakaotalk ||
              currentBrowser == Browser.daum ||
              currentBrowser == Browser.chrome) {
            html.window.location.href = intent;
          } else {
            html.window.open(intent, '_blank');
          }
        } else if (_uaParser.isiOS(userAgent)) {
          final universalLink =
              iosLoginUniversalLink(kaHeader, Map.castFrom(arguments));

          if (currentBrowser == Browser.safari) {
            html.window.open(universalLink, "_blank");
          } else {
            html.window.location.href = universalLink;
          }
        }
        break;
      case 'launchKakaoTalk':
        String uri = call.arguments['uri'];

        if (_uaParser.isAndroid(userAgent)) {
          final intent = _getAndroidShareIntent(userAgent, uri);
          html.window.location.href = intent;
          return true;
        } else if (_uaParser.isiOS(userAgent)) {
          html.window.location.href = uri;
          return true;
        }
        throw PlatformException(
            code: 'NotImplemented',
            message:
                'KakaoTalk can only be launched on Android or iOS devices.');
      case "navigate":
      case "shareDestination":
        String scheme = 'kakaonavi-sdk://navigate';
        String queries =
            'apiver=1.0&appkey=${KakaoSdk.appKey}&param=${Uri.encodeComponent(call.arguments['navi_params'])}&extras=${Uri.encodeComponent(call.arguments['extras'])}';

        if (_uaParser.isAndroid(userAgent)) {
          html.window.location.href = androidNaviIntent(scheme, queries);
          return true;
        } else if (_uaParser.isiOS(userAgent)) {
          bindPageHideEvent(deferredFallback(
              'https://kakaonavi.kakao.com/launch/index.do?$queries',
              (storeUrl) {
            html.window.top?.location.href = storeUrl;
          }));
          html.window.location.href = '$scheme?$queries';
          return true;
        }
        return false;
      default:
        throw PlatformException(
            code: "NotImplemented",
            details:
                "KakaoFlutterSdk for web doesn't implement the method ${call.method}");
    }
  }

  void _retrieveAuthCode() {
    final uri = Uri.parse(html.window.location.search!);
    final params = uri.queryParameters;
    if (params.containsKey("code") || params.containsKey("error")) {
      html.window.opener?.postMessage(html.window.location.href, "*");
      html.window.close();
    }
  }

  String _getKaHeader() {
    return "os/javascript origin/${html.window.location.origin}";
  }

  String _getAndroidShareIntent(String userAgent, String uri) {
    String intentScheme;
    if (userAgent.contains('FB_IAB') || userAgent.contains('Instagram')) {
      intentScheme =
          'intent://send?${uri.substring('kakaolink://send?'.length, uri.length)}#Intent;scheme=kakaolink';
    } else {
      intentScheme = 'intent:$uri#Intent';
    }

    final intent = [
      intentScheme,
      'launchFlags=0x14008000',
      'package=com.kakao.talk',
      'end;'
    ].join(';');
    return intent;
  }
}
