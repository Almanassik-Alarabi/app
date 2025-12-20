import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: "camera; microphone",
    iframeAllowFullscreen: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
  );

  static const bool kDebugMode = true; // Set to false in release
  String onesignalPlayerId = "null";
  String savedAgencyId = "null";

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // Get OneSignal ID
    onesignalPlayerId = OneSignal.User.pushSubscription.id ?? "null";
    
    // Get Saved Agency ID
    final prefs = await SharedPreferences.getInstance();
    savedAgencyId = prefs.getString('agency_id') ?? "null";
    
    // Refresh WebView if controller exists to inject new values
    if (webViewController != null) {
      _injectVariables(webViewController!);
    }
    
    // Listen for OneSignal changes
    OneSignal.User.pushSubscription.addObserver((state) {
      if (state.current.id != null) {
        setState(() {
          onesignalPlayerId = state.current.id!;
        });
        if (webViewController != null) {
           webViewController!.evaluateJavascript(source: "window.onesignal_player_id = '$onesignalPlayerId';");
        }
      }
    });
  }

  void _injectVariables(InAppWebViewController controller) {
    controller.evaluateJavascript(source: """
        window.onesignal_player_id = '$onesignalPlayerId';
        window.saved_agency_id = '$savedAgencyId';
    """);
  }

  void _injectPolyfills(InAppWebViewController controller) {
    // Injects the AndroidInterface object to mimic the native Android app
    // We use callHandler for methods we want to handle in Flutter (async)
    // We return local variables for methods that need to be sync
    // window.flutter_inappwebview.callHandler is standard for this plugin
    String js = """
      window.AndroidInterface = {
        postMessage: function(message) {
           window.flutter_inappwebview.callHandler('postMessage', message);
        },
        getExternalId: function() {
           return window.onesignal_player_id || "null";
        },
        getSavedAgencyId: function() {
           return window.saved_agency_id || "null";
        },
        forceReLogin: function(agencyId) {
           window.flutter_inappwebview.callHandler('forceReLogin', agencyId);
        },
        testNotification: function() {
           window.flutter_inappwebview.callHandler('testNotification');
           return "Check Log";
        }
      };

      // ReactNativeWebView polyfill as seen in original app
      window.ReactNativeWebView = {
          postMessage: function(data) {
              window.AndroidInterface.postMessage(data);
          }
      };
    """;
    controller.evaluateJavascript(source: js);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          key: webViewKey,
          initialUrlRequest: URLRequest(
            url: WebUri("https://www.almanassikalarabi.com/agencie/dashboard.html"),
          ),
          initialSettings: settings,
          onWebViewCreated: (controller) {
            webViewController = controller;
            
            // Register Handlers
            controller.addJavaScriptHandler(handlerName: 'postMessage', callback: (args) {
              _handlePostMessage(args[0]);
            });
            
            controller.addJavaScriptHandler(handlerName: 'forceReLogin', callback: (args) {
               _handleForceReLogin(args[0]);
            });
            
            controller.addJavaScriptHandler(handlerName: 'testNotification', callback: (args) {
               _handleTestNotification();
            });
          },
          onLoadStart: (controller, url) {
            _injectVariables(controller);
            _injectPolyfills(controller);
          },
          onLoadStop: (controller, url) {
            _injectVariables(controller);
            _injectPolyfills(controller);
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
             return NavigationActionPolicy.ALLOW;
          },
          onConsoleMessage: (controller, consoleMessage) {
            if (kDebugMode) {
              print("WebView Console: \${consoleMessage.message}");
            }
          },
        ),
      ),
    );
  }

  Future<void> _handlePostMessage(dynamic message) async {
    try {
      print("Received message: $message");
      Map<String, dynamic> json;
      if (message is String) {
        json = jsonDecode(message);
      } else {
        json = Map<String, dynamic>.from(message);
      }

      String? type = json['type'];
      
      if (type == "LOGIN_SUCCESS") {
        var payload = json['payload'];
        String? agencyId = payload['agencyId'];
        if (agencyId == null || agencyId.isEmpty) {
           var agency = payload['agency'];
           if (agency != null) {
             agencyId = agency['id'];
           }
        }
        
        String? onesignalId = payload['onesignalPlayerId'];
        
        if (agencyId != null && agencyId.isNotEmpty) {
          // Login OneSignal
          OneSignal.login(agencyId);
          print("OneSignal Login called for: $agencyId");
          
          // Save to Prefs
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('agency_id', agencyId);
          if (onesignalId != null) await prefs.setString('onesignal_player_id', onesignalId);
          
          // Update local var for JS
          savedAgencyId = agencyId;
          if (webViewController != null) {
            webViewController!.evaluateJavascript(source: "window.saved_agency_id = '$agencyId';");
          }
        }
      }
    } catch (e) {
      print("Error parsing message: $e");
    }
  }

  void _handleForceReLogin(dynamic agencyId) {
    if (agencyId is String) {
      print("Force Re-Login for: $agencyId");
      OneSignal.logout();
      
      Future.delayed(const Duration(seconds: 1), () async {
        OneSignal.login(agencyId);
        print("Re-login successful");
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('agency_id', agencyId);
        savedAgencyId = agencyId;
        if (webViewController != null) {
            webViewController!.evaluateJavascript(source: "window.saved_agency_id = '$agencyId';");
        }
      });
    }
  }

  void _handleTestNotification() {
    var id = OneSignal.User.pushSubscription.id;
    var optedIn = OneSignal.User.pushSubscription.optedIn;
    print("Test Notification Status: ID=$id, Subscribed=$optedIn");
  }
}
