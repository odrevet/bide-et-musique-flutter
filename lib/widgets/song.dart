import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:diacritic/diacritic.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:page_indicator/page_indicator.dart';

import '../models/song.dart';

import '../services/artist.dart';
import '../services/account.dart';
import '../services/song.dart';

import 'account.dart';
import 'artist.dart';
import 'cover_viewer.dart';
import 'search.dart';
import '../session.dart';
import 'song_app_bar.dart';
import '../utils.dart';

String createTag(SongLink songLink) {
  return songLink.index == null
      ? 'cover_${songLink.id}'
      : 'cover_${songLink.id}_${songLink.index}';
}

class CoverThumb extends StatelessWidget {
  final SongLink _songLink;

  CoverThumb(this._songLink);

  @override
  Widget build(BuildContext context) {
    final tag = createTag(_songLink);
    return Hero(
        tag: tag,
        child: CachedNetworkImage(
            imageUrl: _songLink.thumbLink,
            placeholder: (context, url) => Icon(Icons.album, size: 56.0),
            errorWidget: (context, url, error) =>
                Icon(Icons.album, size: 56.0)));
  }
}

class SongCardWidget extends StatelessWidget {
  final SongLink songLink;

  SongCardWidget({Key key, this.songLink}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: GestureDetector(
        onTap: () {
          if (songLink.id != null) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => SongPageWidget(
                        songLink: songLink, song: fetchSong(songLink.id))));
          }
        },
        onLongPress: () {
          Navigator.of(context).push(MaterialPageRoute<Null>(
              builder: (BuildContext context) {
                return CoverViewer(songLink);
              },
              fullscreenDialog: true));
        },
        child: Cover(songLink.coverLink),
      ),
    );
  }
}

class Cover extends StatelessWidget {
  final String _url;

  Cover(this._url);

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      fadeInDuration: Duration(seconds: 0),
      fadeOutDuration: Duration(seconds: 0),
      imageUrl: _url,
      errorWidget: (context, url, error) =>
          Image.asset('assets/vinyl-default.jpg'),
    );
  }
}

class SongPageWidget extends StatefulWidget {
  final SongLink songLink;
  final Future<Song> song;

  SongPageWidget({Key key, this.songLink, this.song}) : super(key: key);

  @override
  _SongPageWidgetState createState() => _SongPageWidgetState(this.song);
}

class _SongPageWidgetState extends State<SongPageWidget> {
  int _currentPage;
  final _commentController = TextEditingController();
  Future<Song> song;

  _SongPageWidgetState(this.song);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Song>(
      future: this.song,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _buildView(context, snapshot.data);
        } else if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text('Ouille ouille ouille !')),
            body: Center(child: ErrorDisplay(snapshot.error)),
          );
        }

        return Center(child: _pageLoading(context, widget.songLink));
      },
    );
  }

  void _openCoverViewerDialog(SongLink songLink, BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return CoverViewer(songLink);
        },
        fullscreenDialog: true));
  }

  Widget _pageLoading(BuildContext context, SongLink songLink) {
    var coverLink = songLink.coverLink;

    var loadingMessage = '';
    if (songLink.name != null && songLink.name.isNotEmpty) {
      loadingMessage += songLink.name;
    } else {
      loadingMessage = 'Chargement';
    }

    Widget body = Stack(children: <Widget>[
      CachedNetworkImage(
        imageUrl: coverLink,
        imageBuilder: (context, imageProvider) => Container(
          decoration: BoxDecoration(
            image: DecorationImage(image: imageProvider, fit: BoxFit.fitWidth),
          ),
        ),
        errorWidget: (context, url, error) =>
            Image.asset('assets/vinyl-default.jpg'),
      ),
      Align(alignment: Alignment.center, child: CircularProgressIndicator())
    ]);

    return Scaffold(appBar: AppBar(title: Text(loadingMessage)), body: body);
  }

  _newMessageDialog(BuildContext context, Song song) {
    _commentController.text = '';

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
          actions: [
            RaisedButton.icon(
              icon: Icon(Icons.send),
              label: Text("Envoyer"),
              onPressed: () async {
                _sendAddComment(song);
                Navigator.of(context).pop();
                setState(() {
                  this.song = fetchSong(song.id);
                });
              },
            )
          ],
          title: Text('Nouveau commentaire'),
          content: TextFormField(
              maxLines: 5,
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Entrez votre commentaire ici',
              )),
        );
      },
    );
  }

  _editMessageDialog(BuildContext context, Song song, Comment comment) {
    _commentController.text = comment.body;
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          actions: [
            RaisedButton.icon(
              icon: Icon(Icons.send),
              label: Text("Envoyer"),
              onPressed: () async {
                _sendEditComment(song, comment);
                setState(() {
                  this.song = fetchSong(song.id);
                });
                Navigator.of(context).pop();
              },
            )
          ],
          title: Text('Edition d\'un commentaire'),
          content: TextFormField(
              maxLines: 5,
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Entrez votre commentaire ici',
              )),
        );
      },
    );
  }

  void _sendEditComment(Song song, Comment comment) async {
    String text = removeDiacritics(_commentController.text);

    if (text.isNotEmpty) {
      await Session.post('$baseUri/edit_comment.html?Comment__=${comment.id}',
          body: {
            'mode': 'Edit',
            'REF': song.link,
            'Comment__': comment.id.toString(),
            'Text': text,
          });
    }
  }

  void _sendAddComment(Song song) async {
    String comment = _commentController.text;
    comment = removeDiacritics(comment);

    final url = song.link;

    if (comment.isNotEmpty) {
      await Session.post(url, body: {
        'T': 'Song',
        'N': song.id.toString(),
        'Mode': 'AddComment',
        'Thread_': '',
        'Text': comment,
        'x': '42',
        'y': '42'
      });
    }
  }

  Widget _buildView(BuildContext context, Song song) {
    final String coverLink = song.coverLink;
    final tag = createTag(widget.songLink);

    var nestedScrollView = NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              backgroundColor: Theme.of(context).canvasColor,
              expandedHeight: 200.0,
              automaticallyImplyLeading: false,
              floating: true,
              flexibleSpace: FlexibleSpaceBar(
                  background: Row(children: [
                Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          flex: 1,
                          child: Card(
                              child: Hero(
                                  tag: tag,
                                  child: InkWell(
                                      onTap: () {
                                        _openCoverViewerDialog(
                                            widget.songLink, context);
                                      },
                                      child: CachedNetworkImage(
                                          imageUrl: coverLink)))),
                        ),
                        Expanded(
                            flex: 1,
                            child: SingleChildScrollView(
                                child: SongInformations(song: song))),
                      ],
                    ))
              ])),
            ),
          ];
        },
        body: Stack(children: [
          CachedNetworkImage(
            imageUrl: song.coverLink,
            imageBuilder: (context, imageProvider) => Container(
                decoration: BoxDecoration(
                    image: DecorationImage(
                        image: imageProvider, fit: BoxFit.cover)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 9.6, sigmaY: 9.6),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200.withOpacity(0.7)),
                  ),
                )),
          ),
          PageIndicatorContainer(
            align: IndicatorAlign.bottom,
            length: 2,
            indicatorSpace: 20.0,
            padding: const EdgeInsets.all(10),
            shape: IndicatorShape.circle(size: 8),
            indicatorColor: Theme.of(context).canvasColor,
            indicatorSelectorColor: Theme.of(context).accentColor,
            child: PageView(
              onPageChanged: (int page) => setState(() {
                _currentPage = page;
              }),
              children: <Widget>[
                SingleChildScrollView(
                    child: Padding(
                  padding: EdgeInsets.only(left: 4.0, top: 2.0),
                  child: Html(
                      data: song.lyrics == ''
                          ? '<center><i>Paroles non renseignées</i></center>'
                          : song.lyrics,
                      defaultTextStyle: TextStyle(fontSize: 18.0),
                      linkStyle: linkStyle,
                      onLinkTap: (url) {
                        onLinkTap(url, context);
                      }),
                )),
                _buildViewComments(context, song),
              ],
            ),
          )
        ]));

    Widget postNewComment = Session.accountLink.id == null || _currentPage != 1
        ? null
        : FloatingActionButton(
            onPressed: () => _newMessageDialog(context, song),
            child: Icon(Icons.add_comment),
          );

    return Scaffold(
      appBar: SongAppBar(widget.song),
      body: nestedScrollView,
      floatingActionButton: postNewComment,
    );
  }

  Widget _buildViewComments(BuildContext context, Song song) {
    List<Comment> comments = song.comments;
    var rows = <Widget>[];
    String loginName = Session.accountLink.name;
    var selfComment = TextStyle(
      color: Colors.red,
    );

    for (Comment comment in comments) {
      rows.add(ListTile(
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => AccountPageWidget(
                        account: fetchAccount(comment.author.id))));
          },
          title: Html(
              data: comment.body,
              linkStyle: linkStyle,
              defaultTextStyle: TextStyle(fontSize: 16.0),
              onLinkTap: (url) {
                onLinkTap(url, context);
              }),
          subtitle: Text('Par ' + comment.author.name + ' ' + comment.time,
              style: comment.author.name == loginName ? selfComment : null),
          trailing: comment.author.name == loginName
              ? IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () async {
                    _editMessageDialog(context, song, comment);
                  },
                )
              : null));
      rows.add(Divider());
    }

    return ListView(children: rows);
  }
}

/// Display given songs in a ListView
class SongListingWidget extends StatefulWidget {
  final List<SongLink> _songLinks;

  SongListingWidget(this._songLinks, {Key key}) : super(key: key);

  @override
  SongListingWidgetState createState() => SongListingWidgetState();
}

class SongListingWidgetState extends State<SongListingWidget> {
  SongListingWidgetState();

  @override
  Widget build(BuildContext context) {
    var rows = <ListTile>[];

    for (SongLink songLink in widget._songLinks) {
      String subtitle = songLink.artist == null ? '' : songLink.artist;

      if (songLink.info != null && songLink.info.isNotEmpty) {
        if (subtitle != '') subtitle += ' • ';
        subtitle += songLink.info;
      }

      rows.add(ListTile(
        leading: GestureDetector(
          child: CoverThumb(songLink),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<Null>(
              builder: (BuildContext context) {
                return CoverViewer(songLink);
              },
              fullscreenDialog: true)),
        ),
        title: Text(
          songLink.name,
        ),
        trailing: songLink.isNew ? Icon(Icons.fiber_new) : null,
        subtitle: Text(subtitle),
        onTap: () => launchSongPage(songLink, context),
        onLongPress: () {
          fetchSong(songLink.id).then((song) {
            showDialog<void>(
              context: context,
              barrierDismissible: true,
              builder: (BuildContext context) {
                return SimpleDialog(
                  contentPadding: EdgeInsets.all(20.0),
                  children: [SongActionMenu(song)],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20.0))),
                );
              },
            );
          });
        },
      ));
    }

    return ListView(children: rows);
  }
}

void launchSongPage(SongLink songLink, BuildContext context) {
  if (songLink.id != null) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => SongPageWidget(
                songLink: songLink, song: fetchSong(songLink.id))));
  }
}

class SongInformations extends StatelessWidget {
  final Song song;
  final bool compact;

  SongInformations({this.song, this.compact = false});

  @override
  Widget build(BuildContext context) {
    var linkStyle = TextStyle(
      fontSize: 16.0,
      color: Colors.red,
      fontWeight: FontWeight.bold,
    );

    var textSpans = <TextSpan>[];

    if (!compact && song.year != 0) {
      textSpans.add(TextSpan(
        text: 'Année\n',
        style: defaultStyle,
      ));

      textSpans.add(TextSpan(
          text: song.year.toString() + '\n\n',
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                    'Recherche de l\'année "${song.year.toString()}"'),
                              ),
                              body: SearchResultsWidget(
                                  song.year.toString(), '7')))),
                }));
    }

    if (!compact && song.artist != null) {
      textSpans.add(TextSpan(
        text: 'Artiste\n',
        style: defaultStyle,
      ));

      textSpans.add(TextSpan(
          text: song.artist + '\n\n',
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ArtistPageWidget(
                              artist: fetchArtist(song.artistId)))),
                }));
    }

    if (song.durationPretty != null) {
      textSpans.add(TextSpan(
        text: 'Durée \n',
        style: defaultStyle,
      ));

      textSpans.add(TextSpan(
        text: song.durationPretty + '\n\n',
        style: defaultStyle,
      ));
    }

    if (song.label != null && song.label != '') {
      textSpans.add(TextSpan(
        text: 'Label\n',
        style: defaultStyle,
      ));

      textSpans.add(TextSpan(
          text: song.label + '\n\n',
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => Scaffold(
                              appBar: AppBar(
                                title:
                                    Text('Recherche du label "${song.label}"'),
                              ),
                              body: SearchResultsWidget(song.label, '5')))),
                }));
    }

    if (song.reference != null && song.reference != '') {
      textSpans.add(TextSpan(
        text: 'Référence\n',
        style: defaultStyle,
      ));

      textSpans.add(TextSpan(
        text: song.reference.toString() + '\n\n',
        style: defaultStyle,
      ));
    }

    return Center(
        child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(style: defaultStyle, children: textSpans)));
  }
}