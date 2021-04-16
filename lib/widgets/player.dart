// @dart=2.9

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:bide_et_musique/utils.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../models/song.dart';
import '../player.dart';
import '../services/song.dart';
import 'song.dart';
import 'song_airing_notifier.dart';
import 'song_position_slider.dart';

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
    return StreamBuilder(
        stream: Rx.combineLatest2<MediaItem, PlaybackState, ScreenState>(
            AudioService.currentMediaItemStream,
            AudioService.playbackStateStream,
            (mediaItem, playbackState) =>
                ScreenState(mediaItem, playbackState)),
        builder: (context, snapshot) {
          final screenState = snapshot.data;
          final mediaItem = screenState?.mediaItem;
          final state = screenState?.playbackState;
          final processingState =
              state?.processingState ?? AudioProcessingState.none;
          final bool playing = state?.playing ?? false;
          final bool radioMode =
              mediaItem != null ? mediaItem.album == radioIcon : null;

          List<Widget> controls;

          if (processingState == AudioProcessingState.none) {
            controls = [RadioStreamButton(widget._songNowPlaying)];
          } else {
            Widget playPauseControl;
            if (playing == null ||
                processingState == AudioProcessingState.buffering ||
                processingState == AudioProcessingState.connecting) {
              playPauseControl = Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                      height: 25.0,
                      width: 25.0,
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.black))));
            } else if (playing == true) {
              playPauseControl = pauseButton();
            } else {
              playPauseControl = playButton();
            }

            controls = <Widget>[
              Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    radioMode == false
                        ? InkWell(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (context) {
                              int id = getIdFromUrl(mediaItem.id);
                              return SongPageWidget(
                                  songLink: SongLink(id: id, name: ''),
                                  song: fetchSong(id));
                            })),
                            child: Icon(
                              Icons.music_note,
                              size: 18.0,
                            ),
                          )
                        : InkWell(
                            onTap: () => _streamInfoDialog(context),
                            child: Icon(
                              Icons.radio,
                              size: 18.0,
                            ),
                          ),
                    playPauseControl,
                    stopButton()
                  ]),
              if (radioMode != null && radioMode != true)
                Container(
                    height: 20, child: SongPositionSlider(mediaItem, state))
            ];
          }

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
        });
  }

  _streamInfoDialog(BuildContext context) {
    return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0)),
              actions: <Widget>[],
              title: Text('Informations du flux musical'),
              content: StreamBuilder<dynamic>(
                  stream: AudioService.customEventStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data is IcyMetadata) {
                      var icyMetadata = snapshot.data;
                      String info =
                          '''${icyMetadata.headers.name} ${icyMetadata.headers.genre}
${icyMetadata.info.title}
bitrate ${icyMetadata.headers.bitrate}
''';
                      return Text(info);
                    } else if (snapshot.hasError) {
                      return Text("${snapshot.error}");
                    }

                    return Text('Veuillez attendre');
                  }));
        });
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
              style: DefaultTextStyle.of(context).style,
              children: <TextSpan>[
                TextSpan(
                    text: '\n${snapshot.data.nbListeners} auditeurs',
                    style:
                        TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
              ],
            ),
          );
        }
        return ElevatedButton.icon(
          icon: Icon(Icons.radio, size: 40),
          label: label,
          onPressed: () async {
            bool success = false;
            if (!AudioService.running) {
              success = await AudioService.start(
                backgroundTaskEntrypoint: audioPlayerTaskEntrypoint,
                androidNotificationChannelName: 'Bide&Musique',
                androidNotificationIcon: 'mipmap/ic_launcher',
              );
            }
            if (success) {
              SongAiringNotifier().songNowPlaying.then((song) async {
                await AudioService.customAction('set_radio_mode', true);
                await AudioService.customAction('set_song', song.toJson());
                await AudioService.play();
              });
            }
          },
        );
      },
    );
  }
}

IconButton playButton([double iconSize = 40]) => IconButton(
      icon: Icon(Icons.play_arrow),
      iconSize: iconSize,
      onPressed: AudioService.play,
    );

IconButton pauseButton([double iconSize = 40]) => IconButton(
      icon: Icon(Icons.pause),
      iconSize: iconSize,
      onPressed: AudioService.pause,
    );

IconButton stopButton([double iconSize = 40]) => IconButton(
      icon: Icon(Icons.stop),
      iconSize: iconSize,
      onPressed: AudioService.stop,
    );
