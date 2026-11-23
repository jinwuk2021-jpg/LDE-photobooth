// Booth constants. Server values come from booth_defines.json at build time
// (flutter run --dart-define-from-file=booth_defines.json, see README).
// ignore_for_file: constant_identifier_names

/// This booth's own share Worker (../server, "lde-booth"), at lenslycam.com/lde. Not Lensly's Worker.
const String SHARE_API_URL = String.fromEnvironment('SHARE_API_URL', defaultValue: 'https://lenslycam.com/lde');

/// The Worker's BOOTH_KEY secret. Empty = nothing is uploaded (files stay in the queue).
const String BOOTH_KEY = String.fromEnvironment('BOOTH_KEY');

/// Least shots per guest (a frame with more windows gets 2 spare: BoothLayout.shots).
const int SHOTS = 6;

/// Countdown seconds before the first shot and before each next one.
const int FIRST_COUNTDOWN = 5;
const int NEXT_COUNTDOWN = 3;

/// "Chuẩn bị nhé!" before the first countdown: the guest has just tapped the screen and is
/// stepping back, which must not end up in the first shot's Live clip.
const Duration READY_DELAY = Duration(seconds: 3);

/// No touch for this long on the frame picker → back to the start screen.
/// (The photo picker has its own visible limit: BoothSettings.pickSeconds.)
const Duration IDLE_TIMEOUT = Duration(seconds: 60);

/// The thank-you screen goes back to the start screen after this.
const Duration THANKS_TIMEOUT = Duration(seconds: 25);

const String ADMIN_PIN = '1234';

/// Album in the iPad's Photos app that every print (with its QR) is copied into.
const String PHOTOS_ALBUM = 'Photobooth';

// Printing on the SELPHY is switched on in admin (BoothSettings.printing), off by default.

/// Live: length of the clip kept before the shutter, and file segment length (as in Lensly).
const Duration LIVE_WINDOW = Duration(seconds: 5);
const Duration LIVE_SEGMENT = Duration(seconds: 1);

/// Long side of each developed photo (the print cell is ~530 px wide, the download gets this).
const int PHOTO_LONG_SIDE = 1600;
