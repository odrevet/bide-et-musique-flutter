import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:bide_et_musique/nowPlaying.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'player.dart';

class InheritedPlaybackState extends InheritedWidget {
  const InheritedPlaybackState(
      {Key key, @required this.playbackState, @required Widget child})
      : super(key: key, child: child);

  final PlaybackState playbackState;

  static PlaybackState of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedPlaybackState>()
        .playbackState;
  }

  @override
  bool updateShouldNotify(InheritedPlaybackState old) =>
      playbackState != old.playbackState;
}

class SongPositionSlider extends StatefulWidget {
  final double _duration;

  SongPositionSlider(this._duration);

  @override
  _SongPositionSliderState createState() => _SongPositionSliderState();
}

class _SongPositionSliderState extends State<SongPositionSlider> {
  final BehaviorSubject<double> _dragPositionSubject =
  BehaviorSubject.seeded(null);

  String _formatSongDuration(int ms) {
    Duration duration = Duration(milliseconds: ms);
    String twoDigits(int n) {
      if (n >= 10) return "$n";
      return "0$n";
    }

    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: Rx.combineLatest2<double, double, double>(
            _dragPositionSubject.stream,
            Stream.periodic(Duration(milliseconds: 200)),
                (dragPosition, _) => dragPosition),
        builder: (context, snapshot) {
          final playerState = InheritedPlaybackState.of(context);
          double seekPos;
          double position =
              snapshot.data ?? playerState.currentPosition.toDouble();

          Widget text =
          Text(_formatSongDuration(playerState.currentPosition));

          Widget slider = Slider(
              inactiveColor: Colors.grey,
              activeColor: Colors.red,
              min: 0.0,
              max: widget._duration,
              value: seekPos ?? max(0.0, min(position, widget._duration)),
              onChanged: (value) {
                _dragPositionSubject.add(value);
              },
              onChangeEnd: (value) {
                AudioService.seekTo(value.toInt());
                seekPos = value;
                _dragPositionSubject.add(null);
              });
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[text, slider],
          );
        });
  }
}

class PlayerWidget extends StatefulWidget {
  final Orientation orientation;
  final Future<SongNowPlaying> _songNowPlaying;

  PlayerWidget(this.orientation, this._songNowPlaying);

  @override
  _PlayerWidgetState createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget>
    with WidgetsBindingObserver {
  @override
  Widget build(BuildContext context) {
    final basicState = InheritedPlaybackState.of(context)?.basicState;

    if (basicState == null || basicState == BasicPlaybackState.none)
      return RadioStreamButton(widget._songNowPlaying);

    if (basicState == BasicPlaybackState.buffering ||
        basicState == BasicPlaybackState.connecting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
          stopButton()
        ],
      );
    }

    List<Widget> controls = <Widget>[
      Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              PlayerState.playerMode == PlayerMode.song
                  ? Icons.music_note
                  : Icons.radio,
              size: 18.0,
            ),
            basicState == BasicPlaybackState.paused
                ? playButton()
                : pauseButton(),
            stopButton()
          ]),
      if (PlayerState.playerMode == PlayerMode.song)
        Container(
          height: 20,
          child: SongPositionSlider(
              AudioService.currentMediaItem?.duration?.toDouble()),
        )
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        widget.orientation == Orientation.portrait
            ? Row(
          children: controls,
        )
            : Column(
          children: controls,
        )
      ],
    );
  }
}

class RadioStreamButton extends StatefulWidget {
  final Future<SongNowPlaying> _songNowPlaying;

  RadioStreamButton(this._songNowPlaying);

  @override
  _RadioStreamButtonState createState() => _RadioStreamButtonState();
}

class _RadioStreamButtonState extends State<RadioStreamButton> {
  Widget build(BuildContext context) {
    Widget label = Text("Écouter la radio",
        style: TextStyle(
          fontSize: 20.0,
        ));

    return FutureBuilder<SongNowPlaying>(
      future: widget._songNowPlaying,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          label = RichText(
            text: TextSpan(
              text: 'Écouter la radio ',
              style: DefaultTextStyle
                  .of(context)
                  .style,
              children: <TextSpan>[
                TextSpan(
                    text: '\n${snapshot.data.nbListeners} auditeurs',
                    style:
                    TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
              ],
            ),
          );
        }
        return RaisedButton.icon(
          icon: Icon(Icons.radio, size: 40),
          label: label,
          onPressed: () async {
            bool success = await AudioService.start(
              backgroundTaskEntrypoint: audioPlayerTaskEntrypoint,
              resumeOnClick: true,
              androidNotificationChannelName: 'Bide&Musique',
              notificationColor: 0xFFFFFFFF,
              androidNotificationIcon: 'mipmap/ic_launcher',
            );
            if (success) {
              SongAiringNotifier().songNowPlaying.then((song) async {
                PlayerState.playerMode = PlayerMode.radio;
                await AudioService.customAction('mode', 'radio');
                await AudioService.customAction('song', song.toJson());
                await AudioService.play();
              });
            }
          },
        );
      },
    );
  }
}

IconButton playButton([double iconSize = 40]) =>
    IconButton(
      icon: Icon(Icons.play_arrow),
      iconSize: iconSize,
      onPressed: AudioService.play,
    );

IconButton pauseButton([double iconSize = 40]) =>
    IconButton(
      icon: Icon(Icons.pause),
      iconSize: iconSize,
      onPressed: AudioService.pause,
    );

IconButton stopButton([double iconSize = 40]) =>
    IconButton(
      icon: Icon(Icons.stop),
      iconSize: iconSize,
      onPressed: AudioService.stop,
    );
