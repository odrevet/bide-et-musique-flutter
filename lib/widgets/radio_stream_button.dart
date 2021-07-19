import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../player.dart' show audioHandler;
import '../widgets/song_airing_notifier.dart';

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
                    text: '\n${snapshot.data!.nbListeners} auditeurs',
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
            SongAiringNotifier().songNowPlaying!.then((song) async {
              await audioHandler.customAction('set_radio_mode', <String, dynamic>{'radio_mode': true});
              await audioHandler.customAction('set_song', song.toJson());
              await audioHandler.play();
            });


            /*bool success = false;
            if (!AudioService.running) {
              success = await AudioService.start(
                backgroundTaskEntrypoint: audioPlayerTaskEntrypoint,
                androidNotificationChannelName: 'Bide&Musique',
                androidNotificationIcon: 'mipmap/ic_launcher',
              );
            }
            if (success) {
              SongAiringNotifier().songNowPlaying!.then((song) async {
                //await AudioService.customAction('set_radio_mode', true);
                await AudioService.customAction('set_song', song.toJson());
                await AudioService.play();
              });
            }*/
          },
        );
      },
    );
  }
}