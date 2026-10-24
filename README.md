# Sun for iOS

An iPhone version of the [Sun desktop music player](https://github.com/Carlos-J-Falconett/Personal-Music-app), built with SwiftUI, SwiftData and AVAudioEngine for iOS 27. It keeps the desktop app's look, with the artist's picture filling the screen behind see-through Liquid Glass panels, and most of its features. Lyrics work like the desktop app's (see Lyrics below). Black Hole mode is not included.

## Features

### Library
- **Importing:** tap **+** and pick songs or whole folders in the Files app (MP3, M4A/AAC/ALAC, FLAC, WAV, AIFF, CAF).
  - **In the Files app:** the app's own storage shows as **On My iPhone → Sun** (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`), with imported and downloaded songs in its `Music` folder. Deleting a file there leaves the song in the library but it can't play (it's skipped).
  - The app copies files into its own storage and never changes your originals.
  - Folder structure is kept, and files already in the library are skipped.
- **Tags:** read with AVFoundation. Files without tags take their names from their folders (`Artist/Album/Song.ext`), and a leading track number like `01 - ` is removed from the title.
- **Covers:** taken from the embedded artwork. Otherwise the app looks for a folder image named `cover`, `folder`, `front`, `album` or `albumart`, then any image in the folder.
- **Tabs:** Home · Library · Stats · Settings, plus Search pinned at the end of the tab bar. The app opens on Home. Five tabs fit without iOS folding any into a "More" tab, which happened with six.
  - **Fixed headers:** Home, Library and Stats each have their header (title, buttons, chips) in a fixed area at the top (`pinnedHeader`). The page's content scrolls below it, so rows and cards never slide underneath the title and buttons. The artist backdrop still shows behind both.
  - **Home** (`UI/HomeView.swift`): the app's name, **Sun**, with its version next to it (e.g. "v1.0", read from the app's Info.plist via `AppInfo`, so it follows the version set in Xcode), and a glowing **Shuffle All** icon button. Underneath, horizontal shelves of up to 15 items each. Hidden artists are left out, like All Songs:
    - **Recently Played:** songs, newest first. Tapping one plays the shelf from that song, and long-press has the usual song actions.
    - **Top Artists This Week:** artists by listening time over the past 7 days (same crediting as the listening sorts), with their time. Opens the artist page.
    - **Recently Added:** albums by when their newest song was imported. Opens the album page.
    - A shelf with nothing in it yet shows a short hint instead.
  - **Library** (`LibraryView`): a compact header replaces the navigation bar on this page, so the list starts high on the screen.
    - **Title:** the current section's name ("Songs", "Albums", "Artists", "Genres" or "Playlists"), which changes with the chips.
    - **Icon buttons** on the same line as the title: **Play** and **Shuffle** play every song (except hidden artists) in the Songs sort order, then **Sort** on Songs, Albums, Artists and Genres, or **New Playlist** on Playlists. They're round glass buttons with VoiceOver labels; Play is tinted with the ambient accent. The icons scale with the text size, and at accessibility sizes the buttons move under the title.
    - **Chips** under the title switch between sections. The last section used is remembered. No chip is ever cut off by the screen edge: at normal text sizes all five sit in one row at their natural widths, spread evenly across the screen. The chips use a compact footnote-bold label with tight padding (10 pt sides, 4 pt minimum gaps), so Songs · Albums · Artists · Genres · Playlists fit on one row on any iPhone (on a 440 pt screen they end 16 pt from the edge); when they don't fit (large text sizes) they wrap onto a second line (`FlowLayout`).
    - **Sorting** (`UI/Library/LibrarySorts.swift`): each section remembers its own order. The Sort menu has two groups:
      - **Sort By:** Songs by Title, Artist, Album or Recently Added; Albums by Title, Artist, Year (newest first) or Recently Added; Artists and Genres by Name or Most Songs.
      - **Listening** (from your listening history, the same sessions as Stats):
        - **Most Listened:** total listening time.
        - **Most Played:** plays, then time.
        - **Recently Played:** when you last listened.
        - **Least Played:** never-played first, to rediscover forgotten music.
      - **Show → Lossless Only** (Songs): only lossless songs (FLAC, ALAC, WAV, AIFF, uncompressed CAF) are listed, and Play / Shuffle in the header play just those. The header reads "Lossless Songs" and the Sort button's icon changes while it's on. Remembered like the sort (`SongFilter`).
      - With a Listening order, every row shows the number it's sorted by ("7 plays", "9m", "Played yesterday"), and the section header names the order. Ties fall back to name order.
      - **Totals** (`Stats/ListeningTotals.swift`): summed per song, artist and genre off the main thread, and only when listening history changes. An artist's total comes from the songs listed on their page (main, featured and group songs), so it matches the page. Songs deleted from the library use the saved artist text, like Stats.
    - Pages opened from Library (artist, album, genre, playlist) keep the normal bar with a back button, and their own Play / Shuffle buttons.
    - **Songs:** a list of glass rows. The "All Songs" bar is the list's first row and scrolls away with it (as a sticky section header, songs slid underneath it).
    - **Albums** (`UI/Library/AlbumsView.swift`): a grid of covers with artist and year, for every album in the library (hidden artists left out). Albums are grouped by name and owner (Album Artist, else the main artist), so two "Greatest Hits" from different artists stay apart. A listening sort totals every song on the album.
    - **Artists:** a grid of large circles, three per row, with a two-color glow rim. Each circle shows the artist's **latest album cover** (`LibraryGrouping.latestAlbumCover`): the newest year (an album's year is its earliest song's), then the most recently imported; albums they own (Album Artist, else main artist) come before guest spots on other artists' albums, and a group member without solo albums gets the group's newest. The same circles are used on Home, in Search and in Member of…. Each shows the song count, or the number it's sorted by. Hidden artists are greyed out and labelled "Hidden", and long-press hides or unhides.
    - **Genres:** a grid of cover cards.
    - **Playlists:** a grid of cover cards with Favorites first (a heart). Long-press a playlist to delete it, since a grid has no swipe-to-delete.
  - **Stats** (see Stats below).
  - **Settings** (`UI/SettingsView.swift`): a **Library** card at the top with the song count (and hidden artists, which explains why All Songs shows fewer songs) and a glowing **Sync Music** button: it syncs with the media server (see Media Server below), shows progress and the result in the card, and turns into **Stop Sync** while running. Before the server is set up it reads **Set Up Sync** and opens Settings → Media Server. Adding songs from the phone is the **Import from Files** row right under the card (songs or whole folders, copied into the app). Below it, grouped rows with colored icon tiles like the system Settings app (`SettingsRowLabel`): **Theme**, **Show Album Cover** for Now Playing, **Media Server** (see Media Server below), **Lyrics** (see Lyrics below), **Duplicates** (see Lossless and duplicates below), and **Playback Problems**. The Library card also says how many duplicate copies are hidden (counted apart from hidden artists' songs, so the numbers add up). The tiles use the theme's Primary, Secondary and Highlight colors, with a black or white symbol by the 3:1 contrast rule, and grow with the text size.
- **Search** is a tab (`Tab(role: .search)`), always one tap away. The field is always shown under the title, and it searches artists, albums, songs and genres. Results open artist and album pages inside the tab, and going back keeps your search.
  - On this iOS version the search tab is drawn inside the tab bar rather than as a separate round button, even with the field on the tab view, so the field lives on the Search page.
- **Artist credits** (`Library/ArtistCredits.swift`): songs with several artists are listed under each of them.
  - **Always split:** `feat`, `feat.`, `ft.`, `featuring` and `f/` separate the main artists from the featured ones. Inside the featured part, `,`, `&` and ` / ` always split, as in "Calle 13 feat. Totó la Momposina / Susana Baca / Maria Rita".
  - **Smart split:** elsewhere, `,`, `&`, ` x `, ` + ` and ` with ` split only when one of the pieces is already its own artist in your library.
    - "Bad Bunny & Chuwi" splits because Bad Bunny is already an artist in the library.
    - "Of Mice & Men", "Wolf & Bear", "Sleeping With Sirens" and "Florence + the Machine" stay whole.
    - Splitting repeats, so newly found artists (like Chencho Corleone) unlock more splits.
  - **Never guessed:** "Daryl Palumbo of Glassjaw" stays one name, and slashes outside a featured part (like "AC/DC") are never split.
  - **More separators:** `;` always splits (taggers use it for multiple artists, e.g. "Telemann; Kuijken"), and ` × ` works like ` x `.
  - **Titles count too:** "(feat. X)", "[ft. X]" and "(with X)" in a song title add X as a featured artist. The title itself isn't changed.
  - **Album years:** an album's year and cover come from the whole album (every song with that name and Album Artist), so it shows the same year on every artist's page, even if a featured song has a different year tag.
  - **Albums:** a featured song shows on each artist's page inside its real album, with a "with …" note. Albums are grouped by the **Album Artist** tag, so "WELTiTA" (Bad Bunny & Chuwi) stays in *DeBÍ TiRAR MáS FOToS*.
  - **Primary artist:** the first main artist. Hiding and the backdrop use it.
- **Groups and members:**
  - **From tags:** when a song's Album Artist (e.g. **TWICE**) isn't credited on the song (e.g. SANA's solo song on *TEN: The Story Goes On*), the song also appears on the group's page, and SANA counts as a TWICE member.
  - **Group page:** only members' songs on the group's albums appear there. Members' own albums stay on their pages.
  - **Members' pages:** they say "Member of TWICE", and the Artists list shows "TWICE · …".
  - **Not groups:** these Album Artist values are ignored when looking for groups:
    - Compilations like "Various Artists".
    - **Database IDs** instead of names. "Hush (Still Woozy remix)" had `7a3970c9-…` as its Album Artist, which made The Marías look like a member of a "random group".
    - **The song's own artists written differently:** "Bad Bunny ft. Drake", "Becky G + Paulo Londra" against "Becky G & Paulo Londra", "MY FIRST STORY × HYDE" against "HYDE × MY FIRST STORY".
  - **Collaborations and soundtracks don't make members:** if the Album Artist is co-credited with others anywhere on the album (the NieR:Automata soundtrack credits Keiichi Okabe alongside his co-composers), or the album is a soundtrack/OST/score, nobody becomes a "member". The songs still appear on the Album Artist's page.
  - Featured guests on a group song (e.g. Megan Thee Stallion on "Strategy") aren't members either.
  - **By hand:** for files without an Album Artist, use the **…** menu on an artist's page → **Member of…** (search for the group). Their songs on that group's albums then join the group page.
  - **Album Artist tags:** they are now saved for new imports, and were re-read once for existing songs in the background.
- **Song actions:** each song has a context menu and swipe actions: Play Next, Add to Queue, Favorite, Add to Playlist, and Remove from Library.
- **Hidden artists:** long-press an artist in Browse → Artists (or use the **…** menu on their page) and choose **Hide Artist**. Rules live in `HiddenArtistRules`:
  - A song counts as hidden only when the hidden artist is its **primary (first) artist**. Hiding Chuwi doesn't hide "Bad Bunny & Chuwi"; hiding Bad Bunny does.
  - Their songs don't appear in **All Songs** or **Search** (the artist still shows in search, dimmed, so their page is reachable).
  - Play / Shuffle never queue them, including from **Genres**. Genre lists still show their songs (dimmed, with an eye-slash); tapping one plays it, and the rest of the queue skips hidden artists.
  - They play normally from their **own artist page** (and its albums), **playlists** and **Favorites**, since opening those is intentional.
  - Hiding an artist also removes their songs from **Up Next**.
  - In the Artists list they stay visible, greyed out with an eye-slash and "Hidden · N songs". Choose **Unhide Artist** to undo.
  - Listening stats still include them.

### The see-through look
- **Backdrop layers**, bottom to top, the same as desktop `backdrop.py`:
  1. Window color.
  2. A pre-blurred copy of the image, filling the screen. It's shrunk to 24 px on its short side, then scaled back up to 384 px.
  3. A 35% black veil.
  4. The sharp image, shown whole.
- **Crossfade:** the backdrop crossfades over 800 ms when the artist changes, and stays put when the next song is by the same artist.
- **One image per artist:** each artist has a single **Artist Image** (`ArtistImage`). It shows behind the player while their songs play, and fills the top of their artist page. (Circles in lists show their latest album cover instead.)
  - (A build briefly had a separate Artist Picture and Background. At launch, `ArtistArtwork.mergeLegacyBackgrounds` moves any of those backgrounds into `ArtistImage`, the background winning since it's what showed behind the player, and deletes them. The old `ArtistBackground` model stays in the schema only for that.)
- **Image source:** in this order:
  1. The primary artist's own image.
  2. Their group's image, so TWICE members show TWICE's image until you give them their own.
  3. The current song's album cover.
- **Choosing an image:** artist page → **…** → **Choose Artist Image…** opens Photos (**Remove Artist Image** goes back to the group's image or an album cover). The old button did nothing because a photo picker can't open from inside a menu.
  - Picked photos are downsampled to 3000 px, then shown in the framing screen (`ArtistImageCropper`, titled "Artist Image" with the artist's name underneath), with three choices:
    - **Whole Picture** (the default): the entire image at its own shape, uncropped.
    - **Screen:** pinch and drag to choose a section shaped like the phone's screen, so it fills the background exactly.
    - **Square:** pinch and drag to choose a square section.
  - The picture is saved at up to 2048 px on its long side, keeping its shape (it used to be forced into a square, which cut off the sides of wide or tall photos). A checkerboard behind the picture shows any see-through areas.
  - **Transparent pictures** (e.g. a cut-out artist PNG) keep their transparency: `ArtCache` saves them as PNG instead of JPEG (`ArtCache.hasTransparency`). Behind the player they get no blurred copy and no edge fade; instead a soft wash of the glow colors sits behind them, and a glow in the glow colors is traced around the subject's outline (shadows of a transparent image follow its visible pixels). Hidden with Reduce Transparency. In circles and cards they sit on the theme's panel color.
  - Pictures set before this change were saved as squares, so set them again to show the whole picture.
- **Artist page:** the artist's image (their own, their group's, or their latest album's cover) sits fixed behind the page, standing on the **bottom edge of the screen** wherever the discography starts, and the discography scrolls up over it (`ArtistPageBackdrop`). The page uses its own image even when another artist is playing.
  - **Picture position:** full width, its bottom on the screen's bottom edge, however tall it is (Whole Picture is never cropped at the sides; Fill Screen also sits on the bottom edge, its top cropped if needed). Its top fades at least 12% into the blur above it. Zooming in Adjust Background… grows it upward from the bottom edge; moving it is still possible there.
  - **Where the name starts:** unchanged by the picture's position. The space above the name is the image's height at full width, but at least 42% of the screen and at most 62% (so the name, Play / Shuffle and the first album are always on screen) (`ArtistArtwork.heroHeight`).
  - **Name:** large and left-aligned at the picture's lower edge, with the member line, album and song counts, and Play / Shuffle underneath. The navigation bar shows the name only once the big one has scrolled away.
  - **No jump:** that space is worked out from the picture's shape, read from the file's header (`ArtCache.aspectRatio(of:)`), so the layout is right before the image has loaded.
  - **Transparent pictures:** the glow-color wash and outline glow take this picture's own colors (with Match Artwork on); cut-outs stand on the bottom edge with no fade.
- **Adjust Background… (per artist):** artist page → **…** → **Adjust Background…** opens a full-screen editor (`BackdropStyleEditor`) with a live preview, switchable between **Player** (behind Now Playing and every page while their songs play) and **Artist Page** (the top of their page, with their name where it sits). The settings apply to whichever picture is shown for them (their image, their group's, or an album cover).
  - **Separate framing:** the position, zoom and Whole Picture / Fill Screen choice are separate for the player and the artist page (`BackdropFraming`: `BackdropStyle.player` and `.page`). The preview chip picks which one dragging, pinching and the fit chips change, and a caption under the chips says which. Brightness, Dim, Blur, Edge Fade and Glow are shared. Artists adjusted before this was split keep their look on both screens: the page framing starts as a copy of the player's (stored as optional `page…` fields; `nil` = same as the player).
  - **Whole Picture / Fill Screen:** the picture at its own shape, never cropped, or covering the whole screen with its edges cropped. With Fill Screen the artist page gives the picture the full 62% of the screen.
  - **Move and zoom:** drag the preview to move the picture, pinch to zoom (50%–500%). The move is stored as a fraction of the screen, so it looks the same on any iPhone.
  - **Brightness** (−60% to +30%) darkens or lightens the picture itself; **Dim** (0–85%) is the veil over the blurred area around it, in the theme's Backdrop Dim color; **Blur** is that area's blur; **Edge Fade** (0–35%) is how much of the picture's top and bottom fades into the blur.
  - **Glow** (transparent cut-outs only): the outline glow's strength, 0–200%.
  - **Reset** → Reset Position & Zoom (only the framing being edited), Copy from Player / Copy from Artist Page (start from the other one's framing), or Reset Everything. **Save** uses the lighter accent so it reads on the dark glass. **Hide Controls** hides the panel to see the whole preview. Saving the standard look removes the artist's settings.
  - Stored per artist in `ArtistBackdropStyle` (artist key + the settings); group members without their own use their group's. Without any, the standard look (`BackdropStyle.standard`: 35% dim, 12 pt blur, 4% fade for artist pictures, 14% for covers, none for cut-outs) is the same as before.
  - Drawn by `StyledBackdrop`, shared by the player backdrop (`BackdropView`), the artist page (`ArtistPageBackdrop`) and the editor's preview, so all three always match.
- **Feathered edges:** the sharp image fades into the blur at its top and bottom, so there's no hard line where it ends. Album covers fade over 14% at each end; artist pictures only 4%, so the whole picture shows; transparent pictures don't fade at all.
- **Readable secondary text:** secondary text is the text color at 70% (the desktop uses 58%, which was too faint over bright pictures). Dimmed hidden-artist rows are at 75%, and the Now Playing album line at 80%.
- **Glass:** list rows, cards, section headers, the tab bar, the mini player and the Now Playing controls use Liquid Glass.
  - Every glass surface goes through one modifier, `glassCard()`. It puts a dimming layer in **Glass Panel Tint** at the theme's **Glass Opacity** between the glass and the content, so text stays readable over bright pictures.
  - **Glow (the "ambient" look):** glass edges have a thin two-color rim in the glow colors (`GlowRim`), and cards have a soft halo of the same colors behind them. List rows keep the rim but skip the halo, because a blurred halo on every row would slow scrolling. Covers and prominent buttons use `ambientGlow()`. Rims and halos are hidden when **Reduce Transparency** is on.
  - Text on glass gets a soft shadow (`legibleOnGlass()`). Headings that sit straight on the backdrop get a stronger one.
  - Section headers are pinned glass bars, so rows scrolling under them stay hidden.
- **Tab bar:** it always stays full size (no collapsing while scrolling) and uses the same glass tint. The mini player above it is tinted a little stronger so list text doesn't show through.
- **Portrait only:** the app is locked to portrait on iPhone (iPad allows portrait and upside-down portrait).

### Design system
Shared values live in `UI/Components/Styling.swift`, so every screen lines up the same way:
- `Layout`: 16 pt page margin, 8 pt row spacing, rounded corners (20 pt rows, 28 pt cards, 32 pt sheets, 14 pt row covers), 48 pt song covers, 56 pt artist/playlist pictures, and an 8/16/28 pt spacing scale.
- `Motion`: `standard` (a smooth 0.6 s) for taps and panels, and `ambient` (1.2 s) for color changes between songs.
- **Type:** SF Pro Rounded everywhere (`.fontDesign(.rounded)` on the tab view, Now Playing and sheets). Navigation bar titles are drawn by UIKit, so `Typography.configureNavigationBars()` gives them a heavy rounded large title and a bold rounded inline title, still following Dynamic Type.
- `GlowCapsuleButton`: Play / Shuffle capsules. The prominent one is tinted with the ambient accent and glows. Labels never wrap, and at accessibility text sizes `PlayShuffleRow` stacks the two buttons.
- `ChipPicker`: glass chips used as a segmented control. The selected chip takes the ambient accent. Chips are always fully on screen: one evenly spread row when they fit, otherwise wrapped onto more lines with `FlowLayout`, a small left-to-right wrapping layout.
- `SectionHeader`: bold section title with an optional count.
- `DetailHeader`: the shared top of artist, album, genre, playlist and Favorites pages: 230 pt artwork with a two-color rim and a soft halo, a heavy rounded title, details, and Play / Shuffle. The rim and halo take their colors from **that page's own artwork** (not the playing song), via the same cached `ArtworkPalette`, so each album glows in its own colors. With Match Artwork off, or a colorless cover, they use the theme's glow colors. The halo is hidden with Reduce Transparency.
- `PageHeader`, `HeaderIconButton`, `HeaderIconMenu` (`UI/Components/LibraryComponents.swift`): the compact title-plus-icon-buttons header shared by Home, Library and Stats, with optional small text after the title (`titleDetail`, Home's version). `pinnedHeader(_:)` fixes it at the top with the content scrolling below it. Icons sit in a fixed, text-size-scaled square so every circle is the same size.
- `CoverCard`, `ArtistCircle`, `ShelfSection`: the grid and shelf building blocks shared by Home and Library.
- `libraryListStyle()`, `glassRow()` and `plainListRow()`: list styling.

### Now Playing
- **Opening:** tap the mini player above the tab bar. VoiceOver reads it as a "Now playing: song by artist" button.
- **Layout** (top to bottom, `UI/Player/NowPlayingView.swift`):
  - **Top bar:** a round glass close button, "Now Playing" with the album name under it, and the **cover button** (photo icon).
  - **The square:** three pages side by side, **Cover · Queue · Equalizer**. Swipe sideways to change page (`.scrollTargetBehavior(.paging)`), or tap the glass **switcher** under the square. The current page's capsule is wider and takes the ambient accent. With Reduce Motion on, tapping the switcher jumps straight to the page.
    - **Cover** (the default page). It's empty, so only the artist backdrop shows. The cover button puts the album cover there, with a two-color glow rim and halo; it's inset further than the glow reaches, so the glow fades out instead of being cut off in a straight line at the page's edge. This setting is remembered, and is also in Settings → **Show Album Cover**. Turning it on also returns to the Cover page.
    - **Queue:** "Up Next". Tap a song to jump to it, swipe to remove, use **Edit** to drag songs into a new order, or **Clear**.
    - **Equalizer:** 10 bands from 31 Hz to 16 kHz at ±12 dB, with presets. **Save for this song** keeps a separate EQ curve for the current song.
    - The queue and EQ pages sit on Liquid Glass with the panel tint (`nowPlayingPanel()`). The old card turn rotated glass in 3D, which smeared, so it used a frosted material; with flat paging, real glass renders cleanly.
  - **Song info:** the title (heavy, up to two lines) and artist. **Tapping the artist** (marked with a ›) closes Now Playing and opens their page in the current tab (Library from Settings), without stacking a second copy if that page is already open. Songs with several artists ("A & B", "feat. C") show a menu to pick one. It uses `AppState.pendingRoute` and each tab's navigation path in `RootView`. Then **Favorite** (the heart turns the Highlight color) and **Add to Playlist** as round glass buttons.
  - **Wave visualizer:** 104 pt tall and edge to edge, past the page margins.
  - **Timeline:** a capsule with a two-color fill in the glow colors that thickens and glows while you drag it, plus elapsed and remaining time. It redraws four times a second while playing, and not at all while paused.
  - **Controls:** a large glass **Play/Pause** circle (78 pt, grows with the text size) tinted with the ambient accent, glowing brighter while playing; large Previous / Next icons with 56 pt tap areas; and **Shuffle** and **Repeat** (off → queue → song) as small glass circles that take the accent when on.
  - **No volume slider:** on a phone the device's buttons control volume, so Now Playing doesn't have its own. (The app's internal volume isn't saved and always starts at full, so only the device volume matters.)
- **Fixed square size:** the square's size comes from a plain placeholder with the pages laid on top. That way the queue's list can't feed back into the screen layout. Before this, opening the queue right as a song ended could hang the app. On short screens and at large text sizes the square shrinks to make room, so nothing is pushed off screen.
- **Wave visualizer:** the desktop app's red/blue ribbon, drawn from the live post-EQ spectrum.
  - 64 log-spaced bins from 50 Hz to 16 kHz, with a +3 dB/octave tilt.
  - Lobes alternate up and down with flat tails at each end, and the two edges twist.
  - At rest it settles into two flat lines.
- **Queue order:** like desktop, the original order is kept, so turning shuffle off restores it.
  - Each queued song is exactly one list row, so a whole shuffled library opens instantly. Edits use queue-entry ids (`reorderUpcoming`, `removeUpcoming(ids:)`).
- **Unplayable songs:** files that are missing or can't be opened are skipped in a bounded loop. A queue of only bad files stops instead of looping forever with Repeat on.
  - **Retry first:** before skipping, the player resets the audio engine and tries the song once more (`PlayerEngine.recover()`). Most failures on a good file come from the audio session being taken away without notice, by a call, Siri, another app or Bluetooth switching. The reset re-activates the session.
  - **Starting playback:** if the engine won't start, the session is re-activated and the start retried. Pressing play no longer fails silently. A failed restart after a hardware change (e.g. AirPods connecting) now pauses visibly instead of "playing" with no sound.
  - **The message names the songs and the reason**, e.g. "the audio engine wouldn't start (NSOSStatusErrorDomain 561015905)".
  - **Settings → Playback Problems** keeps the last 50 problems, with song, file, time, reason, whether the app was in the background, and whether the retry fixed it (`PlaybackIssueLog`).
  - **Ruled out:** a check on the phone showed all 1,587 files use the normal file protection, so locked-screen playback can read them.

### Media Server (downloading music from home)
Sun can download music from a personal media server running on a PC at home, reached through **Tailscale** over HTTPS (so no App Transport Security exceptions or Local Network permission are needed). The server says what exists and what changed; the phone keeps its own copy, so everything plays offline.
- **Settings → Media Server** (`UI/MediaServerSettings.swift`):
  - **Server Address:** the server's Tailscale address (`https://<pc>.<tailnet>.ts.net`). Saved as a setting; there's no default in the code. Tailscale must be connected on the iPhone (VPN On Demand in the Tailscale app keeps it connected).
  - **Device Token:** this iPhone's token from the server's `config.toml`. It's pasted once and stored **only in the iOS Keychain** (`ServerTokenStore`, readable after first unlock); it's never shown again and never written to the source, Info.plist, UserDefaults or files. Replace Token / Remove Token are there if it changes.
  - **Test Connection:** checks `/api/health` first (no token, so "can't reach the server" and "wrong token" are told apart), then lists the server's music libraries with their song counts, each with a switch to include it in syncs. A library on a drive that isn't plugged into the PC shows "Drive not connected".
  - **Sync Now** with progress (songs checked of the library's total, songs downloaded, the song downloading now with its own bar) and **Stop**; afterwards a summary ("Synced 9:41 PM · 12 downloaded · 12 new in your library"). **Sync When Sun Opens** (off by default) runs it at launch.
  - Clear messages: a 401 means the token was rejected, a 502 means the server isn't running on the PC, and no connection means Tailscale isn't connected.
- **How a sync works** (`Sources/ServerSync.swift`, the server guide's algorithm): for each music library, read the change feed from the saved cursor (500 items a page); download each song that's missing on the phone or a different size; add the page's new songs to the library; then save the cursor, so a crash or Stop just repeats that page.
  - **Where files go:** `Documents/Music/<rel_path>`, the same `Artist/Album/Song` layout as imported music. The High-Res library goes into `Documents/Music/Hi-Res/` so its copies never overwrite the regular ones; Settings → Duplicates then decides which copy shows (Lossless keeps the hi-res one).
  - **Resumable downloads** (`PartFileDownload`): files stream into `<file>.part` as they arrive. After an interruption the next sync sends `Range: bytes=<part size>-`: a 206 reply appends, a 200 reply starts over. The finished file keeps the server's modification date.
  - **Added as they download:** every 10 songs (or 20 seconds), not only at the end of a 500-item page, so a sync that's stopped or interrupted keeps the songs it finished. Before each sync and at launch, any song file in `Documents/Music` that isn't in the library yet (left by an interrupted sync) is added too (`LibraryActions.addMissingFiles`); unfinished `.part` files are left to resume.
  - **Adding to the library:** downloaded files go through the same steps as importing (`LibraryImporter.indexInPlace`: tags, embedded or folder cover, audio format), so artists, albums, duplicates and Lossless Only work the same. If the file has no cover, the server's (`/api/items/{id}/cover`) is used. A newer version of a song already in the library updates it in place. Files already on the phone but not yet in the library (e.g. the app closed mid-sync) are added too.
  - Each downloaded song remembers its server id and key (`Track.serverID`, `Track.serverKey` = "library:rel_path"), the cross-device identity for syncing stats, favorites and playlists later.
  - **Songs from the Server** (in Media Server) lists every downloaded song, with how many are shown in place of a copy you already had. A server FLAC of a song you had as an MP3 doesn't appear as a new song: Duplicates shows the FLAC in the MP3's place.
  - **Songs removed on the server are never deleted from the phone.**
  - A big first sync should run with the app open: iOS gives a little extra time after leaving (`beginBackgroundTask`), then pauses it; the next sync continues from the cursor and any part-downloaded file.
- **Client** (`Sources/MediaServerClient.swift`): `MediaServerClient` (health, libraries, the item change feed, covers, resumable downloads; Bearer token on every request except health), and `LocalServerSongSource`, the server as a `SongSource` (lists songs not downloaded yet). Streaming isn't wired up: the player plays files on the phone.
- **Not wired yet:** syncing listening stats, favorites and playlists through the server (the server supports it; it's the next step).

### Lossless and duplicates
- **Audio format** (`Library/AudioFormat.swift`): each song's codec (FLAC, ALAC, uncompressed, AAC, MP3, Opus), sample rate, bit depth (lossless files) and average bitrate are read from the file header when it's imported, and saved on the song (`Track.codec`, `sampleRate`, `bitDepth`, `bitRate`). Songs imported earlier get theirs once, in the background at launch (`LibraryActions.backfillAudioFormats`). Until then, the file extension decides (".m4a" counts as lossy, since it can be either).
- **Duplicates** (`Library/Duplicates.swift`): a song is in the library more than once when the title (ignoring case, accents and extra spaces) and main artist match and the lengths are within 3 seconds. So a single and its album version match; live versions and remixes don't; songs with an unknown length are never matched.
  - One copy stays; the others are **hidden, not deleted**: left out of every list, search, shuffle, genre, artist page, artist count and the lyrics download. They still play from playlists (tapping one plays it; the rest of the queue skips copies).
  - Worked out with the artist index, only when the library or the setting changes (`LibraryIndexStore.rebuild`, `ArtistIndex.hiddenCopies`).
- **Settings → Duplicates** (`UI/DuplicatesSettings.swift`):
  - **Copy to Keep:** **Lossless** (default): a lossless copy beats MP3/AAC; between equals, the one added first. **Best Quality:** lossless first, then the highest sample rate and bit depth (hi-res), then the highest bitrate. Changing it updates the library at once.
  - **Hidden Copies:** each hidden copy with the one shown in its place and both formats ("Uncompressed · 32-bit/44.1 kHz · Northern Lights" / "AAC · 109 kbps · Satellite (Single)").
- **Demo:** `SUN_DEMO_LIBRARY=1` adds two AAC songs: a lossy copy of Aurora Vale's "Satellite" (hidden, the lossless one stays) and "Radio Edit" (only AAC, so Lossless Only hides it).

### App name and icon
- The name under the icon is **Sun** (target → General → Display Name, `INFOPLIST_KEY_CFBundleDisplayName`).
- The icon is a Liquid Glass Icon Composer file, `AppIcon.icon`, in the app folder (made in Xcode → Open Developer Tool → Icon Composer). For Xcode to compile it, the target's **General → App Icons and Launch Screen → App Icon** must say `AppIcon`.

### Lyrics
Ported from the desktop app (`lyrics.py`, `lyrics_view.py`, `lyrics_manager.py`).
- **Lyrics page** (`UI/Player/LyricsPage.swift`): Now Playing's pager is now **Cover · Lyrics · Queue · EQ**, with a Lyrics button in the switcher. The page sits on the same glass panel as Queue and EQ.
  - **Synced lyrics:** the line being sung is highlighted (bold, slightly larger, in the lighter accent; past lines dimmer than upcoming ones) and kept in the middle. It's highlighted 0.15 s early so it feels on time. After scrolling by hand, following pauses for 4 s. Tapping a line jumps the song there, also while paused (the scrubber and highlight refresh through `PlayerEngine.positionChanges`).
  - **Plain lyrics** just scroll.
  - **Messages:** "Instrumental", "No lyrics found for this song", or "Couldn't reach lrclib.net" with **Retry**. "Lyrics from LRCLIB" is credited under lyrics from there.
  - **Efficient:** the position is read 10 times a second only while playing, and the lines only redraw when the current line changes.
- **Where lyrics come from** (`LyricsStore`), in order:
  1. memory, then the saved copy on the phone (`Application Support/Lyrics/<song id>.json`);
  2. lyrics stored in the song file (ID3 USLT, iTunes ©lyr, the file's lyrics), `EmbeddedLyricsProvider`;
  3. **lrclib.net** (`LRCLIBProvider`), the same way as the desktop: `get-cached`, then `get` (if it's too busy, the search still runs, but a "not found" then isn't kept), then `search`, picking the closest length within ±5 s with synced lyrics preferred. "feat./ft./with" parts are left out of the names; 8 s timeout, one retry. Requests identify the app (`Sun-iOS/<version>`).
  - Found lyrics and instrumentals are kept for good; "no lyrics" for a week (then checked again); network errors are never kept.
- **Settings → Lyrics** (`UI/LyricsSettings.swift`):
  - **Download All Lyrics** looks up every song, hidden artists included (like the desktop, so the missing list is complete), one at a time so LRCLIB isn't flooded. While it runs the row shows "Downloading Lyrics 34 / 210" with a progress bar and **Stop**; afterwards a row sums it up ("Done. Found 180 · 25 without lyrics · 5 couldn't be checked"). The rows stay in place, so the list doesn't jump. Keep the app open: iOS gives it a little time after you leave, then pauses it.
  - **Search Again for Missing** looks up only the songs without lyrics again, forgetting their saved "no lyrics" first.
  - **Missing Lyrics** lists those songs by artist (tap to play). Songs without lyrics also get a small mark (`text.badge.xmark`, VoiceOver "No lyrics") in every song list.
  - Bulk-downloaded lyrics are kept on disk only (not in memory), and the missing list is published at most once a second, so song lists don't redraw for every song.
- **Demo:** with `SUN_DEMO_LIBRARY=1` (debug builds), generated synced lyrics are used for the demo songs, which don't exist on LRCLIB (`DemoLyricsProvider`); about one in five has none.

### Sources (groundwork for a local server)
`Sources/MediaSources.swift` defines where lyrics, songs and artist images come from, so a local server can be added later without changing the screens:
- `LyricsProvider` (lyrics for a `LyricsQuery`: found, instrumental, or not found, certain or not; throwing means "couldn't check"), `SongSource` (list `RemoteSong`s and give a URL to stream or download one), `ArtistImageSource` (image data for an artist).
- `MediaSources` holds them in the order they're asked. Today: `[EmbeddedLyricsProvider, LRCLIBProvider]`, and no extra song or image sources (songs are imported files, images come from Photos). A server type would conform to these protocols and go first in the lists.
- A self-hosted LRCLIB needs no new code: it's an `LRCLIBProvider` with a different `baseURL`.
- The media server (see Media Server above) now downloads songs into the library; `LocalServerSongSource` is its `SongSource`. Lyrics and artist images still come from the song file, LRCLIB and Photos.

### Playback reliability (shuffle fixes)
Tested against a real 1,587-song library on an iPhone (about 70% 44.1 kHz, 30% 48 kHz files):
- **Before:** once a 44.1 kHz song was followed by a 48 kHz one (or the reverse), the audio graph failed to rewire (`-10868`, format not supported). After that, every skip froze the app for about 5 seconds.
  - **Fix:** `PlayerEngine.reconnect(for:)` stops the engine while rewiring. It connects player → EQ → mixer in the file's own format, and the mixer converts to the hardware rate.
  - **Result:** 80 shuffled skips through the real library, with the worst skip at 150 ms and no audio errors.
- **Audio session:** it is activated once, not on every song, because activation can block the main thread. It's re-activated after the system ends an interruption.
- **Broken files:** files with no audio (zero length, zero sample rate or zero channels) are rejected instead of crashing the scheduler.
- **Stats tab:** it is recalculated in the background, and only when listening data changes. It used to redo the whole history on the main thread on every song change.
- **System integration:** lock screen, Control Center and headphone controls, and background playback. Playback pauses for calls and when headphones are unplugged.

### Crash after a number of songs (fixed)
- **Symptom:** after a while (often 100+ songs), the app froze on a song change or seek and iOS killed it. All 8 crash reports pulled from the phone were watchdog kills (`SIGKILL`, FrontBoard), not memory kills.
- **Cause:** a deadlock. The visualizer's audio tap (`SpectrumAnalyzer.attach(to:)`) called `node.outputFormat(forBus:)` for every buffer, which takes the audio engine's lock. Meanwhile, the main thread holds that lock in `engine.stop()` (on 44.1 ↔ 48 kHz switches) or `playerNode.stop()` (on seeks and song changes) and waits for the tap. If the timing lined up, both threads waited forever. It depended on timing, not on a particular song, so it appeared at random.
- **Fix:** the tap never calls back into the engine. The sample rate comes from the buffer itself (`buffer.format.sampleRate`).
- **Result:** 1,271 songs in a row on the iPhone in a single app run, with no freezes, no problems, and memory flat at 125–152 MB. Before the fix, sweeps were killed every few minutes.
- **Also fixed:**
  - **Seek failures:** a failed restart after a seek shows the player as paused instead of "playing" with no sound.
  - **Image cache:** the in-memory cache (`ArtCache`) is limited to 128 MB of decoded images as well as 300 items. One decoded full-size cover can take 16 MB.
  - **Visualizer:** redraws at most 60 times a second (its smoothing is designed in 1/60 s steps), and stops redrawing 1.5 s after playback pauses, once the lines are flat. This saves battery.

### Smooth playback while editing a theme (fixed)
Music stuttered when making a color theme during playback. Every theme change redraws every screen that uses theme colors (all tabs stay loaded), with their Liquid Glass and glows. A color-picker drag sent dozens of changes a second, and each one also wrote the theme to disk and restarted a 1.2 s animation in the theme preview. That kept the phone busy enough that the audio file reader fell behind. Fixes:
- **Batched edits** (`ThemeEditBuffer` in `UI/ThemeEditorView.swift`): color-picker drags and the Glass Opacity slider are collected and applied to the app about 12 times a second. The picker and slider still follow your finger instantly (they show the newest edit).
- **Cached colors** (`ResolvedColors` in `Theme/ThemeStore.swift`): every theme color is parsed and derived once per change, instead of parsing hex strings on every read (views read them thousands of times per redraw, and the visualizer 60 times a second).
- **Saving later:** the theme is saved half a second after the last change, and when the app leaves the foreground (`ThemeStore.saveNow()`), instead of on every step of a drag.
- **No restarting animation** on the theme preview; picking a preset still crossfades once.

### Performance and checks (2026-10-14)
- **Artist summaries cached:** the artists list (counts and latest-album circle cover) is worked out once per library change in `LibraryIndexStore.artists`, instead of walking the whole library on every redraw of the Artists grid, Home's Top Artists, Search and Member of….
- **Listening totals off the main thread:** crediting saved sessions to artists now runs in the background with the adding-up; the main thread only copies the sessions. This runs every 30 s during playback, when the current session is saved.
- **Name sorts don't re-sort during playback:** Songs, Albums, Artists and Genres only read the listening totals when a listening sort is chosen, so a name or title order isn't redone every 30 s.
- **Artwork shows instantly when cached:** `ArtworkView` uses an image already decoded in memory on its first frame (no placeholder flash when scrolling back), and clears the previous picture when its key changes.
- **Fewer blurred glows:** album headers on artist pages (pinned while scrolling) no longer draw a blurred glow under their glass.
- **No disk check per redraw** on artist pages (the transparency of the picture comes from the loaded image).
- **Checked:** no crash reports from the app on the iPhone since the audio-tap deadlock fix (2026-10-11), and in the system's memory-pressure reports from 2026-10-13 the app wasn't the one killed (it was suspended at 108 MB). Playback callbacks, the stats save loop, theme saving and edit batching hold weak references, so nothing keeps a closed screen or the player alive. The image cache is capped by memory (128 MB) as well as count.

### Stats
These follow the desktop rules:
- A session starts when a song loads, and again each time Repeat Song restarts it.
- Only time spent playing counts.
- Sessions under 5 seconds aren't saved.
- A song counts as a **play** after half its length or 4 minutes, whichever comes first.

The Stats tab (`UI/StatsView.swift`) uses the same compact header as Home and Library, with glass chips for **Week · Month · Year · All Time**. Then:
- **Hero card:** the period's listening time in large type, and a glowing ring (in the glow colors) showing how many of the period's days you listened, e.g. "Listened on 3 of 30 days". All Time counts from the first day you listened (`StatsView.activity`).
- **Tiles:** Plays, Songs and Artists, then Current Streak and Best, each with an accent-tinted icon.
- **Past Year heatmap** with rounded cells in the theme's Heatmap color (Primary).
- **Top Artists, Albums, Songs and Genres:** numbered badges (the #1 badge takes the ambient accent) and soft glowing bars in the theme's Stat Bars color.

It shows listening time, plays, songs and artists for the past week, month or year, or all time. Artist stats use the same credit rules as the library: a session of "Bad Bunny & Chuwi" counts for both Bad Bunny and Chuwi, not as a third artist. Older sessions are split from their saved artist text, so existing history is credited correctly too. It also has a heatmap of the past year, current and longest streaks, and top artists, albums, songs and genres.

### Themes
Go to Settings → **Theme**.
- **Built-in themes** (`ThemePreset`), based on common color combinations:

  | Theme | Primary | Secondary | Highlight |
  | --- | --- | --- | --- |
  | Sun (default, desktop) | blue | light blue | pink-red |
  | **Sunset** | **orange** | **blue** | **red** |
  | Ocean | teal | sky blue | coral |
  | Forest | green | lime | amber |
  | Royal | purple | gold | rose |
  | Neon | magenta | cyan | yellow |
  | Rosé | pink | peach | coral pink |
  | Ember | red | gold | orange |
  | Mono | light grey | grey | white |

- **Five colors (`ThemeRole`):** **Primary**, **Secondary**, **Highlight**, **Background** and **Text**. Every element follows one of them:

  | Role | Used for |
  | --- | --- |
  | Primary | Tab bar, buttons, sliders, stats, EQ |
  | Secondary | Wave bottom edge |
  | Highlight | Favorites and the wave top edge |
  | Background | Window and glass panels |
  | Text | Titles and labels |

  - **Removed:** the old per-element colors ("Auto" overrides). They're ignored in older saved themes, so every theme stays uniform.
  - **Derived colors:**
    - Glass panels are the background lifted 3% toward white.
    - The play-button icon is white if that gives at least 3:1 contrast on Primary, otherwise black (orange, teal and yellow get black icons).
    - Older saved themes get this icon color recalculated when they load.
- **Glass Panels:** **Glass Opacity** (10–90%, default 50%) controls every glass surface: rows, cards, headers, the tab bar and the mini player. Raise it if text is hard to read. Picking a built-in theme keeps your Glass Opacity.
  - Themes saved before this setting existed still load, because every palette key is decoded as optional.
- **Match Artwork** (on by default): glows and accents take their colors from the picture behind the player, the same one as the backdrop: the artist's picture (or their group's) when one is set, otherwise the playing song's cover. So the glow always matches the background, and both change together. This covers the glass rims and halos, the Play button, selected chips, the selected tab, the mini player's ring and progress line, and the playing song's title. Turn it off to use the theme's Primary and Highlight colors everywhere. Text, background and glass always follow the theme.
  - **How the colors are picked** (`Theme/ArtworkPalette.swift`): the cover's thumbnail is averaged down to an 8×8 grid. The most vivid cell becomes the main color, and the most vivid cell with a clearly different hue becomes the second one. Both are lifted so they glow on dark glass. Results are cached per cover and crossfade over 1.2 s between songs.
  - Nearly colorless covers (black-and-white photos) and songs without a cover use the theme colors.
  - Text on the accent is white or black by the same 3:1 rule as the theme. Accent-colored text on glass uses the accent lifted 40% toward white (`ambientAccentLight`), so it stays readable.
  - It's stored with the theme, and picking a built-in or saved theme keeps your setting, like Glass Opacity. Themes saved before it existed load with it on.
- **My Themes:** save the current colors under a name, reapply or delete them, or **Reset to Default**.
- **Live preview** at the top of Settings → Theme: built from the same pieces as Now Playing (glass card with glow rim, the playing song's cover and title, the glowing timeline bar, the wave colors, the glowing play button). With Match Artwork on it shows the playing cover's colors, and a caption says where the glow colors come from: the playing cover, the theme (Match Artwork off), or the theme because the cover has no strong colors.
- Changes apply live, and themes can be saved and reapplied. **Every new UI element should read its color from `ThemeStore`.**

### iPhone 15 Pro Max
- Animations can run at 120 Hz on ProMotion screens (`CADisableMinimumFrameDurationOnPhone`). The wave visualizer is capped at 60 fps to save battery.
- The Now Playing cover grows to fill the larger screen, up to 400 pt.

## Project layout

| Folder | Contents |
| --- | --- |
| `Models/` | SwiftData models: `Track`, `Playlist`, `ListenSession`, `ArtistImage` (the artist's one image), `ArtistBackdropStyle` (per-artist background settings), `ArtistBackground` (legacy, merged into `ArtistImage` at launch), `SavedTheme`, `HiddenArtist` |
| `Library/` | `LibraryImporter` (Files import + Album Artist and audio format backfill), `AudioFormat` (codec and quality from the file header), `Duplicates` (finding copies and which one stays), `TagReader` (tags, Album Artist, folder fallback), `ArtCache` (cover/thumb/blur images), `HiddenArtists` (hide rules and actions), `ArtistCredits` (credit parser, `ArtistIndex`, `LibraryIndexStore`) |
| `Debug/` | Debug-only tools: `AudioFixtures` (generated test audio and covers), `DemoLibrary`, `LibraryDiagnostics` |
| `Playback/` | `PlayerEngine` (AVAudioEngine + EQ, recovery), `QueueManager`, `SpectrumAnalyzer`, `NowPlayingBridge` (lock screen), `MusicPlayer` (ties it all together), `PlaybackIssues` (problem log) |
| `Lyrics/` | `Lyrics` (model, LRC parsing, current line), `LyricsProviders` (song file, LRCLIB, demo), `LyricsStore` (lookup chain, cache, missing list, Download All) |
| `Sources/` | `MediaSources` (protocols for where lyrics, songs and artist images come from), `MediaServerClient` (the media server's API, resumable downloads, `LocalServerSongSource`), `ServerSync` (downloading new music into the library), `Keychain` (`ServerTokenStore`, the device token) |
| `Stats/` | `ListeningRules`, `StatsRecorder`, `StatsSummary` / `StatsCalendar`, `ListeningTotals` (per song/artist/genre totals for the Library's listening sorts) |
| `Theme/` | `ThemePalette` (colors + Auto rules), `ThemeStore` (theme colors plus the glow and accent colors), `ArtworkPalette` (glow colors from the playing cover, Match Artwork) |
| `UI/` | Root tabs, Home, library screens (Songs, Albums, Artists, Genres, Playlists, Search), Now Playing (with its lyrics, queue and equalizer pages), stats, Settings (with Lyrics and Missing Lyrics) and theme editor |
| `Theme/` additions | `ThemeRole` (the five colors) and `ThemePreset` (built-in themes) in `ThemePalette.swift` |

## Storage
| Location | Contents |
| --- | --- |
| `Documents/Music/` | Imported audio, plus folder images copied with it |
| `Application Support/Art/` | Covers and artist pictures, in full, thumbnail and blurred versions |
| `Documents/Music/Hi-Res/` | Songs from the media server's High-Res library (regular server music goes straight into `Documents/Music/`) |
| Keychain | The media server device token (only there) |
| `Application Support/Lyrics/` | One JSON file per song with its looked-up lyrics (or "instrumental" / "none" and when) |
| `Application Support/lyrics-missing.json` | The songs whose lookup found no lyrics |
| SwiftData store | Library (including Album Artist and each song's audio format), favorites, playlists, per-song EQ, listening history, saved themes, hidden artists, artist images and their background settings (separate player and page framing), manual group links (`ArtistGroupLink`) |
| `UserDefaults` | Active theme (including Glass Opacity and Match Artwork), global EQ, sort orders (Songs, Artists, Genres), Lossless Only, the duplicate choice (Copy to Keep), the media server address, its sync cursor per library, which libraries to sync and Sync When Sun Opens, last Library section, Show Album Cover, playback problem log |

## Tests
The `Music AppTests` target (Swift Testing) covers:
- queue shuffle, repeat and editing (by offset and by entry id)
- listening rules
- stats totals and streaks
- theme color rules, and loading themes saved before Glass Opacity existed
- Stats: days listened in the period (only that period, ignoring zero-second days; All Time from the first day) and an empty history
- Home and albums: this week's top artists (only the past 7 days), recently played newest first, album totals and album sort orders
- listening sorts: totals per song, artist and genre; Most Listened, Most Played, Recently Played and Least Played orders; name order on ties; and the row details ("3 plays", "1h 5m")
- artwork glow colors: both hues from a two-color cover, colors bright enough to glow, colorless covers falling back to the theme, Match Artwork saving and loading (on for older themes), and glows using the theme when Match Artwork is off
- tag fallback from folder paths, including corrupted files
- spectrum bin mapping
- **Playback robustness:** these tests use generated audio only (`AudioFixtures`), never real music.
  - 44.1, 48, 96, 22 and 8 kHz files, mono and stereo, loaded back to back. Each load must take under 1 s.
  - Very short, empty and corrupted files.
  - Skipping unplayable songs, including a queue of only bad files with Repeat on.
  - Huge (5000 px) artwork being downsampled.
- hidden-artist rules: filtering, tap-to-play queue and removing their songs from Up Next, and the primary-artist rule
- Album Artist edge cases from a real library: database IDs, the same credit written differently, soundtrack collaborators, `;` and `×`
- stats credit every artist on a song, and album years match across artists' pages
- artist credits, using credit strings as they appear in a real library: feature markers, smart splitting, "X of Band", slashes, title features
- the artist index: features on both artists in the right album, group albums and members, guests who aren't members, compilations, manual groups
- crop geometry: the photo always covers the frame, and each framing keeps its shape (Whole Picture the image's own, Screen the phone's, Square)
- transparent artist pictures keep their transparency (stored as PNG, own shape kept), opaque ones are stored as before
- media server (against a pretend server with a made-up token, no network): songs finished before a sync stops are kept in the library while the cursor stays put; leftover downloads are added but `.part` files aren't; addresses normalized; a two-page sync downloads only the songs (not other files or deleted items) into the right folders, adds them with their server id and key, saves the cursor, sends the token on every request and skips book libraries; a second sync downloads nothing; an interrupted download resumes with a Range request (206 appends, 200 starts over); a rejected token or a closed server stops without moving the cursor; libraries on an unplugged drive are skipped; the token is kept in the Keychain
- audio formats: generated uncompressed and AAC files are read as lossless/lossy with their sample rate, bit depth and bitrate; Core Audio codec and bit-depth mapping; songs not yet read judged by extension; Lossless Only
- duplicates: the lossless copy stays by default; lengths must be within 3 s and the artist must match; Best Quality prefers hi-res, then bitrate; unknown lengths never match; hidden copies leave lists and artist pages but play when tapped in a playlist
- lyrics: LRC parsing (several time tags, offset, both fraction formats, metadata skipped), synced vs plain, the current line with its lead, feat. parts left out; LRCLIB best match (±5 s, synced first) and responses from a stubbed network (cached answer first; a busy full lookup falls back to search and isn't certain; instrumental); the store with a fake provider (missing list rules, errors not kept, answers kept across launches, "none" checked again after a week, Download All counts and Search Again only re-checking missing songs)
- separate background framing: player and page framings are independent, and styles saved before the split give the page the player's framing
- theme performance: cached colors match the palette for every preset and element, the store updates them with the palette, and rapid edits are batched (the controls show the newest edit at once, the theme catches up within 250 ms)
- artist circles show the latest album cover (newest year, then most recently added; own albums before guest spots); background settings saved per artist, members using their group's; where the picture goes for Whole Picture, Fill Screen, zoom and move (player and artist page); the standard look matches the old backdrop
- artist images: separate backgrounds from an earlier build merge into the artist's one image (the background wins) and are deleted, and the artist page's picture area (full-width height, between 42% and 62% of the screen)
- skipped songs: retried once, logged with a reason, and named in the message
- theme roles, derived contrast colors, the built-in presets (Sunset really is orange, blue and red), and older themes with per-element colors
- songs ending on their own: a mixed-format queue advances to the end with no main-thread stall over 500 ms

To run it, select the **Music AppTests** scheme, pick a simulator, and choose Product → Test. Use a simulator so test files aren't written into a phone's real library.

## Debug tools
These are Debug builds only. Set the environment variables in Product → Scheme → Edit Scheme → Run → Arguments.
- `SUN_DEMO_LIBRARY=1`: fills an empty library with generated songs (sine tones at mixed sample rates, with gradient covers) for testing the UI in the simulator.
- `SUN_TAG_CHECK=1`: read-only report of artist credits, Album Artist tags, file protection and every inferred member → group link (with the song that caused it), prefixed `[Tags]`.
- `SUN_DEMO_LIBRARY=1` also gives two demo artists generated pictures: Aurora Vale a wide 16:9 one with white bars at its left and right edges (any cropping is easy to spot), and Kenji Sato a transparent cut-out figure (for the outline glow).
- `SUN_DEMO_LIBRARY=1` also adds generated credit examples: a group album "PRISM TEN" with member solo songs, songs with featured artists, and the band "Of Mice & Men".
- `SUN_DIAGNOSTICS=1`: on launch, opens every file in the library and prints its format and any failures. Then it plays **every song** through the real player, muted.
  - For each song it checks that audio starts, seeks to the middle, then jumps to the end and checks the song finishes by itself.
  - It flags main-thread calls slower than 250 ms, and logs the app's memory use (and how much is left before iOS would kill it) for every song.
  - Progress is saved before each song (`Caches/diag-sweep-v2.json`). If the app crashes, the next launch records that song as a crash suspect and carries on with the next one.
  - A full library of 1,587 songs takes about 30 minutes, and the screen is kept awake. Output is prefixed `[Diag]` in the Xcode console.
  - It replaces the current queue but saves no stats, since each song plays for less than 5 s.
