import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;

class GoogleAuthHttpClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner;

  GoogleAuthHttpClient(this._headers, {http.Client? inner}) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class GoogleCalendarService {
  final GoogleSignIn _googleSignIn;

  GoogleCalendarService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: <String>[
                'email',
                gcal.CalendarApi.calendarScope,
              ],
            );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> signInSilently() => _googleSignIn.signInSilently();

  Future<GoogleSignInAccount?> signInInteractive() => _googleSignIn.signIn();

  Future<void> signOut() => _googleSignIn.signOut();

  Future<void> disconnect() => _googleSignIn.disconnect();

  Future<void> ensureFirebaseSignedIn(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    final accessToken = auth.accessToken;
    final idToken = auth.idToken;
    if (accessToken == null || idToken == null) return;

    final credential = GoogleAuthProvider.credential(
      accessToken: accessToken,
      idToken: idToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<T> withCalendarApi<T>({
    required bool interactive,
    required Future<T> Function(gcal.CalendarApi api) run,
  }) async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    final signedIn = account ?? (interactive ? await _googleSignIn.signIn() : null);
    if (signedIn == null) {
      throw StateError('Google Sign-In cancelado o no disponible');
    }

    final headers = await signedIn.authHeaders;
    final client = GoogleAuthHttpClient(headers);
    final api = gcal.CalendarApi(client);
    try {
      return await run(api);
    } finally {
      client.close();
    }
  }

  Future<List<gcal.CalendarListEntry>> listCalendars({bool interactive = false}) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) async {
        final entries = <gcal.CalendarListEntry>[];
        String? pageToken;
        do {
          final resp = await api.calendarList.list(pageToken: pageToken);
          entries.addAll(resp.items ?? const <gcal.CalendarListEntry>[]);
          pageToken = resp.nextPageToken;
        } while (pageToken != null && pageToken.isNotEmpty);
        return entries;
      },
    );
  }

  Future<gcal.Calendar> getCalendar(String calendarId, {bool interactive = false}) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) => api.calendars.get(calendarId),
    );
  }

  Future<gcal.Calendar> insertCalendar(gcal.Calendar calendar, {bool interactive = false}) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) => api.calendars.insert(calendar),
    );
  }

  Future<gcal.Calendar> updateCalendar(
    String calendarId,
    gcal.Calendar calendar, {
    bool interactive = false,
  }) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) => api.calendars.update(calendar, calendarId),
    );
  }

  Future<void> deleteCalendar(String calendarId, {bool interactive = false}) async {
    await withCalendarApi(
      interactive: interactive,
      run: (api) => api.calendars.delete(calendarId),
    );
  }

  Future<gcal.CalendarListEntry> getCalendarListEntry(
    String calendarId, {
    bool interactive = false,
  }) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) => api.calendarList.get(calendarId),
    );
  }

  Future<gcal.CalendarListEntry> updateCalendarListEntry(
    String calendarId,
    gcal.CalendarListEntry entry, {
    bool interactive = false,
  }) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) => api.calendarList.update(entry, calendarId),
    );
  }

  Future<List<gcal.Event>> listEventsInWindow({
    required String calendarId,
    required DateTime timeMinUtc,
    required DateTime timeMaxUtc,
    bool interactive = false,
  }) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) async {
        final events = <gcal.Event>[];
        String? pageToken;
        do {
          final resp = await api.events.list(
            calendarId,
            timeMin: timeMinUtc,
            timeMax: timeMaxUtc,
            singleEvents: true,
            orderBy: 'startTime',
            showDeleted: false,
            pageToken: pageToken,
          );
          events.addAll(resp.items ?? const <gcal.Event>[]);
          pageToken = resp.nextPageToken;
        } while (pageToken != null && pageToken.isNotEmpty);
        return events;
      },
    );
  }

  Future<gcal.Event> insertEvent({
    required String calendarId,
    required gcal.Event event,
    String? sendUpdates,
    bool interactive = false,
  }) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) => api.events.insert(
        event,
        calendarId,
        sendUpdates: sendUpdates,
      ),
    );
  }

  Future<gcal.Event> updateEvent({
    required String calendarId,
    required String eventId,
    required gcal.Event event,
    String? sendUpdates,
    bool interactive = false,
  }) async {
    return withCalendarApi(
      interactive: interactive,
      run: (api) => api.events.update(
        event,
        calendarId,
        eventId,
        sendUpdates: sendUpdates,
      ),
    );
  }

  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
    String? sendUpdates,
    bool interactive = false,
  }) async {
    await withCalendarApi(
      interactive: interactive,
      run: (api) => api.events.delete(
        calendarId,
        eventId,
        sendUpdates: sendUpdates,
      ),
    );
  }
}

