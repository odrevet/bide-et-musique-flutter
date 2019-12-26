import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'account.dart';
import 'artist.dart';
import 'coverViewer.dart';
import 'search.dart';
import 'session.dart';
import 'songAppBar.dart';
import 'utils.dart';

class SongLink {
  String id;
  String title;
  String artist;
  String program;
  bool isNew;
  int index;

  SongLink(
      {this.id = '',
      this.title = '',
      this.artist = '',
      this.program = '',
      this.isNew = false});
}

class Song {
  String id;
  int year;
  String title;
  String artist;
  String artistId;
  String author;
  Duration duration;
  String durationPretty;
  String label;
  String reference;
  String lyrics;
  List<Comment> comments;
  bool canListen;
  bool canFavourite;
  bool isFavourite;
  bool hasVote;

  Song(
      {this.id,
      this.title,
      this.year,
      this.artist,
      this.artistId,
      this.author,
      this.duration,
      this.durationPretty,
      this.label,
      this.reference,
      this.lyrics});

  factory Song.fromJson(Map<String, dynamic> json) {
    final String lyrics = json['lyrics'];
    return Song(
        id: json['id'].toString(),
        title: stripTags(json['name']),
        year: json['year'],
        artist: stripTags(json['artists']['main']['alias']),
        artistId: json['artists']['main']['id'].toString(),
        author: json['author'],
        duration: Duration(seconds: json['length']['raw']),
        durationPretty: json['length']['pretty'],
        label: stripTags(json['label']),
        reference: stripTags(json['reference']),
        lyrics: lyrics == null
            ? 'Paroles non renseignées pour cette chanson '
            : lyrics);
  }

  String get link {
    return '$baseUri/song/${this.id}.html';
  }
}

class Comment {
  String id;
  AccountLink author;
  String body;
  String time;

  Comment();
}

String extractSongId(str) {
  final idRegex = RegExp(r'/song/(\d+).html');
  var match = idRegex.firstMatch(str);
  if (match != null) {
    return match[1];
  } else {
    return null;
  }
}

String createTag(SongLink songLink) {
  return songLink.index == null
      ? 'cover_${songLink.id}'
      : 'cover_${songLink.id}_${songLink.index}';
}

Hero heroThumbCover(SongLink songLink) {
  final tag = createTag(songLink);
  return Hero(
      tag: tag,
      child: Image(
          image: NetworkImage('$baseUri/images/thumb25/${songLink.id}.jpg')));
}

class SongCardWidget extends StatelessWidget {
  final SongLink songLink;

  SongCardWidget({Key key, this.songLink}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
      child: Container(
        decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            image: DecorationImage(
                image: NetworkImage(
                    '$baseUri/images/pochettes/${songLink.id}.jpg'))),
      ),
    );
  }
}

Future<Song> fetchSong(String songId) async {
  var song;
  final url = '$baseUri/song/$songId';
  final responseJson = await Session.get(url);

  if (responseJson.statusCode == 200) {
    try {
      var decodedJson = utf8.decode(responseJson.bodyBytes);
      song = Song.fromJson(json.decode(decodedJson));
    } catch (e) {
      song = Song(
          id: songId,
          title: '?',
          year: 0,
          artist: '?',
          author: '?',
          duration: null,
          label: '?',
          reference: '?',
          lyrics: e.toString());
    }
  } else {
    throw Exception('Failed to load song with id $songId');
  }

  //If connected, fetch comments and favorite status
  var response = await Session.get(url + '.html');

  if (response.statusCode == 200) {
    var body = response.body;
    dom.Document document = parser.parse(body);
    var comments = <Comment>[];
    var divComments = document.getElementById('comments');
    var divsNormal = divComments.getElementsByClassName('normal');

    for (dom.Element divNormal in divsNormal) {
      var comment = Comment();
      try {
        var tdCommentChildren = divNormal.children;
        //get comment id (remove 'comment' string)
        comment.id = tdCommentChildren[0].attributes['id'].substring(8);
        dom.Element aAccount = tdCommentChildren[1].children[0];
        String accountId = extractAccountId(aAccount.attributes['href']);
        String accountName = aAccount.innerHtml;
        comment.author = AccountLink(id: accountId, name: accountName);
        var commentLines = divNormal.innerHtml.split('<br>');
        commentLines.removeAt(0);
        comment.body = stripTags(commentLines.join().trim());
        comment.time = tdCommentChildren[2].innerHtml;
        comments.add(comment);
      } catch (e) {
        print(e.toString());
      }
    }
    song.comments = comments;

    song.canListen = false;
    song.isFavourite = false;
    song.canFavourite = false;

    var divTitres = document.getElementsByClassName('titreorange');
    for (var divTitre in divTitres) {
      var title = stripTags(divTitre.innerHtml).trim();
      switch (title) {
        case 'Écouter le morceau':
          song.canListen = true;
          break;
        case 'Ce morceau est dans vos favoris':
          song.isFavourite = true;
          song.canFavourite = true;
          break;
        case 'Ajouter à mes favoris':
          song.isFavourite = false;
          song.canFavourite = true;
          break;
      }
    }

    //available only if logged-in
    if (Session.accountLink.id != null) {
      //check vote
      var vote = document.getElementById('vote');
      if (vote == null) {
        song.hasVote = true;
      } else {
        song.hasVote = false;
      }
    } else {
      song.isFavourite = false;
      song.canFavourite = false;
    }
  } else {
    throw Exception('Failed to load song page');
  }
  return song;
}

class SongPageWidget extends StatefulWidget {
  final SongLink songLink;
  final Future<Song> song;

  SongPageWidget({Key key, this.songLink, this.song}) : super(key: key);

  @override
  _SongPageWidgetState createState() => _SongPageWidgetState();
}

class _SongPageWidgetState extends State<SongPageWidget> {
  int _currentPage;
  final _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FutureBuilder<Song>(
        future: widget.song,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _buildView(context, snapshot.data);
          } else if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: Text('Ouille ouille ouille !')),
              body: Center(child: Center(child: errorDisplay(snapshot.error))),
            );
          }

          return _pageLoading(context, widget.songLink);
        },
      ),
    );
  }

  void _openCoverViewerDialog(SongLink songLink, BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return CoverViewer(songLink);
        },
        fullscreenDialog: true));
  }

  ///Mimic the song page to be displayed while the song is fetched
  Widget _pageLoading(BuildContext context, SongLink songLink) {
    var urlCover = '$baseUri/images/pochettes/${songLink.id}.jpg';

    var loadingMessage = '';
    if (songLink.title.isNotEmpty) {
      loadingMessage += songLink.title;
    } else {
      loadingMessage = 'Chargement';
    }

    final tag = createTag(songLink);

    var body = Column(
      children: <Widget>[
        Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(
                    padding: EdgeInsets.only(bottom: 8.0, top: 8.0),
                    child: Hero(tag: tag, child: Image.network(urlCover))),
                Expanded(child: Center(child: CircularProgressIndicator())),
              ],
            )),
        Expanded(
          flex: 7,
          child: Container(
            child: Stack(children: [
              Container(
                decoration:
                    BoxDecoration(color: Colors.grey.shade200.withOpacity(0.7)),
              ),
              Center(child: CircularProgressIndicator())
            ]),
            decoration: BoxDecoration(
                image: DecorationImage(
              fit: BoxFit.fill,
              alignment: FractionalOffset.topCenter,
              image: NetworkImage(urlCover),
            )),
          ),
        ),
      ],
    );

    return Scaffold(appBar: AppBar(title: Text(loadingMessage)), body: body);
  }

  _newMessageDialog(BuildContext context, Song song) {
    _commentController.text = '';

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Nouveau commentaire'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextFormField(
                    maxLines: 5,
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Entrez votre commentaire ici',
                    )),
                RaisedButton(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30.0)),
                    child: Text(
                      'Envoyer',
                    ),
                    onPressed: () {
                      _sendAddComment(song);
                      Navigator.of(context).pop();
                    },
                    color: Colors.orangeAccent),
              ],
            ),
          ),
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
          title: Text('Edition d\'un commentaire'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextFormField(
                    maxLines: 5,
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Entrez votre commentaire ici',
                    )),
                RaisedButton(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30.0)),
                    child: Text(
                      'Envoyer',
                    ),
                    onPressed: () {
                      _sendEditComment(song, comment);
                      Navigator.of(context).pop();
                    },
                    color: Colors.orangeAccent),
              ],
            ),
          ),
        );
      },
    );
  }

  void _sendEditComment(Song song, Comment comment) async {
    String text = _commentController.text;
    text = text.replaceAll(RegExp(r'é'), 'e');
    text = text.replaceAll(RegExp(r'è'), 'e');

    if (text.isNotEmpty) {
      await Session.post('$baseUri/edit_comment.html?Comment__=${comment.id}',
          body: {
            'mode': 'Edit',
            'REF': song.link,
            'Comment__': comment.id,
            'Text': text,
          });
    }
  }

  void _sendAddComment(Song song) async {
    String comment = _commentController.text;
    comment = comment.replaceAll(RegExp(r'é'), 'e');
    comment = comment.replaceAll(RegExp(r'è'), 'e');

    final url = song.link;

    if (comment.isNotEmpty) {
      await Session.post(url, body: {
        'T': 'Song',
        'N': song.id,
        'Mode': 'AddComment',
        'Thread_': '',
        'Text': comment,
        'x': '42',
        'y': '42'
      });
    }
  }

  Widget _buildView(BuildContext context, Song song) {
    var urlCover = '$baseUri/images/pochettes/${song.id}.jpg';
    final _fontLyrics = TextStyle(fontSize: 18.0);
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
                          child: Hero(
                              tag: tag,
                              child: InkWell(
                                  onTap: () {
                                    _openCoverViewerDialog(
                                        widget.songLink, context);
                                  },
                                  child: Image.network(
                                      '$baseUri/images/pochettes/${widget.songLink.id}.jpg')))),
                      Expanded(child: SongWidget(song)),
                    ],
                  ))
            ])),
          ),
        ];
      },
      body: Center(
          child: Container(
        child: Stack(children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              decoration:
                  BoxDecoration(color: Colors.grey.shade200.withOpacity(0.7)),
            ),
          ),
          PageView(
            onPageChanged: (int page) => setState(() {
              _currentPage = page;
            }),
            children: <Widget>[
              SingleChildScrollView(
                  child: Padding(
                padding: EdgeInsets.only(left: 8.0, top: 2.0),
                child: Html(
                    data: song.lyrics,
                    defaultTextStyle: _fontLyrics,
                    onLinkTap: (url) {
                      onLinkTap(url, context);
                    }),
              )),
              _buildViewComments(context, song),
            ],
          )
        ]),
        decoration: BoxDecoration(
            image: DecorationImage(
          fit: BoxFit.fill,
          alignment: FractionalOffset.topCenter,
          image: NetworkImage(urlCover),
        )),
      )),
    );

    var postNewComment = Session.accountLink.id == null || _currentPage != 1
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
              onLinkTap: (url) {
                onLinkTap(url, context);
              }),
          subtitle: Text('Par ' + comment.author.name + ' ' + comment.time,
              style: comment.author.name == loginName ? selfComment : null),
          trailing: comment.author.name == loginName ?  IconButton(
            icon: Icon(Icons.edit),
            onPressed: () async {
              _editMessageDialog(context, song, comment);
            },
          ) : null));
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
      rows.add(ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.black12,
            child: heroThumbCover(songLink),
          ),
          title: Text(
            songLink.title,
          ),
          trailing: songLink.isNew ? Icon(Icons.fiber_new) : null,
          subtitle: Text(songLink.artist == null ? '' : songLink.artist),
          onTap: () => launchSongPage(songLink, context)));
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

class SongWidget extends StatelessWidget {
  final Song _song;

  SongWidget(this._song);

  @override
  Widget build(BuildContext context) {
    var textSpans = <TextSpan>[];

    if (_song.year != 0) {
      textSpans.add(TextSpan(
          text: _song.year.toString() + '\n',
          recognizer: TapGestureRecognizer()
            ..onTap = () => {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                    'Recherche de l\'année "${_song.year.toString()}"'),
                              ),
                              body: SearchResultsWidget(
                                  _song.year.toString(), '7')))),
                }));
    }

    if (_song.artist != null) {
      textSpans.add(TextSpan(
          text: _song.artist + '\n',
          recognizer: TapGestureRecognizer()
            ..onTap = () => {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ArtistPageWidget(
                              artist: fetchArtist(_song.artistId)))),
                }));
    }

    if (_song.durationPretty != null) {
      textSpans.add(TextSpan(text: _song.durationPretty + '\n'));
    }

    if (_song.label != null) {
      textSpans.add(TextSpan(
          text: _song.label + '\n',
          recognizer: TapGestureRecognizer()
            ..onTap = () => {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => Scaffold(
                              appBar: AppBar(
                                title:
                                    Text('Recherche du label "${_song.label}"'),
                              ),
                              body: SearchResultsWidget(_song.label, '5')))),
                }));
    }

    if (_song.reference != null) {
      textSpans.add(TextSpan(text: _song.reference.toString() + '\n'));
    }

    final textStyle = TextStyle(
      fontSize: 18.0,
      color: Colors.black,
    );

    return Center(
        child: RichText(
            textAlign: TextAlign.left,
            text: TextSpan(style: textStyle, children: textSpans)));
  }
}
