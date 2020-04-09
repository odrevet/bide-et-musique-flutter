import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:bide_et_musique/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uni_links/uni_links.dart';

import 'drawer.dart';
import 'identification.dart';
import 'nowPlaying.dart';
import 'player.dart';
import 'playerWidget.dart';
import 'utils.dart' show handleLink, errorDisplay;

enum UniLinksType { string, uri }

void main() => runApp(BideApp());

class BideApp extends StatefulWidget {
  @override
  _BideAppState createState() => _BideAppState();
}

class _BideAppState extends State<BideApp> with WidgetsBindingObserver {
  PlaybackState _playbackState;
  StreamSubscription _playbackStateSubscription;
  Future<SongNowPlaying> _songNowPlaying;
  Exception _e;
  SongAiringNotifier _songAiring;

  void initSongFetch() {
    _songAiring = SongAiringNotifier();
    _songAiring.addListener(() {
      setState(() {
        _songNowPlaying = _songAiring.songNowPlaying;
        if (_songNowPlaying == null)
          _e = _songAiring.e;
        else if (PlayerState.playerMode == PlayerMode.radio)
          _songAiring.songNowPlaying.then((song) async {
            await AudioService.customAction('song', song.toJson());
          });
      });
    });
    _songAiring.periodicFetchSongNowPlaying();
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    connect();
    autoLogin();
    initPlatformState();
    initSongFetch();

    super.initState();
  }

  // DEEP LINKING
  /////////////////////////////////////////////////////////////////////////
  String _deepLink;
  UniLinksType _type = UniLinksType.string;
  StreamSubscription _sub;

  Future<Null> initUniLinks() async {
    // Attach a listener to the stream
    _sub = getLinksStream().listen((String link) {
      // Parse the link and warn the user, if it is not correct
    }, onError: (err) {
      // Handle exception by warning the user their action did not succeed
    });
  }

  initPlatformState() async {
    if (_type == UniLinksType.string) {
      await initPlatformStateForStringUniLinks();
    } else {
      await initPlatformStateForUriUniLinks();
    }
  }

  /// An implementation using a [String] link
  initPlatformStateForStringUniLinks() async {
    // Attach a listener to the links stream
    _sub = getLinksStream().listen((String link) {
      if (!mounted) return;
      setState(() {
        _deepLink = link ?? null;
      });
    }, onError: (err) {
      print('Failed to get deep link: $err.');
      if (!mounted) return;
      setState(() {
        _deepLink = null;
      });
    });

    // Attach a second listener to the stream
    getLinksStream().listen((String link) {
      print('got link: $link');
    }, onError: (err) {
      print('got err: $err');
    });

    // Get the latest link
    String initialLink;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      initialLink = await getInitialLink();
      print('initial link: $initialLink');
    } on PlatformException {
      initialLink = 'Failed to get initial link.';
    } on FormatException {
      initialLink = 'Failed to parse the initial link as Uri.';
    }

    if (!mounted) return;

    setState(() {
      _deepLink = initialLink;
    });
  }

  /// An implementation using the [Uri] convenience helpers
  initPlatformStateForUriUniLinks() async {
    // Attach a listener to the Uri links stream
    _sub = getUriLinksStream().listen((Uri uri) {
      if (!mounted) return;
      setState(() {
        _deepLink = uri?.toString() ?? null;
      });
    }, onError: (err) {
      print('Failed to get latest link: $err.');
      if (!mounted) return;
      setState(() {
        _deepLink = null;
      });
    });

    // Attach a second listener to the stream
    getUriLinksStream().listen((Uri uri) {
      print('got uri: ${uri?.path} ${uri?.queryParametersAll}');
    }, onError: (err) {
      print('got err: $err');
    });

    // Get the latest Uri
    Uri initialUri;
    String initialLink;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      initialUri = await getInitialUri();
      print('initial uri: ${initialUri?.path}'
          ' ${initialUri?.queryParametersAll}');
      initialLink = initialUri?.toString();
    } on PlatformException {
      initialUri = null;
      initialLink = 'Failed to get initial uri.';
    } on FormatException {
      initialUri = null;
      initialLink = 'Bad parse the initial link as Uri.';
    }

    if (!mounted) return;

    setState(() {
      _deepLink = initialLink;
    });
  }

  void autoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    bool rememberIdents = prefs.getBool('rememberIdents') ?? false;
    bool autoConnect = prefs.getBool('autoConnect') ?? false;

    if (rememberIdents && autoConnect) {
      var login = prefs.getString('login') ?? '';
      var password = prefs.getString('password') ?? '';

      sendIdentifiers(login, password);
    }
  }

  @override
  void dispose() {
    disconnect();
    WidgetsBinding.instance.removeObserver(this);
    if (_sub != null) _sub.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        connect();
        break;
      case AppLifecycleState.paused:
        disconnect();
        break;
      default:
        break;
    }
  }

  void connect() async {
    await AudioService.connect();
    if (_playbackStateSubscription == null) {
      _playbackStateSubscription = AudioService.playbackStateStream
          .listen((PlaybackState playbackState) {
        setState(() {
          _playbackState = playbackState;
        });
      });
    }
  }

  void disconnect() {
    if (_playbackStateSubscription != null) {
      _playbackStateSubscription.cancel();
      _playbackStateSubscription = null;
    }
    AudioService.disconnect();
  }

  Widget refreshNowPlayingSongButton() {
    return Center(
      child: Column(
        children: <Widget>[
          errorDisplay(_e),
          RaisedButton.icon(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _songAiring.periodicFetchSongNowPlaying();
            },
            label: Text('Ré-essayer maintenant'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    Widget body;
    Widget nowPlayingWidget;

    if(_e != null && _songNowPlaying == null)
      nowPlayingWidget = refreshNowPlayingSongButton();
    else if(_songNowPlaying == null)
      nowPlayingWidget = Center(child: CircularProgressIndicator());
    else
      nowPlayingWidget = NowPlayingCard(_songNowPlaying);


    //if the app is launched from deep linking, try to fetch the widget that
    //match the url
    if (_deepLink != null) {
      body = handleLink(_deepLink, context);
    }

    //no url match from deep link or not launched from deep link
    if (body == null)
      home = OrientationBuilder(builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return Scaffold(
              appBar: SongNowPlayingAppBar(orientation, _songNowPlaying),
              bottomNavigationBar: SizedBox(
                  height: 60,
                  child: BottomAppBar(
                      child: PlayerWidget(orientation, _songNowPlaying))),
              drawer: DrawerWidget(),
              body: nowPlayingWidget);
        } else {
          return Scaffold(
              appBar: SongNowPlayingAppBar(orientation, _songNowPlaying),
              drawer: DrawerWidget(),
              body: Row(
                children: <Widget>[
                  Expanded(child: nowPlayingWidget),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      mainAxisSize: MainAxisSize.max,
                      children: <Widget>[
                        SongDetails(_songNowPlaying),
                        PlayerWidget(orientation, _songNowPlaying),
                      ],
                    ),
                  )
                ],
              ));
        }
      });
    else {
      home = Scaffold(
          bottomNavigationBar: SizedBox(
              height: 60,
              child: BottomAppBar(
                  child: PlayerWidget(Orientation.portrait, _songNowPlaying))),
          body: body);
    }

    return InheritedPlaybackState(
        playbackState: _playbackState,
        child: MaterialApp(
            title: 'Bide&Musique',
            theme: ThemeData(
              primarySwatch: Colors.orange,
              buttonColor: Colors.orangeAccent,
              secondaryHeaderColor: Colors.deepOrange,
              bottomAppBarColor: Colors.orange,
              canvasColor: Color.fromARGB(0xE5, 0xF5, 0xEE, 0xE5),
              dialogBackgroundColor: Color.fromARGB(0xE5, 0xF5, 0xEE, 0xE5),
            ),
            home: home));
  }
}
